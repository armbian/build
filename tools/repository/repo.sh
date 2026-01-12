#!/usr/bin/env bash

# Global variables
DRY_RUN=false              # Full dry-run: don't make any repository changes
KEEP_SOURCES=true          # Keep source packages when adding to repo (don't delete)
FORCE_ADD=false            # Force re-adding packages even if they already exist in repo
FORCE_PUBLISH=true         # Force publishing even when no packages to add
GPG_PARAMS=()              # Global GPG parameters array (set by get_gpg_signing_params)

# Log message to syslog (view with: journalctl -t repo-management -f)
log() {
    logger -t repo-management "$*"
}

# Execute aptly command, exit on failure (unless dry-run)
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

# Drop published repositories for unsupported releases
# Arguments:
#   $1 - "all" to drop all, otherwise only drops unsupported ones
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
showall() {
	echo "Displaying common repository contents"
	aptly repo show -with-packages -config="${CONFIG}" common 2>/dev/null | tail -n +7

	local releases_to_show=("${DISTROS[@]}")
	if [[ ${#DISTROS[@]} -eq 0 ]]; then
		releases_to_show=($(aptly repo list -config="${CONFIG}" -raw 2>/dev/null | awk '{print $NF}' | grep -E '^.+-(utils|desktop)$' | sed 's/-(utils|desktop)$//' | sort -u))
	fi

	for release in "${releases_to_show[@]}"; do
		if aptly repo show -config="${CONFIG}" "${release}-utils" &>/dev/null; then
			echo "Displaying repository contents for $release-utils"
			aptly repo show -with-packages -config="${CONFIG}" "${release}-utils" | tail -n +7
		fi

		if aptly repo show -config="${CONFIG}" "${release}-desktop" &>/dev/null; then
			echo "Displaying repository contents for $release-desktop"
			aptly repo show -with-packages -config="${CONFIG}" "${release}-desktop" | tail -n +7
		fi
	done
}


# Add .deb packages to repository component
# Arguments:
#   $1 - Component name (e.g., "common", "jammy-utils")
#   $2 - Subdirectory path (e.g., "", "/extra/jammy-utils")
#   $3 - Description (unused)
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

		# If package with same name+arch but different version exists in repo, remove it first
		# This prevents "file already exists and is different" errors during publish
		if [[ "$FORCE_ADD" != true ]]; then
			for existing_key in "${!repo_packages_map[@]}"; do
				# existing_key format: name|version|arch
				local existing_name existing_version existing_arch
				IFS='|' read -r existing_name existing_version existing_arch <<< "$existing_key"
				# Check if same name and arch but different version
				if [[ "$existing_name" == "$deb_name" && "$existing_arch" == "$deb_arch" && "$existing_version" != "$deb_version" ]]; then
					log "Removing old version ${existing_name}_${existing_version}_${existing_arch} before adding new version"
					run_aptly repo remove -config="${CONFIG}" "${component}" "${existing_name}_${existing_version}_${existing_arch}"
					# Remove from map so we don't try to remove it again
					unset "repo_packages_map[$existing_key]"
				fi
			done
		fi

		# Skip if exact package (name+version+arch) already exists in repo (unless FORCE_ADD is true)
		if [[ "$FORCE_ADD" != true && -n "${repo_packages_map[$deb_key]}" ]]; then
			echo "[-] SKIP: $deb_display"
			log "SKIP: $deb_display already in $component"
			continue
		fi

		# Repack BSP packages if last-known-good kernel map exists
		# This prevents upgrading to kernels that may break the board
		if [[ -f userpatches/last-known-good-kernel-pkg.map ]]; then
			# Read kernel pinning mappings from file
			while IFS='|' read -r board branch linux_family last_kernel; do
				if [[ "${deb_name}" == "armbian-bsp-cli-${board}-${branch}" ]]; then
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
		local remove_flag="-remove-files"
		if [[ "$KEEP_SOURCES" == true ]] || [[ "$DRY_RUN" == true ]]; then
			remove_flag=""
		fi

		# Add package to repository
		log "Adding $deb_name to $component"
		run_aptly repo add $remove_flag -force-replace -config="${CONFIG}" "${component}" "${deb_file}"
	done
}


# Process a single release: create repos, publish, and sign
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

	# Create release-specific repositories if they don't exist
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
		run_aptly repo create -config="${CONFIG}" -component="${release}-utils" -distribution="${release}" -comment="Armbian ${release}-utils repository" "${release}-utils" | logger -t repo-management >/dev/null
	fi
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
		run_aptly repo create -config="${CONFIG}" -component="${release}-desktop" -distribution="${release}" -comment="Armbian ${release}-desktop repository" "${release}-desktop" | logger -t repo-management >/dev/null
	fi

	# Run db cleanup before adding packages to avoid "file already exists and is different" errors
	# This removes unreferenced packages from previous runs that may have the same filename
	log "Running database cleanup before adding release packages"
	run_aptly db cleanup -config="${CONFIG}"

	# Add packages ONLY from release-specific extra folders
	adding_packages "${release}-utils" "/extra/${release}-utils" "release utils" "$input_folder"
	adding_packages "${release}-desktop" "/extra/${release}-desktop" "release desktop" "$input_folder"

	# Run db cleanup again after adding packages to remove any old package files
	# This is critical after removing old versions of packages to prevent
	# "file already exists and is different" errors during publish
	log "Running database cleanup after adding packages"
	run_aptly db cleanup -config="${CONFIG}"

	# Check if we have any packages to publish
	# Get package counts in each repo
	local utils_count desktop_count
	utils_count=$(aptly repo show -config="${CONFIG}" "${release}-utils" 2>/dev/null | grep "Number of packages" | awk '{print $4}') || utils_count="0"
	desktop_count=$(aptly repo show -config="${CONFIG}" "${release}-desktop" 2>/dev/null | grep "Number of packages" | awk '{print $4}') || desktop_count="0"

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

	# Always drop and recreate snapshots for fresh publish
	# This ensures that even empty repos are properly published
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
		log "Dropping existing ${release}-utils snapshot"
		run_aptly -config="${CONFIG}" snapshot drop ${release}-utils | logger -t repo-management 2>/dev/null
	fi
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
		log "Dropping existing ${release}-desktop snapshot"
		run_aptly -config="${CONFIG}" snapshot drop ${release}-desktop | logger -t repo-management 2>/dev/null
	fi

	# Create snapshots for all repos (even empty ones) to ensure they're included in publish
	local components_to_publish=()
	local snapshots_to_publish=()

	# Add common/main component
	components_to_publish=("main")
	snapshots_to_publish=("common")

	# Always create utils snapshot and include in publish (even if empty)
	log "Creating ${release}-utils snapshot (packages: $utils_count)"
	run_aptly -config="${CONFIG}" snapshot create ${release}-utils from repo ${release}-utils | logger -t repo-management >/dev/null
	components_to_publish+=("${release}-utils")
	snapshots_to_publish+=("${release}-utils")

	# Always create desktop snapshot and include in publish (even if empty)
	log "Creating ${release}-desktop snapshot (packages: $desktop_count)"
	run_aptly -config="${CONFIG}" snapshot create ${release}-desktop from repo ${release}-desktop | logger -t repo-management >/dev/null
	components_to_publish+=("${release}-desktop")
	snapshots_to_publish+=("${release}-desktop")

	log "Publishing $release with components: ${components_to_publish[*]}"

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
	log "Starting signing process for $release"
	local release_pub_dir="${output_folder}/public/dists/${release}"

	if ! get_gpg_signing_params "$gpg_password"; then
		return 1
	fi

	# First, create component-level Release files by copying from binary-amd64 Release
	# This is needed because aptly only creates Release files in binary-* subdirs
	for component in main ${release}-utils ${release}-desktop; do
		local component_dir="${release_pub_dir}/${component}"
		if [[ -d "$component_dir" ]]; then
			local source_release="${component_dir}/binary-amd64/Release"
			local target_release="${component_dir}/Release"

			if [[ -f "$source_release" && ! -f "$target_release" ]]; then
				log "Creating component Release file: ${target_release}"
				cp "$source_release" "$target_release"
			fi
		fi
	done

	# Sign all Release files (both top-level and component-level)
	# Skip binary-* subdirectories
	find "${release_pub_dir}" -type f -name "Release" | while read -r release_file; do
		if [[ "$release_file" =~ /binary-[^/]+/Release$ ]]; then
			continue
		fi

		log "Signing: ${release_file}"
		local sign_dir="$(dirname "$release_file")"

		# Sign with InRelease (clear-sign) - capture output for logging
		if gpg "${GPG_PARAMS[@]}" --clear-sign -o "${sign_dir}/InRelease" "$release_file" 2>&1; then
			log "Created InRelease for: ${release_file}"
			# Sign with Release.gpg (detach-sign)
			if gpg "${GPG_PARAMS[@]}" --detach-sign -o "${sign_dir}/Release.gpg" "$release_file" 2>&1; then
				log "Successfully signed: ${release_file}"
			else
				log "ERROR: Failed to create Release.gpg for: ${release_file}"
			fi
		else
			log "ERROR: Failed to create InRelease for: ${release_file}"
		fi
	done

	log "Completed processing release: $release"
}

# Build common component, process all releases, and finalize repository
# Arguments:
#   $1 - Input folder containing packages
#   $2 - Output folder for published repository
#   $3 - Command name (unused)
#   $4 - GPG password for signing
#   $5 - Comma-separated list of releases (unused, determined from config)
publishing() {
	# Build common repo - this repository contains packages that are the same in all releases
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
		run_aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | logger -t repo-management >/dev/null
	fi

	# Run db cleanup before adding packages to avoid "file already exists and is different" errors
	# This removes unreferenced packages from previous runs that may have the same filename
	log "Running database cleanup before adding common packages"
	run_aptly db cleanup -config="${CONFIG}"

	# Add packages from main folder
	adding_packages "common" "" "main" "$1"

	# Run db cleanup after adding packages to remove any old package files
	# This is critical after removing old versions of packages to prevent
	# "file already exists and is different" errors during publish
	log "Running database cleanup after adding common packages"
	run_aptly db cleanup -config="${CONFIG}"

	# Create or update the common snapshot
	# Drop existing snapshot if it exists
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "^common$") ]]; then
		log "Dropping existing common snapshot"
		run_aptly -config="${CONFIG}" snapshot drop common | logger -t repo-management 2>/dev/null
	fi

	log "Creating common snapshot"
	run_aptly -config="${CONFIG}" snapshot create common from repo common | logger -t repo-management >/dev/null

	# Get all distributions
	local distributions=($(grep -rw config/distributions/*/support -ve '' | cut -d"/" -f3))

	# Process releases sequentially
	log "Processing ${#distributions[@]} releases sequentially"
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


# Resolve GPG keys and build signing parameters
# Sets global GPG_PARAMS array
# Arguments:
#   $1 - GPG password (optional, currently unused)
# Returns:
#   0 on success, 1 if no keys found
get_gpg_signing_params() {
	local gpg_password="${1:-}"
	local gpg_keys=()

	# Get GPG keys from environment or use defaults
	if [[ -n "$GPG_KEY" ]]; then
		gpg_keys=("$GPG_KEY")
	else
		gpg_keys=("DF00FAF1C577104B50BF1D0093D6889F9F0E78D5" "8CFA83D13EB2181EEF5843E41EB30FAF236099FE")
	fi

	GPG_PARAMS=("--yes" "--armor")
	local keys_found=0

	# Add all available keys to GPG parameters
	for gpg_key in "${gpg_keys[@]}"; do
		local actual_key=""
		if gpg --list-secret-keys "$gpg_key" >/dev/null 2>&1; then
			actual_key="$gpg_key"
		else
			# Try to find by email or partial match
			actual_key=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -B1 "$gpg_key" | grep "sec" | awk '{print $2}' | cut -d'/' -f2 || echo "")
		fi

		if [[ -n "$actual_key" ]]; then
			GPG_PARAMS+=("-u" "$actual_key")
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
	return 0
}

# Sign Release files with GPG (creates InRelease and Release.gpg)
# Arguments:
#   $1 - Output folder path containing published repository
signing() {
	local output_folder="$1"

	if ! get_gpg_signing_params; then
		return 1
	fi

	# Sign top-level Release files for each distribution
	find "$output_folder/public/dists" -maxdepth 2 -type f -name Release | while read -r release_file; do
		local rel_path="${release_file#$output_folder/public/dists/}"
		local slash_count=$(echo "$rel_path" | tr -cd '/' | wc -c)

		if [[ $slash_count -eq 1 ]]; then
			local distro_path
			distro_path="$(dirname "$release_file")"
			log "Signing release at: $distro_path"
			gpg "${GPG_PARAMS[@]}" --clear-sign -o "$distro_path/InRelease" "$release_file"
			gpg "${GPG_PARAMS[@]}" --detach-sign -o "$distro_path/Release.gpg" "$release_file"
		fi
	done
}


# Main command dispatcher
# Arguments:
#   $1 - Input folder containing packages
#   $2 - Output folder for published repository
#   $3 - Command to execute (serve, html, delete, show, unique, update)
#   $4 - GPG password for signing
#   $5 - Comma-separated list of releases
#   $6 - List of packages to delete (used by delete command)
repo-manipulate() {
	# Read comma-delimited distros into array
	IFS=', ' read -r -a DISTROS <<< "$5"

	case "$3" in

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

          [show] displays packages in each repository
          [html] displays packages in each repository in html form
          [serve] serve repository - useful for local diagnostics
          [unique] manually select which package should be removed from all repositories
          [update] search for packages in input folder and create/update repository
          [delete] delete package from -l LIST of packages

-d --dry-run                 perform a full trial run without making any repository changes
                             (implies --keep-sources, shows what would be done)
-k --keep-sources            keep source packages when adding to repository
                             (generates real repo but doesn't delete input packages)
-F --force-add               force re-adding all packages even if they already exist
                             (by default, skips packages that are already in the repo)
-P --force-publish           force publishing even when there are no packages to add
                             (by default, skips publishing empty releases)
	"
    exit 2
}

SHORT=i:,l:,o:,c:,p:,r:,h,d,k,F:,P:
LONG=input:,list:,output:,command:,password:,releases:,help,dry-run,keep-sources,force-add:,force-publish:
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
TempDir="$(mktemp -d || exit 1)"
sed 's|"rootDir": ".*"|"rootDir": "'$output'"|g' tools/repository/aptly.conf > "${TempDir}"/aptly.conf
CONFIG="${TempDir}/aptly.conf"

# Display configuration status
echo "=========================================="
echo "Configuration Status:"
echo "  DRY-RUN:       $([ "$DRY_RUN" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  KEEP-SOURCES:  $([ "$KEEP_SOURCES" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  FORCE-ADD:     $([ "$FORCE_ADD" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "  FORCE-PUBLISH: $([ "$FORCE_PUBLISH" == true ] && echo 'ENABLED' || echo 'disabled')"
echo "=========================================="

log "Configuration: DRY_RUN=$DRY_RUN, KEEP_SOURCES=$KEEP_SOURCES, FORCE_ADD=$FORCE_ADD, FORCE_PUBLISH=$FORCE_PUBLISH"

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


# main
repo-manipulate "$input" "$output" "$command" "$password" "$releases" "$list"
RETURN=$?
exit $RETURN
