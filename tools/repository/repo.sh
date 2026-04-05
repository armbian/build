#!/usr/bin/env bash

# Global variables
DRY_RUN=false              # Full dry-run: don't make any repository changes
KEEP_SOURCES=false         # Keep source packages when adding to repo (don't delete)
SINGLE_RELEASE=""          # Process only a single release (for GitHub Actions parallel workflow)
FORCE_ADD=false            # Force re-adding packages even if they already exist in repo
FORCE_PUBLISH=true         # Force publishing even when no packages to add

# Logging function - uses syslog, view logs with: journalctl -t repo-management -f
# Arguments:
#   $* - Message to log
log() {
    logger -t repo-management "$*"
}

# Execute aptly command and check for errors
# Exits with status 1 if the command fails (unless in dry-run mode)
# Arguments:
#   $* - Aptly command to execute (without 'aptly' prefix)
run_aptly() {
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would execute: aptly $*"
        return 0
    fi

    if ! aptly "$@"; then
        local exit_code=$?
        log "ERROR: aptly $* failed with exit code $exit_code"
        exit 1
    fi
}

# Drop published repositories that are no longer supported
# Identifies and removes published repositories for releases that are no longer
# in config/distributions/*/support (excluding 'eos')
# Arguments:
#   $1 - "all" to drop all published repositories, otherwise drops only unsupported ones
drop_unsupported_releases() {
	local supported_releases=()
	local published_repos=()
	local repos_to_drop=()

	# Determine which releases should be kept
	if [[ "$1" == "all" ]]; then
		log "Cleanup: dropping all published repositories"
		supported_releases=()
	else
		log "Cleanup: dropping unsupported releases"
		supported_releases=($(grep -rw config/distributions/*/support | cut -d"/" -f3))
	fi

	# Get currently published repositories
	published_repos=($(aptly publish list -config="${CONFIG}" --raw | sed "s/. //g"))

	# Find repos to drop (published but not supported)
	for repo in "${published_repos[@]}"; do
		local should_keep=false
		for supported in "${supported_releases[@]}"; do
			[[ "$repo" == "$supported" ]] && { should_keep=true; break; }
		done
		[[ "$should_keep" == false ]] && repos_to_drop+=("$repo")
	done

	# Drop the identified repositories
	for repo in "${repos_to_drop[@]}"; do
		run_aptly publish drop -config="${CONFIG}" "${repo}"
	done
}
# Display contents of all repositories
# Shows packages in the common repository and release-specific repositories (utils, desktop)
# In single-release mode, shows content from isolated database
# Otherwise, shows content from main database and any existing isolated databases
# Uses global DISTROS array for iteration, or discovers repos automatically if DISTROS is empty
showall() {
	echo "Displaying common repository contents"
	aptly repo show -with-packages -config="${CONFIG}" common 2>/dev/null | tail -n +7

	# If DISTROS array is empty, discover repos from the database
	local releases_to_show=("${DISTROS[@]}")
	if [[ ${#DISTROS[@]} -eq 0 ]]; then
		# First, discover releases from isolated databases
		local all_repos=()
		if [[ -d "$output" ]]; then
			for isolated_dir in "$output"/aptly-isolated-*; do
				if [[ -d "$isolated_dir" ]]; then
					local release_name=$(basename "$isolated_dir" | sed 's/aptly-isolated-//')
					all_repos+=("$release_name")
				fi
			done
		fi
		# Also get repos from main database (for non-isolated repos)
		local main_repos
		main_repos=($(aptly repo list -config="${CONFIG}" -raw 2>/dev/null | awk '{print $NF}' | grep -E '^.+-(utils|desktop)$' | sed 's/-(utils|desktop)$//' | sort -u))
		# Merge and deduplicate
		all_repos+=("${main_repos[@]}")
		releases_to_show=($(echo "${all_repos[@]}" | tr ' ' '\n' | sort -u))
	fi

	for release in "${releases_to_show[@]}"; do
		# In single-release mode, only show that specific release from the isolated database
		if [[ -n "$SINGLE_RELEASE" ]]; then
			if [[ "$release" != "$SINGLE_RELEASE" ]]; then
				continue
			fi
		fi

		# Check if there's an isolated database for this release
		local isolated_db="${output}/aptly-isolated-${release}"
		local show_config="$CONFIG"

		if [[ -d "$isolated_db" ]]; then
			# Create temporary config for the isolated database
			local temp_config
			temp_config="$(mktemp)"
			sed 's|"rootDir": ".*"|"rootDir": "'$isolated_db'"|g' tools/repository/aptly.conf > "$temp_config"
			show_config="$temp_config"
		fi

		# Show utils repo if it exists
		if aptly repo show -config="${show_config}" "${release}-utils" &>/dev/null; then
			echo "Displaying repository contents for $release-utils"
			aptly repo show -with-packages -config="${show_config}" "${release}-utils" | tail -n +7
		fi

		# Show desktop repo if it exists
		if aptly repo show -config="${show_config}" "${release}-desktop" &>/dev/null; then
			echo "Displaying repository contents for $release-desktop"
			aptly repo show -with-packages -config="${show_config}" "${release}-desktop" | tail -n +7
		fi

		# Clean up temp config if we created one
		if [[ -n "$temp_config" && -f "$temp_config" ]]; then
			rm -f "$temp_config"
		fi
	done
}


# Add packages to an aptly repository component
# Processes .deb files from a source directory, optionally repacking BSP packages
# to pin kernel versions, then adds them to the specified repository
# Arguments:
#   $1 - Repository component name (e.g., "common", "jammy-utils")
#   $2 - Subdirectory path relative to input folder (e.g., "", "/extra/jammy-utils")
#   $3 - Description (unused, for documentation only)
#   $4 - Base input folder containing packages
adding_packages() {
	local component="$1"
	local subdir="$2"
	local input_folder="$4"
	local package_dir="${input_folder}${subdir}"

	# Check if any .deb files exist in the directory
	if ! find "$package_dir" -maxdepth 1 -type f -name "*.deb" 2> /dev/null | grep -q .; then
		return 0
	fi

	# Get list of packages already in repo for deduplication check
	# Use associative array for O(1) lookup performance
	local -A repo_packages_map
	if [[ "$FORCE_ADD" != true ]]; then
		log "Building package list from $component for deduplication check..."
		# Read aptly output line by line and parse properly
		# aptly output format: "  name_version_arch" (has leading spaces)
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			# Trim leading/trailing whitespace from line
			line="${line#"${line%%[![:space:]]*}"}"
			line="${line%"${line##*[![:space:]]}"}"
			[[ -z "$line" ]] && continue
			# aptly repo show -with-packages outputs packages as: name_version_arch
			# Split by underscore to get name, version, arch
			# But version can contain underscores (e.g., 25.11.0-trunk.502), so we need to be careful
			# Format: name_version_arch where arch is last field, version is everything before arch after name
			local name version arch
			# Get architecture (last field after last underscore)
			arch="${line##*_}"
			# Remove architecture from line to get name_version
			local temp="${line%_*}"
			# Get package name (first field before first underscore)
			name="${temp%%_*}"
			# Get version (everything between first and last underscore)
			version="${temp#*_}"
			[[ -z "$name" || -z "$version" || -z "$arch" ]] && continue
			repo_packages_map["${name}|${version}|${arch}"]=1
		done < <(aptly repo show -with-packages -config="${CONFIG}" "$component" 2>/dev/null | tail -n +7)
		log "Built lookup map with ${#repo_packages_map[@]} unique packages in $component"
	fi

	# Process each .deb file
	for deb_file in "${package_dir}"/*.deb; do
		# Get package info using dpkg-deb -f to get reliable format
		# Single call to get all fields at once (faster than 3 separate calls)
		local deb_info deb_name deb_version deb_arch
		deb_info=$(dpkg-deb -f "$deb_file" Package Version Architecture 2>/dev/null)
		deb_name=$(echo "$deb_info" | sed -n '1s/Package: //p')
		deb_version=$(echo "$deb_info" | sed -n '2s/Version: //p')
		deb_arch=$(echo "$deb_info" | sed -n '3s/Architecture: //p')

		# Create full identifier using pipe as separator (won't appear in package names)
		local deb_key="${deb_name}|${deb_version}|${deb_arch}"
		local deb_display="${deb_name}_${deb_version}_${deb_arch}"

		log "Checking package: $deb_display"

		# Skip if exact package (name+version+arch) already exists in repo (unless FORCE_ADD is true)
		if [[ "$FORCE_ADD" != true && -n "${repo_packages_map[$deb_key]}" ]]; then
			echo "[-] SKIP: $deb_display"
			log "SKIP: $deb_display already in $component"
			continue
		fi

		# Repack BSP packages if last-known-good kernel map exists
		# This prevents upgrading to kernels that may break the board
		if [[ -f userpatches/last-known-good.map ]]; then
			local package_name
			package_name=$(dpkg-deb -W "$deb_file" | awk '{ print $1 }')

			# Read kernel pinning mappings from file
			while IFS='|' read -r board branch linux_family last_kernel; do
				if [[ "${package_name}" == "armbian-bsp-cli-${board}-${branch}" ]]; then
					echo "Setting last kernel upgrade for $board to linux-image-$branch-$board=${last_kernel}"

					# Extract, modify control file, and repackage
					local tempdir
					tempdir=$(mktemp -d)
					dpkg-deb -R "$deb_file" "$tempdir"
					sed -i '/^Replaces:/ s/$/, linux-image-'$branch'-'$linux_family' (>> '$last_kernel'), linux-dtb-'$branch'-'$linux_family' (>> '$last_kernel')/' "$tempdir/DEBIAN/control"
					dpkg-deb -b "$tempdir" "${deb_file}" >/dev/null
					rm -rf "$tempdir"
				fi
			done < userpatches/last-known-good-kernel-pkg.map
		fi

		# Determine whether to remove source files after adding to repo
		# KEEP_SOURCES mode preserves source packages
		# DRY_RUN mode also preserves sources (and skips all repo modifications)
		# SINGLE_RELEASE mode preserves sources so parallel workers don't delete files needed by other workers
		local remove_flag="-remove-files"
		if [[ "$KEEP_SOURCES" == true ]] || [[ "$DRY_RUN" == true ]] || [[ -n "$SINGLE_RELEASE" ]]; then
			remove_flag=""
		fi

		# Add package to repository
		log "Adding $deb_name to $component"
		run_aptly repo add $remove_flag -force-replace -config="${CONFIG}" "${component}" "${deb_file}"
	done
}


# Build the common (main) repository component
# Creates/updates the common repository that contains packages shared across all releases
# Should be run once before processing individual releases in parallel
# Arguments:
#   $1 - Input folder containing packages
#   $2 - Output folder for published repository
#   $3 - GPG password for signing (currently unused, signing is done separately)
update_main() {
	local input_folder="$1"
	local output_folder="$2"
	local gpg_password="$3"

	log "Building common (main) component"

	# Create common repo if it doesn't exist
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
		run_aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | logger -t repo-management >/dev/null
	fi

	# Add packages from main folder
	adding_packages "common" "" "main" "$input_folder"

	# Drop old snapshot if it exists and is not published
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
		# Check if snapshot is published
		if ! aptly publish list -config="${CONFIG}" 2>/dev/null | grep -q "common"; then
			run_aptly -config="${CONFIG}" snapshot drop common | logger -t repo-management >/dev/null
		else
			log "WARNING: common snapshot is published, cannot drop. Packages added to repo but snapshot not updated."
			log "Run 'update' command to update all releases with new packages."
			return 0
		fi
	fi

	# Create new snapshot if it doesn't exist or was dropped
	if [[ -z $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
		run_aptly -config="${CONFIG}" snapshot create common from repo common | logger -t repo-management >/dev/null
	else
		log "common snapshot already exists, skipping creation"
	fi

	log "Common component built successfully"
}

# Process a single release distribution
# Creates/updates release-specific repositories (utils, desktop), publishes them,
# and signs the Release files. Can be run in parallel for different releases.
# Arguments:
#   $1 - Release name (e.g., "jammy", "noble")
#   $2 - Input folder containing packages
#   $3 - Output folder for published repository
#   $4 - GPG password for signing
process_release() {
	local release="$1"
	local input_folder="$2"
	local output_folder="$3"
	local gpg_password="$4"

	log "Processing release: $release"

	# In isolated mode (SINGLE_RELEASE), workers do NOT build common repo
	# Common component is built separately by 'update-main' command and merged later
	# This avoids duplicate work when running in parallel
	if [[ -n "$SINGLE_RELEASE" ]]; then
		log "Isolated mode: skipping common repo (will be merged by 'merge' command)"
	fi

	# Create release-specific repositories if they don't exist
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
		run_aptly repo create -config="${CONFIG}" -component="${release}-utils" -distribution="${release}" -comment="Armbian ${release}-utils repository" "${release}-utils" | logger -t repo-management >/dev/null
	fi
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
		run_aptly repo create -config="${CONFIG}" -component="${release}-desktop" -distribution="${release}" -comment="Armbian ${release}-desktop repository" "${release}-desktop" | logger -t repo-management >/dev/null
	fi

	# Add packages ONLY from release-specific extra folders
	adding_packages "${release}-utils" "/extra/${release}-utils" "release utils" "$input_folder"
	adding_packages "${release}-desktop" "/extra/${release}-desktop" "release desktop" "$input_folder"

	# Run db cleanup before publishing to remove unreferenced packages
	# This helps avoid "file already exists and is different" errors
	log "Running database cleanup before publishing"
	run_aptly db cleanup -config="${CONFIG}"

	# Check if we have any packages to publish
	# Get package counts in each repo
	local utils_count=$(aptly repo show -config="${CONFIG}" "${release}-utils" 2>/dev/null | grep "Number of packages" | awk '{print $4}' || echo "0")
	local desktop_count=$(aptly repo show -config="${CONFIG}" "${release}-desktop" 2>/dev/null | grep "Number of packages" | awk '{print $4}' || echo "0")

	log "Package counts for $release: utils=$utils_count, desktop=$desktop_count"

	# Always publish - even if no release-specific packages, we still need to publish common/main
	# Check if this release was previously published for logging
	if [[ "$utils_count" -eq 0 && "$desktop_count" -eq 0 && "$FORCE_PUBLISH" != true ]]; then
		if ! aptly publish list -config="${CONFIG}" 2>/dev/null | grep -q "^\[${release}\]"; then
			log "No release-specific packages for $release. Publishing common/main component only."
		else
			log "No new packages but $release was previously published. Will publish with common only."
		fi
	fi

	if [[ "$FORCE_PUBLISH" == true ]]; then
		log "Force publish enabled: will publish even with no packages"
	fi

	# Drop old snapshots if we have new packages to add OR if FORCE_PUBLISH is enabled
	# This ensures fresh snapshots are created for force-publish scenarios
	if [[ "$utils_count" -gt 0 || "$FORCE_PUBLISH" == true ]]; then
		if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
			log "Dropping existing ${release}-utils snapshot"
			run_aptly -config="${CONFIG}" snapshot drop ${release}-utils | logger -t repo-management 2>/dev/null
		fi
	fi
	if [[ "$desktop_count" -gt 0 || "$FORCE_PUBLISH" == true ]]; then
		if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			log "Dropping existing ${release}-desktop snapshot"
			run_aptly -config="${CONFIG}" snapshot drop ${release}-desktop | logger -t repo-management 2>/dev/null
		fi
	fi

	# Create snapshots only for repos that have packages
	# OR when FORCE_PUBLISH is enabled (then we publish whatever exists in the DB)
	# In isolated mode, do NOT include common snapshot - it will be merged later
	local components_to_publish=()
	local snapshots_to_publish=()

	# Only add common/main component if NOT in isolated mode
	if [[ -z "$SINGLE_RELEASE" ]]; then
		components_to_publish=("main")
		snapshots_to_publish=("common")
	fi

	if [[ "$utils_count" -gt 0 || "$FORCE_PUBLISH" == true ]]; then
		# Only create snapshot if repo has packages, or if force-publishing
		if [[ "$utils_count" -gt 0 ]]; then
			run_aptly -config="${CONFIG}" snapshot create ${release}-utils from repo ${release}-utils | logger -t repo-management >/dev/null
			components_to_publish+=("${release}-utils")
			snapshots_to_publish+=("${release}-utils")
		elif [[ "$FORCE_PUBLISH" == true ]]; then
			log "Force publish: checking for existing ${release}-utils snapshot in DB"
			# Try to use existing snapshot if it exists
			if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
				components_to_publish+=("${release}-utils")
				snapshots_to_publish+=("${release}-utils")
				log "Using existing ${release}-utils snapshot"
			else
				# Create empty snapshot from empty repo
				run_aptly -config="${CONFIG}" snapshot create ${release}-utils from repo ${release}-utils | logger -t repo-management >/dev/null
				components_to_publish+=("${release}-utils")
				snapshots_to_publish+=("${release}-utils")
				log "Created empty ${release}-utils snapshot for force publish"
			fi
		fi
	fi

	if [[ "$desktop_count" -gt 0 || "$FORCE_PUBLISH" == true ]]; then
		# Only create snapshot if repo has packages, or if force-publishing
		if [[ "$desktop_count" -gt 0 ]]; then
			run_aptly -config="${CONFIG}" snapshot create ${release}-desktop from repo ${release}-desktop | logger -t repo-management >/dev/null
			components_to_publish+=("${release}-desktop")
			snapshots_to_publish+=("${release}-desktop")
		elif [[ "$FORCE_PUBLISH" == true ]]; then
			log "Force publish: checking for existing ${release}-desktop snapshot in DB"
			# Try to use existing snapshot if it exists
			if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
				components_to_publish+=("${release}-desktop")
				snapshots_to_publish+=("${release}-desktop")
				log "Using existing ${release}-desktop snapshot"
			else
				# Create empty snapshot from empty repo
				run_aptly -config="${CONFIG}" snapshot create ${release}-desktop from repo ${release}-desktop | logger -t repo-management >/dev/null
				components_to_publish+=("${release}-desktop")
				snapshots_to_publish+=("${release}-desktop")
				log "Created empty ${release}-desktop snapshot for force publish"
			fi
		fi
	fi

	log "Publishing $release with components: ${components_to_publish[*]}"

	# Determine publish directory based on mode
	local publish_dir="$output_folder"
	if [[ -n "$SINGLE_RELEASE" ]]; then
		publish_dir="$IsolatedRootDir"
	fi

	# In isolated mode, do NOT publish - only create repos and snapshots
	# The merge command will handle all publishing with common component included
	if [[ -n "$SINGLE_RELEASE" ]]; then
		log "Isolated mode: skipping publishing (merge command will publish with common component)"
		log "Created repos and snapshots for $release in isolated database"
		return 0
	fi

	# Publish - include common snapshot for main component
	log "Publishing $release"

	# Drop existing publish for this release if it exists to avoid "file already exists" errors
	if aptly publish list -config="${CONFIG}" 2>/dev/null | grep -q "^\[${release}\]"; then
		log "Dropping existing publish for $release"
		run_aptly publish drop -config="${CONFIG}" "${release}"
	fi

	# Build publish command with only components that have packages
	local component_list=$(IFS=,; echo "${components_to_publish[*]}")
	local snapshot_list="${snapshots_to_publish[*]}"

	log "Publishing with components: $component_list"
	log "Publishing with snapshots: $snapshot_list"

	# Skip publishing if no components to publish (shouldn't happen, but safety check)
	if [[ ${#components_to_publish[@]} -eq 0 ]]; then
		log "WARNING: No components to publish for $release"
		return 0
	fi

	run_aptly publish \
		-skip-signing \
		-skip-contents \
		-architectures="armhf,arm64,amd64,riscv64,i386,loong64,all" \
		-passphrase="${gpg_password}" \
		-origin="Armbian" \
		-label="Armbian" \
		-config="${CONFIG}" \
		-component="$component_list" \
		-distribution="${release}" snapshot $snapshot_list

	# Sign Release files for this release
	# This includes:
	# 1. Top-level Release file (dists/{release}/Release)
	# 2. Component-level Release files (dists/{release}/{component}/Release)
	# Only sign in non-isolated mode (isolated mode is signed by merge command)
	log "Starting signing process for $release"
	# Use shared output location for signing
	local release_pub_dir="${output_folder}/public/dists/${release}"

	# Get GPG keys from environment or use defaults
	# Use BOTH keys for signing, just like the signing() function does
	local gpg_keys=()
	if [[ -n "$GPG_KEY" ]]; then
		gpg_keys=("$GPG_KEY")
	else
		gpg_keys=("DF00FAF1C577104B50BF1D0093D6889F9F0E78D5" "8CFA83D13EB2181EEF5843E41EB30FAF236099FE")
	fi

	local gpg_params=("--yes" "--armor")
	local keys_found=0

	# Add all available keys to GPG parameters
	for gpg_key in "${gpg_keys[@]}"; do
		# Try to find the actual key in the keyring
		local actual_key=""
		if gpg --list-secret-keys "$gpg_key" >/dev/null 2>&1; then
			actual_key="$gpg_key"
		else
			# Try to find by email or partial match
			actual_key=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -B1 "$gpg_key" | grep "sec" | awk '{print $2}' | cut -d'/' -f2 || echo "")
		fi

		if [[ -n "$actual_key" ]]; then
			gpg_params+=("-u" "$actual_key")
			log "Adding GPG key for signing: $actual_key (requested: $gpg_key)"
			((keys_found++))
		else
			log "WARNING: GPG key $gpg_key not found in keyring"
		fi
	done

	if [[ $keys_found -eq 0 ]]; then
		log "ERROR: No GPG keys found in keyring"
		log "Available keys:"
		gpg --list-secret-keys --keyid-format LONG 2>&1 | logger -t repo-management
		return 1
	fi

	log "Using $keys_found GPG key(s) for signing"

	# First, create component-level Release files by copying from binary-amd64 Release
	# This is needed because aptly only creates Release files in binary-* subdirs
	for component in main ${release}-utils ${release}-desktop; do
		local component_dir="${release_pub_dir}/${component}"
		if [[ -d "$component_dir" ]]; then
			# Use the binary-amd64 Release file as the component Release file
			local source_release="${component_dir}/binary-amd64/Release"
			local target_release="${component_dir}/Release"

			if [[ -f "$source_release" && ! -f "$target_release" ]]; then
				log "Creating component Release file: ${target_release}"
				cp "$source_release" "$target_release" 2>&1 | logger -t repo-management
			fi
		fi
	done

	# Now sign all Release files (both top-level and component-level)
	# Find all Release files except those in binary-* subdirectories
	find "${release_pub_dir}" -type f -name "Release" | while read -r release_file; do
		# Skip binary-* subdirectories
		if [[ "$release_file" =~ /binary-[^/]+/Release$ ]]; then
			continue
		fi

		log "Signing: ${release_file}"
		local sign_dir="$(dirname "$release_file")"

		if gpg "${gpg_params[@]}" --clear-sign -o "${sign_dir}/InRelease" "$release_file" 2>&1 | logger -t repo-management >/dev/null; then
			gpg "${gpg_params[@]}" --detach-sign -o "${sign_dir}/Release.gpg" "$release_file" 2>&1 | logger -t repo-management >/dev/null
			log "Successfully signed: ${release_file}"
		else
			log "ERROR: Failed to sign: ${release_file}"
		fi
	done

	log "Completed processing release: $release"
}

# Publish repositories for all configured releases
# Builds common component, processes each release, and finalizes the repository
# Arguments:
#   $1 - Input folder containing packages
#   $2 - Output folder for published repository
#   $3 - Command name (unused, for compatibility)
#   $4 - GPG password for signing
#   $5 - Comma-separated list of releases (unused, determined from config)
publishing() {
	# Only build common repo if NOT in single-release mode
	# In single-release mode, common should be built separately with 'update-main' command
	if [[ -z "$SINGLE_RELEASE" ]]; then
		# This repository contains packages that are the same in all releases
		if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
			run_aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | logger -t repo-management >/dev/null
		fi

		# Add packages from main folder
		adding_packages "common" "" "main" "$1"

		# Create snapshot
		if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
			run_aptly -config="${CONFIG}" snapshot drop common | logger -t repo-management >/dev/null
		fi
		run_aptly -config="${CONFIG}" snapshot create common from repo common | logger -t repo-management >/dev/null
	else
		# Single-release mode: common component should be built separately with 'update-main'
		# and will be merged during the 'merge' command
		log "Single-release mode: skipping common component (will be merged later)"
		log "Common component should be built with: ./repo.sh -c update-main"
	fi

	# Get all distributions or use single release if specified
	local distributions=()
	if [[ -n "$SINGLE_RELEASE" ]]; then
		distributions=("$SINGLE_RELEASE")
		log "Single release mode: processing only $SINGLE_RELEASE"
	else
		distributions=($(grep -rw config/distributions/*/support -ve '' | cut -d"/" -f3))
	fi

	# Process releases sequentially
	if [[ -n "$SINGLE_RELEASE" ]]; then
		log "Processing single release: ${distributions[0]}"
	else
		log "Processing ${#distributions[@]} releases sequentially"
	fi
	for release in "${distributions[@]}"; do
		process_release "$release" "$1" "$2" "$4"
	done

	# Cleanup database
	run_aptly db cleanup -config="${CONFIG}"

	# Copy GPG key to repository
	mkdir -p "${2}"/public/
	# Remove existing key file if it exists to avoid permission issues
	rm -f "${2}"/public/armbian.key
	cp config/armbian.key "${2}"/public/

	# Write repository sync control file
	date +%s > ${2}/public/control

	# Display repository contents
	showall
}


