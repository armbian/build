#!/usr/bin/env bash

# Global variables for parallel execution and dry-run modes
DRY_RUN=false              # Full dry-run: don't make any repository changes
KEEP_SOURCES=false         # Keep source packages when adding to repo (don't delete)
PARALLEL_JOBS=0
PARALLEL_MODE=false
SINGLE_RELEASE=""          # Process only a single release (for parallel GitHub Actions)

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a "${DEBUGFILE}"
}

# Dry-run aware command execution
run_cmd() {
    local cmd="$*"
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "Executing: $cmd"
        eval "$cmd"
        return $?
    fi
}

# Drop unsupported releases
drop_unsupported_releases() {

	if [[ "$1" == "all" ]]; then
		log "Cleanup: dropping published repositories"
		BUILD_FW=()
	else
		log "Cleanup: dropping unsupported"
		BUILD_FW=($(grep -rw config/distributions/*/support -ve 'eos' | cut -d"/" -f3))
	fi

	REPO=($(aptly publish list -config="${CONFIG}" --raw | sed "s/. //g"))
	DROP=()
	for i in "${REPO[@]}"; do
	skip=
		for j in "${BUILD_FW[@]}"; do
		[[ $i == $j ]] && { skip=1; break ; }
		done
		[[ -n $skip ]] || DROP+=("$i")
	done

	# drop
	for i in "${DROP[@]}"; do
		run_cmd aptly publish drop -config="${CONFIG}" "${i}"
	done
}


# Display repository content
#
showall(){
		echo "Displaying common repository contents"
		aptly repo show -with-packages -config="${CONFIG}" common 2>/dev/null | tail -n +7
		for release in "${DISTROS[@]}"; do
			# Only show if the repo exists
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


# Adding package
#
# @arg $1 string component
# @arg $2 string incoming folder
# @arg $3 string description
# @arg $4 input folder
#
adding_packages() {
# add deb files to repository if they are not already there
	if ! find "${4}${2}" -maxdepth 1 -type f -name "*.deb" 2> /dev/null | grep -q .; then
	return 0
	fi
	for f in "${4}${2}"/*.deb; do
			# If we have a list of last known working kernels, repack BSP files to prevent upgrade to kernel that breaks
			if [[ -f userpatches/last-known-good.map ]]; then
				PACKAGE_NAME=$(dpkg-deb -W $f | awk '{ print $1 }')
				for g in $(cat userpatches/last-known-good-kernel-pkg.map); do
					# Read values from file
					BOARD=$(echo $g | cut -d"|" -f1);
					BRANCH=$(echo $g | cut -d"|" -f2);
					LINUXFAMILY=$(echo $g | cut -d"|" -f3)
					LASTKERNEL=$(echo $g | cut -d"|" -f4);
					if [[ ${PACKAGE_NAME} == "armbian-bsp-cli-${BOARD}-${BRANCH}" ]]; then
					echo "Setting last kernel upgrade for $BOARD to linux-image-$BRANCH-$BOARD=${LASTKERNEL}"
					tempdir=$(mktemp -d)
					dpkg-deb -R $f $tempdir
					sed -i '/^Replaces:/ s/$/, linux-image-'$BRANCH'-'$LINUXFAMILY' (>> '$LASTKERNEL'), linux-dtb-'$BRANCH'-'$LINUXFAMILY' (>> '$LASTKERNEL')/' $tempdir/DEBIAN/control
					dpkg-deb -b $tempdir ${f} >/dev/null
					fi
				done
			fi
			# Determine whether to remove source files after adding to repo
			# KEEP_SOURCES mode preserves source packages
			# DRY_RUN mode also preserves sources (and skips all repo modifications)
			local remove_flag="-remove-files"
			if [[ "$KEEP_SOURCES" == true ]] || [[ "$DRY_RUN" == true ]]; then
				remove_flag=""
			fi
			aptly repo add $remove_flag -force-replace -config="${CONFIG}" "${1}" "${f}"
	done
}


# Build common (main) component - runs once before parallel workers
# $1: input folder
# $2: output folder
# $3: gpg password
update_main() {
	local input_folder="$1"
	local output_folder="$2"
	local gpg_password="$3"

	log "Building common (main) component"

	# Create common repo if it doesn't exist
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
		aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | sudo tee -a "${DEBUGFILE}" >/dev/null
	fi

	# Add packages from main folder
	adding_packages "common" "" "main" "$input_folder"

	# Drop old snapshot
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
		aptly -config="${CONFIG}" snapshot drop common | sudo tee -a "${DEBUGFILE}" >/dev/null
	fi

	# Create snapshot
	aptly -config="${CONFIG}" snapshot create common from repo common | sudo tee -a "${DEBUGFILE}" >/dev/null

	log "Common component built successfully"
}

# Process a single release - can be run in parallel
# $1: release name
# $2: input folder
# $3: output folder
# $4: gpg password
process_release() {
	local release="$1"
	local input_folder="$2"
	local output_folder="$3"
	local gpg_password="$4"

	log "Processing release: $release"

	# In isolated mode, ensure common snapshot exists
	# It should have been created by 'update-main' command, but if not, create empty common
	if [[ -n "$SINGLE_RELEASE" && -z $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
		log "WARNING: Common snapshot not found. Creating empty common snapshot."
		log "Please run 'update-main' command first to populate common packages."

		# Create empty common repo
		if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
			aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | sudo tee -a "${DEBUGFILE}" >/dev/null
		fi

		# Create snapshot (will be empty until update-main is run)
		aptly -config="${CONFIG}" snapshot create common from repo common | sudo tee -a "${DEBUGFILE}" >/dev/null
	fi

	# Create repos if they don't exist
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
		aptly repo create -config="${CONFIG}" -component="${release}-utils" -distribution="${release}" -comment="Armbian ${release}-utils repository" "${release}-utils" | sudo tee -a "${DEBUGFILE}" >/dev/null
	fi
	if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
		aptly repo create -config="${CONFIG}" -component="${release}-desktop" -distribution="${release}" -comment="Armbian ${release}-desktop repository" "${release}-desktop" | sudo tee -a "${DEBUGFILE}" >/dev/null
	fi

	# Add packages ONLY from release-specific extra folders
	adding_packages "${release}-utils" "/extra/${release}-utils" "release utils" "$input_folder"
	adding_packages "${release}-desktop" "/extra/${release}-desktop" "release desktop" "$input_folder"

	# Drop old snapshots
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
		aptly -config="${CONFIG}" snapshot drop ${release}-utils | sudo tee -a "${DEBUGFILE}" 2>/dev/null
	fi
	if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
		aptly -config="${CONFIG}" snapshot drop ${release}-desktop | sudo tee -a "${DEBUGFILE}" 2>/dev/null
	fi

	# Create new snapshots
	aptly -config="${CONFIG}" snapshot create ${release}-utils from repo ${release}-utils | sudo tee -a "${DEBUGFILE}" >/dev/null
	aptly -config="${CONFIG}" snapshot create ${release}-desktop from repo ${release}-desktop | sudo tee -a "${DEBUGFILE}" >/dev/null

	# Determine publish directory based on mode
	local publish_dir="$output_folder"
	if [[ -n "$SINGLE_RELEASE" ]]; then
		publish_dir="$IsolatedRootDir"
	fi

	# Publish - include common snapshot for main component
	log "Publishing $release"
	aptly publish \
		-skip-signing \
		-architectures="armhf,arm64,amd64,riscv64,i386,loong64,all" \
		-passphrase="${gpg_password}" \
		-origin="Armbian" \
		-label="Armbian" \
		-config="${CONFIG}" \
		-component=main,${release}-utils,${release}-desktop \
		-distribution="${release}" snapshot common ${release}-utils ${release}-desktop > /dev/null

	# If using isolated DB, copy published files to shared output location FIRST
	if [[ -n "$SINGLE_RELEASE" && "$publish_dir" != "$output_folder" ]]; then
		log "Copying published files from isolated DB to shared output"
		if [[ -d "${publish_dir}/public" ]]; then
			mkdir -p "${output_folder}/public"
			# Use rsync to copy published repo files to shared location
			# NO --delete flag - we want to preserve other releases' files
			rsync -a "${publish_dir}/public/" "${output_folder}/public/" 2>&1 | sudo tee -a "${DEBUGFILE}"
			log "Copied files for $release to ${output_folder}/public/"
		fi
	fi

	# Sign Release files for this release
	# This includes:
	# 1. Top-level Release file (dists/{release}/Release)
	# 2. Component-level Release files (dists/{release}/{component}/Release)
	# Sign AFTER copying so signed files end up in the shared output location
	log "Starting signing process for $release"
	# Use shared output location for signing, not isolated directory
	local release_pub_dir="${output_folder}/public/dists/${release}"

	# Get GPG keys from environment or use defaults
	local gpg_key="${GPG_KEY:-DF00FAF1C577104B50BF1D0093D6889F9F0E78D5}"
	local gpg_params=("--yes" "--armor" "-u" "$gpg_key")

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
				cp "$source_release" "$target_release" 2>&1 | sudo tee -a "${DEBUGFILE}"
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

		if gpg "${gpg_params[@]}" --clear-sign -o "${sign_dir}/InRelease" "$release_file" 2>&1 | sudo tee -a "${DEBUGFILE}" >/dev/null; then
			gpg "${gpg_params[@]}" --detach-sign -o "${sign_dir}/Release.gpg" "$release_file" 2>&1 | sudo tee -a "${DEBUGFILE}" >/dev/null
			log "Successfully signed: ${release_file}"
		else
			log "ERROR: Failed to sign: ${release_file}"
		fi
	done

	log "Completed processing release: $release"
}

# publishing repository
#
# $1: Input folder
# $2: Output folder
# $3: Command
# $4: GPG password
# $5: jammy,sid

publishing(){

	# Only build common repo if NOT in single-release mode
	# In single-release mode, common should be built separately with 'update-main' command
	if [[ -z "$SINGLE_RELEASE" ]]; then
		# this repository contains packages that are the same in all releases.
		if [[ -z $(aptly repo list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep common) ]]; then
			aptly repo create -config="${CONFIG}" -distribution="common" -component="main" -comment="Armbian common packages" "common" | sudo tee -a "${DEBUGFILE}" >/dev/null
		fi

		# add packages from main folder
		adding_packages "common" "" "main" "$1"

		# create snapshot
		UNIQUE_NAME=$(date +%s)
		if [[ -n $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
		aptly -config="${CONFIG}" snapshot drop common | sudo tee -a "${DEBUGFILE}" >/dev/null
		fi
		aptly -config="${CONFIG}" snapshot create common from repo common | sudo tee -a "${DEBUGFILE}" >/dev/null
	else
		# Single-release mode: ensure common snapshot exists (should be created by update-main)
		if [[ -z $(aptly snapshot list -config="${CONFIG}" -raw | awk '{print $(NF)}' | grep "common") ]]; then
			log "WARNING: Common snapshot not found. Run 'update-main' command first!"
		fi
	fi

	# get all distributions or use single release if specified
	local distributions=()
	if [[ -n "$SINGLE_RELEASE" ]]; then
		distributions=("$SINGLE_RELEASE")
		log "Single release mode: processing only $SINGLE_RELEASE"
	else
		distributions=($(grep -rw config/distributions/*/support -ve '' | cut -d"/" -f3))
	fi

	# Process releases either in parallel or sequentially
	if [[ "$PARALLEL_MODE" == true && "$PARALLEL_JOBS" -gt 1 && -z "$SINGLE_RELEASE" ]]; then
		log "Processing ${#distributions[@]} releases in parallel with $PARALLEL_JOBS jobs"

		# Export functions needed for parallel execution
		export -f adding_packages
		export -f log
		export CONFIG
		export DRY_RUN
		export KEEP_SOURCES
		export DEBUGFILE

		# Use GNU parallel if available, else use xargs
		if command -v parallel &> /dev/null; then
			printf "%s\n" "${distributions[@]}" | parallel -j "$PARALLEL_JOBS" process_release {} "$1" "$2" "$4"
		else
			# Fallback to xargs for parallel execution
			printf "%s\n" "${distributions[@]}" | xargs -P "$PARALLEL_JOBS" -I {} bash -c "process_release '{}' '$1' '$2' '$4'"
		fi
	else
		if [[ -n "$SINGLE_RELEASE" ]]; then
			log "Processing single release: ${distributions[0]}"
		else
			log "Processing ${#distributions[@]} releases sequentially"
		fi
		for release in "${distributions[@]}"; do
			process_release "$release" "$1" "$2" "$4"
		done
	fi

# cleanup
aptly db cleanup -config="${CONFIG}"
# key
mkdir -p "${2}"/public/
cp config/armbian.key "${2}"/public/
# write repo sync control file
sudo date +%s > ${2}/public/control
# display what we have
showall
}