# Sign repository Release files using GPG
# Creates InRelease and Release.gpg signature files for component-level Release files
# Arguments:
#   $1 - Output folder path containing published repository
#   $@ - GPG key IDs to use for signing
signing() {
    local output_folder="$1"
    shift
    local gpg_keys=("$@")

    if [[ ${#gpg_keys[@]} -eq 0 ]]; then
        echo "No GPG keys provided for signing." >&2
        return 1
    fi

    # Build GPG parameters with available keys
    local gpg_params=("--yes" "--armor")
    for key in "${gpg_keys[@]}"; do
        # Try to find the actual key in the keyring
        local actual_key=""
        if gpg --list-secret-keys "$key" >/dev/null 2>&1; then
            actual_key="$key"
        else
            # Try to find by email or partial match
            actual_key=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -B1 "$key" | grep "sec" | awk '{print $2}' | cut -d'/' -f2 || echo "")
            if [[ -z "$actual_key" ]]; then
                echo "Warning: GPG key $key not found on this system." >&2
                continue
            fi
        fi
        gpg_params+=("-u" "$actual_key")
        echo "Using GPG key: $actual_key (requested: $key)" >&2
    done

    # Sign top-level Release files for each distribution
    # Sign: dists/{release}/Release
    # Skip: dists/{release}/{component}/binary-*/Release (subdirs, not needed)
    find "$output_folder/public/dists" -maxdepth 2 -type f -name Release | while read -r release_file; do
        # Skip if file is in a subdirectory (component or binary subdir)
        # Only sign top-level dists/{release}/Release files
        local rel_path="${release_file#$output_folder/public/dists/}"
        # Count slashes - should have exactly 1 for top-level: {release}/Release
        local slash_count=$(echo "$rel_path" | tr -cd '/' | wc -c)

        if [[ $slash_count -eq 1 ]]; then
            local distro_path
            distro_path="$(dirname "$release_file")"
            echo "Signing release at: $distro_path" | logger -t repo-management
            gpg "${gpg_params[@]}" --clear-sign -o "$distro_path/InRelease" "$release_file"
            gpg "${gpg_params[@]}" --detach-sign -o "$distro_path/Release.gpg" "$release_file"
        fi
    done
}


# Finalize repository after parallel GitHub Actions workers have built individual releases
# Combines the common/main component (built by update-main) with release-specific
# components (built by parallel workers) into the final repository structure
# Arguments:
#   $1 - Base input folder (contains package sources, for consistency)
#   $2 - Output folder containing combined repository
merge_repos() {
	local input_folder="$1"
	local output_folder="$2"

	log "Merge mode: combining common component with release-specific components"

	# We need to use the main database to properly merge components
	# The main DB should have the common snapshot from update-main

	# Create a temp config pointing to the main DB (not isolated)
	local main_db_config
	main_db_config="$(mktemp)"
	sed 's|"rootDir": ".*"|"rootDir": "'$output_folder'"|g' tools/repository/aptly.conf > "$main_db_config"

	# Check if common snapshot exists in main DB
	local common_exists=false
	if [[ -n $(aptly -config="$main_db_config" snapshot list -raw 2>/dev/null | awk '{print $(NF)}' | grep "common") ]]; then
		common_exists=true
		log "Found common snapshot in main database"
	fi

	# Get all releases that need to be merged
	# These are releases that workers built in isolated DBs
	local releases=()

	# Discover releases from isolated databases directory
	if [[ -d "$output_folder" ]]; then
		for isolated_dir in "$output_folder"/aptly-isolated-*; do
			if [[ -d "$isolated_dir" ]]; then
				local release=$(basename "$isolated_dir" | sed 's/aptly-isolated-//')
				releases+=("$release")
			fi
		done
	fi

	# Also check if there are any published releases (from old workflow or sequential mode)
	if [[ -d "$output_folder/public/dists" ]]; then
		for release_dir in "$output_folder/public/dists"/*; do
			if [[ -d "$release_dir" ]]; then
				local release=$(basename "$release_dir")
				# Skip common distribution
				[[ "$release" == "common" ]] && continue
				# Add if not already in list
				if [[ ! " ${releases[@]} " =~ " ${release} " ]]; then
					releases+=("$release")
				fi
			fi
		done
	fi

	log "Found ${#releases[@]} release(s) to process: ${releases[*]:-none}"

	# If there are no releases to process, this is a no-op (not an error)
	# This can happen when the repository is empty or workers haven't run yet
	if [[ ${#releases[@]} -eq 0 ]]; then
		log "No releases to merge - nothing to do"
		rm -f "$main_db_config"
		return 0
	fi

	# If we have releases but no common snapshot, that's an error (incomplete workflow)
	if [[ "$common_exists" == false ]]; then
		log "ERROR: Common snapshot not found in main database"
		log "Found ${#releases[@]} release(s) to merge but no common snapshot"
		log "Run 'update-main' command first!"
		rm -f "$main_db_config"
		return 1
	fi

	# Import snapshots from isolated databases into main database
	# This allows us to re-publish with common component included
	for release in "${releases[@]}"; do
		local isolated_db="${output_folder}/aptly-isolated-${release}"

		if [[ -d "$isolated_db" ]]; then
			log "Importing from isolated DB for $release"

			# Create temp config for isolated DB
			local isolated_config
			isolated_config="$(mktemp)"
			sed 's|"rootDir": ".*"|"rootDir": "'$isolated_db'"|g' tools/repository/aptly.conf > "$isolated_config"

			# Import release-specific snapshots from isolated DB to main DB
			# First, we need to import the repos, then create snapshots

			# Check if utils repo exists in isolated DB
			if aptly -config="$isolated_config" repo show "${release}-utils" &>/dev/null; then
				log "Importing ${release}-utils from isolated DB"

				# Create repo in main DB if it doesn't exist
				if ! aptly -config="$main_db_config" repo show "${release}-utils" &>/dev/null; then
					run_aptly -config="$main_db_config" repo create -component="${release}-utils" -distribution="${release}" -comment="Armbian ${release}-utils repository" "${release}-utils"
				fi

				# Export packages from isolated repo and import to main repo
				# Get list of packages in isolated repo
				local packages
				packages=$(aptly -config="$isolated_config" repo show -with-packages "${release}-utils" 2>/dev/null | tail -n +7)

				if [[ -n "$packages" ]]; then
					log "Adding ${release}-utils packages to main database"

					# Get list of packages already in main DB to avoid re-adding them
					local main_db_packages
					main_db_packages=$(aptly -config="$main_db_config" repo show -with-packages "${release}-utils" 2>/dev/null | tail -n +7 || echo "")

					# Add packages from isolated DB's pool to main repo
					# We need to find the .deb files in the isolated pool and add them
					local isolated_pool="${isolated_db}/pool"
					if [[ -d "$isolated_pool" ]]; then
						# Find all .deb files for this release in the isolated pool
						# IMPORTANT: Only add packages that are actually in this repo, not all packages in pool!
						find "$isolated_pool" -name "*.deb" -type f | while read -r deb_file; do
							# Get package info to check if it belongs to this repo
							local deb_name deb_version deb_arch
							deb_info=$(dpkg-deb -f "$deb_file" Package Version Architecture 2>/dev/null)
							deb_name=$(echo "$deb_info" | sed -n '1s/Package: //p')
							deb_version=$(echo "$deb_info" | sed -n '2s/Version: //p')
							deb_arch=$(echo "$deb_info" | sed -n '3s/Architecture: //p')
							local deb_key="${deb_name}_${deb_version}_${deb_arch}"

							# Check if this package is in the utils repo (isolated)
							# aptly output has leading spaces, so grep without anchors
							if echo "$packages" | grep -qw "${deb_key}"; then
								# Check if package already exists in main DB repo to avoid conflicts
								if echo "$main_db_packages" | grep -qw "${deb_key}"; then
									# Package already in main DB, skip it
									continue
								fi
								run_aptly -config="$main_db_config" repo add -force-replace "${release}-utils" "$deb_file"
							fi
						done
					fi
				fi
			fi

			# Same for desktop repo
			if aptly -config="$isolated_config" repo show "${release}-desktop" &>/dev/null; then
				log "Importing ${release}-desktop from isolated DB"

				# Create repo in main DB if it doesn't exist
				if ! aptly -config="$main_db_config" repo show "${release}-desktop" &>/dev/null; then
					run_aptly -config="$main_db_config" repo create -component="${release}-desktop" -distribution="${release}" -comment="Armbian ${release}-desktop repository" "${release}-desktop"
				fi

				# Export packages from isolated repo and import to main repo
				local packages
				packages=$(aptly -config="$isolated_config" repo show -with-packages "${release}-desktop" 2>/dev/null | tail -n +7)

				if [[ -n "$packages" ]]; then
					log "Adding ${release}-desktop packages to main database"

					# Get list of packages already in main DB to avoid re-adding them
					local main_db_packages
					main_db_packages=$(aptly -config="$main_db_config" repo show -with-packages "${release}-desktop" 2>/dev/null | tail -n +7 || echo "")

					local isolated_pool="${isolated_db}/pool"
					if [[ -d "$isolated_pool" ]]; then
						find "$isolated_pool" -name "*.deb" -type f | while read -r deb_file; do
							# Get package info to check if it belongs to this repo
							local deb_name deb_version deb_arch
							deb_info=$(dpkg-deb -f "$deb_file" Package Version Architecture 2>/dev/null)
							deb_name=$(echo "$deb_info" | sed -n '1s/Package: //p')
							deb_version=$(echo "$deb_info" | sed -n '2s/Version: //p')
							deb_arch=$(echo "$deb_info" | sed -n '3s/Architecture: //p')
							local deb_key="${deb_name}_${deb_version}_${deb_arch}"

							# Check if this package is in the desktop repo (isolated)
							# aptly output has leading spaces, so grep without anchors
							if echo "$packages" | grep -qw "${deb_key}"; then
								# Check if package already exists in main DB repo to avoid conflicts
								if echo "$main_db_packages" | grep -qw "${deb_key}"; then
									# Package already in main DB, skip it
									continue
								fi
								run_aptly -config="$main_db_config" repo add -force-replace "${release}-desktop" "$deb_file"
							fi
						done
					fi
				fi
			fi

			rm -f "$isolated_config"
		else
			log "No isolated DB found for $release (repos may already be in main DB)"
			# Repos may already exist in main DB from sequential mode
		fi
	done

	# Now re-publish all releases with common component included
	log "Re-publishing releases with common component..."

	# First, drop ALL existing publishes for the releases we're about to publish
	# This prevents "prefix/distribution already used" errors
	log "Current publish list:"
	aptly -config="$main_db_config" publish list 2>&1 | logger -t repo-management

	for release in "${releases[@]}"; do
		log "Checking for existing publishes for $release"
		# Try to match various formats that aptly might use
		# Formats seen: P.* ./bookworm, [bookworm], etc.
		if aptly -config="$main_db_config" publish list 2>/dev/null | grep -E "(\\[${release}\\]|\\.\\/${release})" >/dev/null; then
			log "Pre-drop: Removing existing publish for $release"
			# Use aptly directly (not run_aptly) to avoid exit on failure
			aptly -config="$main_db_config" publish drop "${release}" 2>/dev/null || true
			# Also try with prefix if the above didn't work
			aptly -config="$main_db_config" publish drop "./${release}" 2>/dev/null || true
		else
			log "No existing publish found for $release"
		fi
	done

	# Clean up published pool once before all publishes to avoid "file already exists and is different" errors
	# This happens when packages are rebuilt with same version but different content
	# IMPORTANT: Do this ONCE before publishing all releases, not per-release
	local published_pool="${output_folder}/public/pool"
	if [[ -d "$published_pool" ]]; then
		log "Removing published pool to avoid conflicts..."
		rm -rf "${published_pool:?}"/*
		log "Pool cleanup complete"
	fi

	for release in "${releases[@]}"; do
		log "Publishing $release with common component..."

		# Determine which components to publish
		local components_to_publish=("main")
		local snapshots_to_publish=("common")

		# Check if utils repo has packages
		local utils_has_packages=false
		if aptly -config="$main_db_config" repo show "${release}-utils" &>/dev/null; then
			local utils_count=$(aptly -config="$main_db_config" repo show "${release}-utils" 2>/dev/null | grep "Number of packages" | awk '{print $4}' || echo "0")
			log "Utils repo has $utils_count packages"
			if [[ "$utils_count" -gt 0 ]]; then
				utils_has_packages=true
				# Drop old snapshot if exists
				if [[ -n $(aptly -config="$main_db_config" snapshot list -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
					run_aptly -config="$main_db_config" snapshot drop "${release}-utils"
				fi
				# Create new snapshot
				run_aptly -config="$main_db_config" snapshot create "${release}-utils" from repo "${release}-utils"
				components_to_publish+=("${release}-utils")
				snapshots_to_publish+=("${release}-utils")
			fi
		else
			log "Utils repo does not exist in main DB"
		fi

		# Check if desktop repo has packages
		local desktop_has_packages=false
		if aptly -config="$main_db_config" repo show "${release}-desktop" &>/dev/null; then
			local desktop_count=$(aptly -config="$main_db_config" repo show "${release}-desktop" 2>/dev/null | grep "Number of packages" | awk '{print $4}' || echo "0")
			log "Desktop repo has $desktop_count packages"
			if [[ "$desktop_count" -gt 0 ]]; then
				desktop_has_packages=true
				# Drop old snapshot if exists
				if [[ -n $(aptly -config="$main_db_config" snapshot list -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
					run_aptly -config="$main_db_config" snapshot drop "${release}-desktop"
				fi
				# Create new snapshot
				run_aptly -config="$main_db_config" snapshot create "${release}-desktop" from repo "${release}-desktop"
				components_to_publish+=("${release}-desktop")
				snapshots_to_publish+=("${release}-desktop")
			fi
		else
			log "Desktop repo does not exist in main DB"
		fi

		# Skip publishing if neither utils nor desktop has packages
		if [[ "$utils_has_packages" == false && "$desktop_has_packages" == false ]]; then
			log "Skipping $release - no packages in utils or desktop repos"
			continue
		fi

		log "Publishing $release with components: ${components_to_publish[*]}"

		# Build publish command
		local component_list=$(IFS=,; echo "${components_to_publish[*]}")
		local snapshot_list="${snapshots_to_publish[*]}"

		# Publish with common component included
		log "Publishing $release with component list: $component_list"

		if ! run_aptly publish \
			-skip-signing \
			-skip-contents \
			-architectures="armhf,arm64,amd64,riscv64,i386,loong64,all" \
			-passphrase="${password:-}" \
			-origin="Armbian" \
			-label="Armbian" \
			-config="$main_db_config" \
			-component="$component_list" \
			-distribution="${release}" snapshot $snapshot_list; then
			log "ERROR: Failed to publish $release"
			# Try to provide more diagnostic information
			aptly -config="$main_db_config" publish list 2>&1 | logger -t repo-management
			return 1
		fi
		log "Successfully published $release"
	done

	# Cleanup temp config
	rm -f "$main_db_config"

	# Sign all Release files
	log "Signing Release files..."
	signing "$output_folder" "DF00FAF1C577104B50BF1D0093D6889F9F0E78D5" "8CFA83D13EB2181EEF5843E41EB30FAF236099FE"

	# Copy GPG key to repository
	mkdir -p "${output_folder}"/public/
	rm -f "${output_folder}"/public/armbian.key
	cp config/armbian.key "${output_folder}"/public/
	log "Copied GPG key to repository"

	# Write repository sync control file
	date +%s > ${output_folder}/public/control
	log "Updated repository control file"

	# Display repository contents
	showall

	log "Merge complete - repository is ready"
}


# Main repository manipulation dispatcher
# Routes commands to appropriate repository management functions
# Arguments:
#   $1 - Input folder containing packages
#   $2 - Output folder for published repository
#   $3 - Command to execute (update-main, serve, html, delete, show, unique, update, merge)
#   $4 - GPG password for signing
#   $5 - Comma-separated list of releases (used by some commands)
#   $6 - List of packages to delete (used by delete command)
repo-manipulate() {
	# Read comma-delimited distros into array
	IFS=', ' read -r -a DISTROS <<< "$5"

	case "$3" in

		update-main)
			# Build common (main) component - runs once before parallel workers
			update_main "$1" "$2" "$4"
			return 0
			;;

		serve)
		# Serve the published repository
		# Since aptly serve requires published repos in its database, and we use
		# direct file publishing, we'll use Python's HTTP server instead
		local serve_ip=$(ip -f inet addr | grep -Po 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1)
		if [[ -z "$serve_ip" ]]; then
			log "WARNING: No external IP found, using 0.0.0.0"
			serve_ip="0.0.0.0"
		fi
		local serve_port="${SERVE_PORT:-8080}"

		if [[ ! -d "$output/public" ]]; then
			log "ERROR: No published repository found at $output/public"
			log "Please run 'update' command first to create the repository"
			return 1
		fi

		log "Starting HTTP server on ${serve_ip}:${serve_port}"
		log "Serving from: $output/public"
		log "Press Ctrl+C to stop"
		log ""
		log "Repository URL: http://${serve_ip}:${serve_port}"
		log ""

		# Change to public directory and start HTTP server
		cd "$output/public" || return 1
		if ! command -v python3 &> /dev/null; then
			log "ERROR: python3 not found. Install python3 to use serve command."
			return 1
		fi
		python3 -m http.server "${serve_port}" --bind "${serve_ip}"
		return 0
	;;

	html)
		cat tools/repository/header.html
		for release in "${DISTROS[@]}"; do
		echo "<thead><tr><td colspan=3><h2>$release</h2></tr><tr><th>Main</th><th>Utils</th><th>Desktop</th></tr></thead>"
		echo "<tbody><tr><td width=33% valign=top>"
		aptly repo show -with-packages -config="${CONFIG}" "${release}-utils" | tail -n +7 | sed 's/.*/&<br>/'
		echo "</td><td width=33% valign=top>"
		aptly repo show -with-packages -config="${CONFIG}" "${release}-desktop" | tail -n +7 | sed 's/.*/&<br>/'
		echo "</td></tr></tbody>"
		done
		cat tools/repository/footer.html
		return 0
	;;

	delete)
			echo "Deleting $6 from common"
			aptly -config="${CONFIG}" repo remove common "$6"
			for release in "${DISTROS[@]}"; do
				echo "Deleting $6 from $release-utils"
				aptly -config="${CONFIG}" repo remove "${release}-utils" "$6"
				echo "Deleting $6 from $release-desktop"
				aptly -config="${CONFIG}" repo remove "${release}-desktop" "$6"
			done
			return 0
		;;

	show)

		showall
		return 0

	;;

	unique)
		# which package should be removed from all repositories
		IFS=$'\n'
		while true; do
			LIST=()
			LIST+=($(aptly repo show -with-packages -config="${CONFIG}" common | tail -n +7))
			for release in "${DISTROS[@]}"; do
				LIST+=($(aptly repo show -with-packages -config="${CONFIG}" "${release}-utils" | tail -n +7))
				LIST+=($(aptly repo show -with-packages -config="${CONFIG}" "${release}-desktop" | tail -n +7))
			done
			LIST=($(echo "${LIST[@]}" | tr ' ' '\n' | sort -u))
			new_list=()
			# create a human readable menu
			for ((n = 0; n < $((${#LIST[@]})); n++)); do
				new_list+=("${LIST[$n]}")
				new_list+=("")
			done
			LIST=("${new_list[@]}")
			LIST_LENGTH=$((${#LIST[@]} / 2))
			exec 3>&1
			TARGET_VERSION=$(dialog --cancel-label "Cancel" --backtitle "BACKTITLE" --no-collapse --title \
			"Remove packages from repositories" --clear --menu "Delete" $((9 + LIST_LENGTH)) 82 65 "${LIST[@]}" 2>&1 1>&3)
			exitstatus=$?
			exec 3>&-
			if [[ $exitstatus -eq 0 ]]; then
				aptly repo remove -config="${CONFIG}" "common" "$TARGET_VERSION"
				for release in "${DISTROS[@]}"; do
					aptly repo remove -config="${CONFIG}" "${release}-utils" "$TARGET_VERSION"
					aptly repo remove -config="${CONFIG}" "${release}-desktop" "$TARGET_VERSION"
				done
			else
				return 1
			fi
			aptly db cleanup -config="${CONFIG}" > /dev/null 2>&1
			# remove empty folders
			find "$2/public" -type d -empty -delete
		done
		;;

	update)
		# remove old releases from publishing (only drops unsupported releases, not all)
		drop_unsupported_releases ""
		publishing "$1" "$2" "$3" "$4" "$5"
		# Only use signing function for non-single-release mode
		# In single-release mode, workers already signed their components
		if [[ -z "$SINGLE_RELEASE" ]]; then
			signing "$2" "DF00FAF1C577104B50BF1D0093D6889F9F0E78D5" "8CFA83D13EB2181EEF5843E41EB30FAF236099FE"
		fi
		;;

	merge)
		# Merge repositories from parallel per-release runs
		# Workers have already signed their releases, just finalize
		merge_repos "$1" "$2"
		;;

	*)
		echo -e "Unknown command"
		return 1
		;;
esac
}


# defaults
input="output/debs-beta"
output="output/repository"
command="show"
if [[ -d "config/distributions" ]]; then
	releases=$(grep -rw config/distributions/*/support 2>/dev/null | cut -d"/" -f3 | xargs | sed -e 's/ /,/g')
	if [[ -z "$releases" ]]; then
		log "WARNING: No releases found in config/distributions"
	fi
else
	log "WARNING: config/distributions directory not found"
	releases=""
fi

help()
{
echo "Armbian wrapper for Aptly v1.0

(c) Igor Pecovnik, igor@armbian.com

License: (MIT) <https://mit-license.org/>

Usage: $0 [ -short | --long ]

-h --help                    displays this help
-i --input [input folder]     input folder with packages
-o --output [output folder]   output folder for repository
-p --password [GPG password]  GPG password for signing
-r --repository [jammy,sid,bullseye,...]  comma-separated list of releases
-l --list [\"Name (% linux*)|armbian-config\"]  list of packages
-c --command                  command to execute
-R --single-release [name]    process only a single release (for parallel GitHub Actions)
                             example: -R jammy or -R noble

          [show] displays packages in each repository
          [sign] sign repository
          [html] displays packages in each repository in html form
          [serve] serve repository - useful for local diagnostics
          [unique] manually select which package should be removed from all repositories
          [update] search for packages in input folder and create/update repository
          [update-main] build common (main) component - run once before parallel workers
          [merge] merge repositories from parallel per-release runs into final repo
          [delete] delete package from -l LIST of packages

-d --dry-run                 perform a full trial run without making any repository changes
                             (implies --keep-sources, shows what would be done)
-k --keep-sources            keep source packages when adding to repository
                             (generates real repo but doesn't delete input packages)
-F --force-add               force re-adding all packages even if they already exist
                             (by default, skips packages that are already in the repo)
-P --force-publish           force publishing even when there are no packages to add
                             (by default, skips publishing empty releases)

GitHub Actions parallel workflow example:
  # Step 1: Build common (main) component once
  ./repo.sh -c update-main -i /shared/packages -o /shared/output

  # Step 2: Workers build release-specific components in parallel (isolated DBs)
  # Workers do NOT build common component - it's merged later
  # Worker 1:  ./repo.sh -c update -R jammy -k -i /shared/packages -o /shared/output
  # Worker 2:  ./repo.sh -c update -R noble -k -i /shared/packages -o /shared/output
  # Worker 3:  ./repo.sh -c update -R bookworm -k -i /shared/packages -o /shared/output

  # Step 3: Final merge to combine common component with release-specific components
  ./repo.sh -c merge -i /shared/packages -o /shared/output

Note: Each worker uses isolated DB (aptly-isolated-<release>) to avoid locking.
Workers build ONLY release-specific components; common component is merged by 'merge' command.
This avoids duplicate work - common packages are added once, not by every worker.
	"
    exit 2
}

SHORT=i:,l:,o:,c:,p:,r:,h,d,k,R:,F:,P:
LONG=input:,list:,output:,command:,password:,releases:,help,dry-run,keep-sources,single-release:,force-add:,force-publish:
if ! OPTS=$(getopt -a -n repo --options $SHORT --longoptions $LONG -- "$@"); then
	help
	exit 1
fi

# Note: Logging now uses syslog/journalctl - view with: journalctl -t repo-management -f

VALID_ARGUMENTS=$# # Returns the count of arguments that are in short or long options

eval set -- "$OPTS"

while :
do
  case "$1" in
    -i | --input )
      input="$2"
      shift 2
      ;;
    -o | --output )
      output="$2"
      shift 2
      ;;
    -c | --command )
      command="$2"
      shift 2
      ;;
    -p | --password )
      password="$2"
      shift 2
      ;;
    -r | --releases )
      releases="$2"
      shift 2
      ;;
    -l | --list )
      list="$2"
      shift 2
      ;;
    -k | --keep-sources )
      KEEP_SOURCES=true
      shift
      ;;
    -R | --single-release )
      SINGLE_RELEASE="$2"
      shift 2
      ;;
    -F | --force-add )
      FORCE_ADD=true
      shift
      ;;
    -P | --force-publish )
      FORCE_PUBLISH=true
      shift
      ;;
    -d | --dry-run )
      DRY_RUN=true
      # Dry-run implies keep-sources
      KEEP_SOURCES=true
      shift
      ;;
    -h | --help)
      help
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      help
      ;;
  esac
done

# redefine output folder in Aptly
# Use isolated database for single-release mode to avoid DB locking during parallel execution
# Use shared database for regular (non-parallel) mode
if [[ -n "$SINGLE_RELEASE" ]]; then
	# Create isolated aptly directory for this release
	IsolatedRootDir="${output}/aptly-isolated-${SINGLE_RELEASE}"

	# Create the isolated directory if it doesn't exist
	if ! mkdir -p "$IsolatedRootDir"; then
		log "ERROR: mkdir $IsolatedRootDir: permission denied"
		exit 1
	fi

	# Do NOT copy the shared database to isolated DB
	# This prevents "key not found" errors when the copied DB references packages
	# that don't exist in the isolated pool. Instead, each worker creates a fresh DB
	# and builds the common component from packages in the shared input folder.

	# Do NOT link the shared pool either - each isolated DB should have its own pool
	# Packages will be copied to the isolated pool when they're added via 'aptly repo add'
	# This prevents hard link issues and "no such file or directory" errors during publish

	# Create temp config file
	TempDir="$(mktemp -d || exit 1)"

	# Create config with isolated rootDir
	cat tools/repository/aptly.conf | \
	sed 's|"rootDir": ".*"|"rootDir": "'$IsolatedRootDir'"|g' > "${TempDir}"/aptly.conf

	CONFIG="${TempDir}/aptly.conf"
	log "Using isolated aptly root for $SINGLE_RELEASE at: $IsolatedRootDir"
else
	TempDir="$(mktemp -d || exit 1)"
	sed 's|"rootDir": ".*"|"rootDir": "'$output'"|g' tools/repository/aptly.conf > "${TempDir}"/aptly.conf
	CONFIG="${TempDir}/aptly.conf"
fi

# Display configuration status
echo "=========================================="
echo "Configuration Status:"
echo "  DRY-RUN:       $([ "$DRY_RUN" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  KEEP-SOURCES:  $([ "$KEEP_SOURCES" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  FORCE-ADD:     $([ "$FORCE_ADD" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  FORCE-PUBLISH: $([ "$FORCE_PUBLISH" == true ] && echo 'ENABLED' || echo 'disabled')"
if [[ -n "$SINGLE_RELEASE" ]]; then
    echo "  SINGLE-RELEASE: ENABLED ($SINGLE_RELEASE)"
else
    echo "  SINGLE-RELEASE: disabled"
fi
echo "=========================================="

log "Configuration: DRY_RUN=$DRY_RUN, KEEP_SOURCES=$KEEP_SOURCES, FORCE_ADD=$FORCE_ADD, FORCE_PUBLISH=$FORCE_PUBLISH, SINGLE_RELEASE=$SINGLE_RELEASE"

if [[ "$DRY_RUN" == true ]]; then
    echo "=========================================="
    echo "DRY-RUN MODE ENABLED"
    echo "No changes will be made to repository"
    echo "Packages will NOT be deleted on add"
    echo "=========================================="
elif [[ "$KEEP_SOURCES" == true ]]; then
    echo "=========================================="
    echo "KEEP-SOURCES MODE ENABLED"
    echo "Repository will be generated normally"
    echo "Source packages will NOT be deleted"
    echo "=========================================="
fi

if [[ "$FORCE_ADD" == true ]]; then
    echo "=========================================="
    echo "FORCE-ADD MODE ENABLED"
    echo "All packages will be re-added even if already in repo"
    echo "=========================================="
fi

if [[ -n "$SINGLE_RELEASE" ]]; then
    echo "=========================================="
    echo "SINGLE RELEASE MODE"
    echo "Processing only: $SINGLE_RELEASE"
    echo "=========================================="
fi


# main
repo-manipulate "$input" "$output" "$command" "$password" "$releases" "$list"
RETURN=$?
exit $RETURN