# Sign repository Release files in the given output folder using provided GPG keys
# $1: Output folder path
# $@: GPG key IDs to use for signing
signing() {
    local output_folder="$1"
    shift
    local gpg_keys=("$@")

    if [[ ${#gpg_keys[@]} -eq 0 ]]; then
        echo "No GPG keys provided for signing." >&2
        return 1
    fi

    local gpg_params=("--yes" "--armor")
    for key in "${gpg_keys[@]}"; do
        if ! gpg --list-secret-keys "$key" >/dev/null 2>&1; then
            echo "Warning: GPG key $key not found on this system." >&2
			continue
        fi
        gpg_params+=("-u" "$key")
    done

    # Only sign Release files at component level, NOT binary subdirs
    # Sign: dists/{release}/{component}/Release
    # Skip: dists/{release}/Release (top-level, not needed)
    # Skip: dists/{release}/*/binary-*/Release (subdirs, not needed)
    find "$output_folder/public/dists" -type f -name Release | while read -r release_file; do
        # Skip if file is in a binary-* subdirectory
        if [[ "$release_file" =~ /binary-[^/]+/Release$ ]]; then
            continue
        fi

        # Skip top-level Release files (dists/{release}/Release)
        # Only sign component-level Release files (dists/{release}/{component}/Release)
        local rel_path="${release_file#$output_folder/public/dists/}"
        # Count slashes - should have exactly 2 for component level: {release}/{component}/Release
        local slash_count=$(echo "$rel_path" | tr -cd '/' | wc -c)

        if [[ $slash_count -eq 2 ]]; then
            local distro_path
            distro_path="$(dirname "$release_file")"
            echo "Signing release at: $distro_path" | sudo tee -a "$DEBUGFILE"
            gpg "${gpg_params[@]}" --clear-sign -o "$distro_path/InRelease" "$release_file"
            gpg "${gpg_params[@]}" --detach-sign -o "$distro_path/Release.gpg" "$release_file"
        fi
    done
}


# Merge repositories from multiple parallel runs
# Used when GitHub Actions generate repos for individual releases in parallel
# Since workers have already built and signed repos, this just finalizes the output
# $1: Base input folder (contains package sources)
# $2: Output folder
merge_repos() {
	local input_folder="$1"
	local output_folder="$2"

	log "Merge mode: finalizing combined repository"
	log "Workers have already built and signed individual releases"

	# Repositories are already built and signed by parallel workers
	# Just need to ensure the key and control file are in place

	# key
	mkdir -p "${output_folder}"/public/
	cp config/armbian.key "${output_folder}"/public/
	log "Copied GPG key to repository"

	# write repo sync control file
	sudo date +%s > ${output_folder}/public/control
	log "Updated repository control file"

	# display what we have
	showall

	log "Merge complete - repository is ready"
}


#
# $1: Input folder
# $2: Output folder
# $3: Command
# $4: GPG password
# $5: jammy,sid
# $6: list of packages to delete
repo-manipulate() {

# read comma delimited distros into array
IFS=', ' read -r -a DISTROS <<< "$5"

case $3 in

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
		python3 -m http.server "${serve_port}" --bind "${serve_ip}"
		return 0
	;;

	html)
		cat tools/repository/header.html
		for release in "${DISTROS[@]}"; do
		echo "<thead><tr><td colspan=3><h2>$release</h2></tr><tr><th>Main</th><th>Utils</th><th>Desktop</th></tr></thead>"
		echo "<tbody><tr><td width=33% valing=top>"
		aptly repo show -with-packages -config="${CONFIG}" "${release}-utils" | tail -n +7 | sed 's/.*/&<br>/'
		echo "</td><td width=33% valign=top>" | sudo tee -a ${filename}
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
			find $2/public -type d -empty -print -exec rm -rf {} \;
		done
		;;

	update)
		# remove old releases from publishing
		drop_unsupported_releases "all"
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
releases=$(grep -rw config/distributions/*/support -ve 'eos' | cut -d"/" -f3 | xargs | sed -e 's/ /,/g')

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
-j --parallel-jobs [N]       number of parallel jobs for release processing (default: 0=disabled)
                             requires GNU parallel or will fall back to xargs

GitHub Actions parallel workflow example:
  # Step 1: Build common (main) component once (optional - workers will create it if missing)
  ./repo.sh -c update-main -i /shared/packages -o /shared/output

  # Step 2: Workers build release-specific components in parallel (isolated DBs)
  # Worker 1:  ./repo.sh -c update -R jammy -k -i /shared/packages -o /shared/output
  # Worker 2:  ./repo.sh -c update -R noble -k -i /shared/packages -o /shared/output
  # Worker 3:  ./repo.sh -c update -R bookworm -k -i /shared/packages -o /shared/output

  # Step 3: Final merge to combine all outputs
  ./repo.sh -c merge -i /shared/packages -o /shared/output

Note: Each worker uses isolated DB (aptly-isolated-<release>) to avoid locking.
Common snapshot is created in each worker's isolated DB from root packages.
	"
    exit 2
}

SHORT=i:,l:,o:,c:,p:,r:,h,j:,d,k,R:
LONG=input:,list:,output:,command:,password:,releases:,help,parallel-jobs:,dry-run,keep-sources,single-release:
OPTS=$(getopt -a -n repo --options $SHORT --longoptions $LONG -- "$@")
DEBUGFILE="/var/log/repo-management.log"

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
    -j | --parallel-jobs )
      PARALLEL_JOBS="$2"
      if [[ "$PARALLEL_JOBS" -gt 0 ]]; then
        PARALLEL_MODE=true
      fi
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
	mkdir -p "$IsolatedRootDir"

	# Copy database structure from shared DB if it exists
	if [[ -d "${output}/db" ]]; then
		log "Copying common database to isolated DB..."
		# Copy the entire db directory to inherit common snapshot
		cp -a "${output}/db" "${IsolatedRootDir}/"
	fi

	# Copy pool directory for common packages if it exists
	# This is needed because the common snapshot references packages in the pool
	if [[ -d "${output}/pool" ]]; then
		log "Linking common pool to isolated DB..."
		mkdir -p "${IsolatedRootDir}/pool"
		# Use rsync with hard links to avoid duplicating package files
		# -H, --hard-links: hard link files from source
		# --delete: remove files in target that don't exist in source
		rsync -aH --delete "${output}/pool/" "${IsolatedRootDir}/pool/" 2>&1 | sudo tee -a "${DEBUGFILE}"
	fi

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

if [[ -n "$SINGLE_RELEASE" ]]; then
    echo "=========================================="
    echo "SINGLE RELEASE MODE"
    echo "Processing only: $SINGLE_RELEASE"
    echo "=========================================="
fi

if [[ "$PARALLEL_MODE" == true ]]; then
    echo "=========================================="
    echo "PARALLEL MODE ENABLED"
    echo "Number of parallel jobs: $PARALLEL_JOBS"
    echo "=========================================="
fi

# main
repo-manipulate "$input" "$output" "$command" "$password" "$releases" "$list"
RETURN=$?
exit $RETURN
