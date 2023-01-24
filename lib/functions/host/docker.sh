#############################################################################################################
# @TODO: called by no-one, yet.
function check_and_install_docker_daemon() {
	# @TODO: sincerely, not worth keeping this. Send user to Docker install docs. `adduser $USER docker` is important on Linux.
	# Install Docker if not there but wanted. We cover only Debian based distro install. On other distros, manual Docker install is needed
	if [[ "${1}" == docker && -f /etc/debian_version && -z "$(command -v docker)" ]]; then
		DOCKER_BINARY="docker-ce"

		# add exception for Ubuntu Focal until Docker provides dedicated binary
		codename=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)
		codeid=$(cat /etc/os-release | grep ^NAME | cut -d"=" -f2 | awk '{print tolower($0)}' | tr -d '"' | awk '{print $1}')
		[[ "${codename}" == "debbie" ]] && codename="buster" && codeid="debian"
		[[ "${codename}" == "ulyana" || "${codename}" == "jammy" ]] && codename="focal" && codeid="ubuntu"

		# different binaries for some. TBD. Need to check for all others
		[[ "${codename}" =~ focal|hirsute ]] && DOCKER_BINARY="docker containerd docker.io"

		display_alert "Docker not installed." "Installing" "Info"
		sudo bash -c "echo \"deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/${codeid} ${codename} stable\" > /etc/apt/sources.list.d/docker.list"

		sudo bash -c "curl -fsSL \"https://download.docker.com/linux/${codeid}/gpg\" | apt-key add -qq - > /dev/null 2>&1 "
		export DEBIAN_FRONTEND=noninteractive
		sudo apt-get update
		sudo apt-get install -y -qq --no-install-recommends ${DOCKER_BINARY}
		display_alert "Add yourself to docker group to avoid root privileges" "" "wrn"
		"${SRC}/compile.sh" "$@"
		exit $?
	fi
}

# "docker info" is expensive to run, so cache it. output globals DOCKER_INFO and DOCKER_INFO_OK=yes/no
function get_docker_info_once() {
	if [[ -z "${DOCKER_INFO}" ]]; then
		declare -g DOCKER_INFO
		# Shenanigans to go around error control & capture output in the same effort.
		DOCKER_INFO="$({ docker info 2> /dev/null && echo "DOCKER_INFO_OK"; } || true)"
		declare -g -r DOCKER_INFO="${DOCKER_INFO}" # readonly

		declare -g DOCKER_INFO_OK="no"
		if [[ "${DOCKER_INFO}" =~ "DOCKER_INFO_OK" ]]; then
			DOCKER_INFO_OK="yes"
		fi
		declare -g -r DOCKER_INFO_OK="${DOCKER_INFO_OK}" # readonly
	fi
	return 0
}

# Usage: if is_docker_ready_to_go; then ...; fi
function is_docker_ready_to_go() {
	# For either Linux or Darwin.
	# Gotta tick all these boxes:
	# 0) NOT ALREADY UNDER DOCKER.
	# 1) can find the `docker` command in the path, via command -v
	# 2) can run `docker info` without errors
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		display_alert "Can't use Docker" "Actually ALREADY UNDER DOCKER!" "debug"
		return 1
	fi
	if [[ -z "$(command -v docker)" ]]; then
		display_alert "Can't use Docker" "docker command not found" "debug"
		return 1
	fi

	get_docker_info_once

	if [[ "${DOCKER_INFO_OK}" != "yes" ]]; then
		display_alert "Can't use Docker" "docker -- info failed" "debug"
		return 1
	fi

	# If we get here, we're good to go.
	return 0
}

# Called by the cli-entrypoint. At this moment ${1} is already shifted; we know it via ${DOCKER_SUBCMD} now.
function cli_handle_docker() {
	display_alert "Handling" "docker" "info"
	exit 0

	# Purge Armbian Docker images
	if [[ "${1}" == dockerpurge && -f /etc/debian_version ]]; then
		display_alert "Purging Armbian Docker containers" "" "wrn"
		docker container ls -a | grep armbian | awk '{print $1}' | xargs docker container rm &> /dev/null
		docker image ls | grep armbian | awk '{print $3}' | xargs docker image rm &> /dev/null
		# removes "dockerpurge" from $1, thus $2 becomes $1
		shift
		set -- "docker" "$@"
	fi

	# Docker shell
	if [[ "${1}" == docker-shell ]]; then
		# this swaps the value of $1 with 'docker', and life continues
		shift
		SHELL_ONLY=yes
		set -- "docker" "$@"
	fi

}

function docker_cli_prepare() {
	# @TODO: Make sure we can access docker, on Linux; gotta be part of 'docker' group: grep -q "$(whoami)" <(getent group docker)

	declare -g DOCKER_ARMBIAN_INITIAL_IMAGE_TAG="armbian.local.only/armbian-build:initial"
	# declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:bookworm"}"
	# declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:sid"}"
	# declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:bullseye"}"
	# declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"ubuntu:focal"}"
	# declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"ubuntu:kinetic"}"
	declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"ubuntu:jammy"}"
	declare -g DOCKER_ARMBIAN_TARGET_PATH="${DOCKER_ARMBIAN_TARGET_PATH:-"/armbian"}"

	declare wanted_os_tag="${DOCKER_ARMBIAN_BASE_IMAGE%%:*}"
	declare wanted_release_tag="${DOCKER_ARMBIAN_BASE_IMAGE##*:}"

	# Store the "from scratch" image. Will be used if Armbian image is not available, for a "from scratch" build.
	declare -g DOCKER_ARMBIAN_BASE_IMAGE_SCRATCH="${DOCKER_ARMBIAN_BASE_IMAGE}"

	# If we're NOT building the public, official image, then USE the public, official image as base.
	# IMPORTANT: This has to match the naming scheme for tag the is used in the GitHub actions workflow.
	if [[ "${DOCKERFILE_USE_ARMBIAN_IMAGE_AS_BASE}" != "no" && "${DOCKER_SIMULATE_CLEAN}" != "yes" ]]; then
		# @TODO: this is rpardini's build. It's done in a different repo, so that's why the strange "armbian-release" name. It should be armbian/build:ubuntu-jammy-latest or something.
		DOCKER_ARMBIAN_BASE_IMAGE="ghcr.io/rpardini/armbian-release:armbian-next-${wanted_os_tag}-${wanted_release_tag}-latest"

		display_alert "Using prebuilt Armbian image as base for '${wanted_os_tag}-${wanted_release_tag}'" "DOCKER_ARMBIAN_BASE_IMAGE: ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
	fi

	# @TODO: this might be unified with prepare_basic_deps
	declare -g -a BASIC_DEPS=("bash" "git" "psmisc" "uuid-runtime")

	#############################################################################################################
	# Prepare some dependencies; these will be used on the Dockerfile

	# initialize the extension manager; enable all extensions; only once..
	if [[ "${docker_prepare_cli_skip_exts:-no}" != "yes" ]]; then
		enable_all_extensions_builtin_and_user
		initialize_extension_manager
	fi
	declare -a -g host_dependencies=()
	host_release="${wanted_release_tag}" early_prepare_host_dependencies
	display_alert "Pre-game host dependencies" "${host_dependencies[*]}" "debug"

	#############################################################################################################
	# Stop here if Docker can't be used at all.
	if ! is_docker_ready_to_go; then
		display_alert "Docker is not ready" "Docker is not available. Make sure you've Docker installed, configured, and running; add your user to the 'docker' group and restart your shell too." "err"
		exit 56
	fi

	#############################################################################################################
	# Detect some docker info; use cached.
	get_docker_info_once

	DOCKER_SERVER_VERSION="$(echo "${DOCKER_INFO}" | grep -i -e "Server Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server version" "${DOCKER_SERVER_VERSION}" "debug"

	DOCKER_SERVER_KERNEL_VERSION="$(echo "${DOCKER_INFO}" | grep -i -e "Kernel Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Kernel version" "${DOCKER_SERVER_KERNEL_VERSION}" "debug"

	DOCKER_SERVER_TOTAL_RAM="$(echo "${DOCKER_INFO}" | grep -i -e "Total memory\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Total RAM" "${DOCKER_SERVER_TOTAL_RAM}" "debug"

	DOCKER_SERVER_CPUS="$(echo "${DOCKER_INFO}" | grep -i -e "CPUs\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server CPUs" "${DOCKER_SERVER_CPUS}" "debug"

	DOCKER_SERVER_OS="$(echo "${DOCKER_INFO}" | grep -i -e "Operating System\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server OS" "${DOCKER_SERVER_OS}" "debug"

	declare -g DOCKER_ARMBIAN_HOST_OS_UNAME
	DOCKER_ARMBIAN_HOST_OS_UNAME="$(uname)"
	display_alert "Local uname" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"

	DOCKER_BUILDX_VERSION="$(echo "${DOCKER_INFO}" | grep -i -e "buildx\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Buildx version" "${DOCKER_BUILDX_VERSION}" "debug"

	declare -g DOCKER_HAS_BUILDX=no
	declare -g -a DOCKER_BUILDX_OR_BUILD=("build")
	if [[ -n "${DOCKER_BUILDX_VERSION}" ]]; then
		DOCKER_HAS_BUILDX=yes
		DOCKER_BUILDX_OR_BUILD=("buildx" "build" "--progress=plain" "--load")
	fi
	display_alert "Docker has buildx?" "${DOCKER_HAS_BUILDX}" "debug"

	DOCKER_SERVER_NAME_HOST="$(echo "${DOCKER_INFO}" | grep -i -e "name\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Hostname" "${DOCKER_SERVER_NAME_HOST}" "debug"

	# Gymnastics: under Darwin, Docker Desktop and Rancher Desktop in dockerd mode behave differently.
	declare -g DOCKER_SERVER_REQUIRES_LOOP_HACKS=yes DOCKER_SERVER_USE_STATIC_LOOPS=no
	if [[ "${DOCKER_ARMBIAN_HOST_OS_UNAME}" == "Darwin" ]]; then
		case "${DOCKER_SERVER_NAME_HOST}" in
			lima-rancher-desktop)
				display_alert "Detected Rancher Desktop" "due to lima-rancher-desktop; EXPERIMENTAL" "warn"
				DOCKER_SERVER_USE_STATIC_LOOPS=yes # use static list; the 'host' is not the real Linux machine.
				;;
			docker-desktop)
				display_alert "Detected Docker Desktop under Darwin" "due to docker-desktop" "info"
				DOCKER_SERVER_USE_STATIC_LOOPS=yes # use static list; the 'host' is not the real Linux machine.
				# Alternatively, set DOCKER_SERVER_REQUIRES_LOOP_HACKS=no which somehow works without any CONTAINER_COMPAT hacks.
				;;
			*)
				display_alert "Not Docker Desktop nor Rancher Desktop" "due to ${DOCKER_SERVER_NAME_HOST}" "debug"
				;;
		esac
	fi

	# Info summary message. Thank you, GitHub Co-pilot!
	display_alert "Docker info" "Docker ${DOCKER_SERVER_VERSION} Kernel:${DOCKER_SERVER_KERNEL_VERSION} RAM:${DOCKER_SERVER_TOTAL_RAM} CPUs:${DOCKER_SERVER_CPUS} OS:'${DOCKER_SERVER_OS}' hostname '${DOCKER_SERVER_NAME_HOST}' under '${DOCKER_ARMBIAN_HOST_OS_UNAME}' - buildx:${DOCKER_HAS_BUILDX} - loop-hacks:${DOCKER_SERVER_REQUIRES_LOOP_HACKS} static-loops:${DOCKER_SERVER_USE_STATIC_LOOPS}" "sysinfo"

	# @TODO: grab git info, add as labels et al to Docker... (already done in GHA workflow)

	display_alert "Creating" ".dockerignore" "info"
	cat <<- DOCKERIGNORE > "${SRC}"/.dockerignore
		# Start by ignoring everything
		*

		# Include certain files and directories; mostly the build system, but not other parts.
		!/VERSION
		!/LICENSE
		!/compile.sh
		!/lib
		!/extensions
		!/config/sources
		!/config/templates

		# Ignore unnecessary files inside include directories
		# This should go after the include directories
		**/*~
		**/*.log
		**/.DS_Store
	DOCKERIGNORE

	# This includes apt install equivalent to install_host_dependencies()
	display_alert "Creating" "Dockerfile; FROM ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
	declare c="" # Nothing; commands will run.
	if [[ "${DOCKER_SIMULATE_CLEAN}" == "yes" ]]; then
		display_alert "Simulating" "clean build, due to DOCKER_SIMULATE_CLEAN=yes -- this is wasteful and slow and only for debugging" "warn"
		c="## " # Add comment to simulate clean env
	fi
	cat <<- INITIAL_DOCKERFILE > "${SRC}"/Dockerfile
		${c}# PLEASE DO NOT MODIFY THIS FILE. IT IS AUTOGENERATED AND WILL BE OVERWRITTEN. Please don't build this Dockerfile yourself either. Use Armbian ./compile.sh instead.
		FROM ${DOCKER_ARMBIAN_BASE_IMAGE}
		${c}# PLEASE DO NOT MODIFY THIS FILE. IT IS AUTOGENERATED AND WILL BE OVERWRITTEN. Please don't build this Dockerfile yourself either. Use Armbian ./compile.sh instead.
		${c}RUN echo "--> CACHE MISS IN DOCKERFILE: apt packages." && \\
		${c} DEBIAN_FRONTEND=noninteractive apt-get -y update && \\
		${c} DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${BASIC_DEPS[@]} ${host_dependencies[@]}
		${c}RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		${c}RUN locale-gen
		WORKDIR ${DOCKER_ARMBIAN_TARGET_PATH}
		ENV ARMBIAN_RUNNING_IN_CONTAINER=yes
		ADD . ${DOCKER_ARMBIAN_TARGET_PATH}/
		${c}RUN echo "--> CACHE MISS IN DOCKERFILE: running Armbian requirements initialization." && \\
		${c} ARMBIAN_INSIDE_DOCKERFILE_BUILD="yes" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" requirements SHOW_LOG=yes && \\
		${c} rm -rf "${DOCKER_ARMBIAN_TARGET_PATH}/output" "${DOCKER_ARMBIAN_TARGET_PATH}/.tmp" "${DOCKER_ARMBIAN_TARGET_PATH}/cache"
	INITIAL_DOCKERFILE
	# For debugging: RUN rm -fv /usr/bin/pip3 # Remove pip3 symlink to make sure we're not depending on it; non-Dockers may not have it

}
function docker_cli_build_dockerfile() {
	local do_force_pull="no"
	local local_image_sha

	declare docker_marker_dir="${SRC}"/cache/docker

	# If cache dir exists, but we can't write to cache dir...
	if [[ -d "${SRC}"/cache ]] && [[ ! -w "${SRC}"/cache ]]; then
		display_alert "Cannot write to cache/docker" "probably trying to share a cache with 'sudo' version" "err"
		display_alert "Sharing a cache directory between sudo and Docker is not tested." "Proceed at your own risk" "warn"
		countdown_and_continue_if_not_aborted 10
		# Use fake marker in .tmp, which should be writable always.
		docker_marker_dir="${SRC}"/.tmp/docker
	fi

	run_host_command_logged mkdir -p "${docker_marker_dir}"

	# Find files under "${SRC}"/cache/docker that are older than 1 day, and delete them.
	EXPIRED_MARKER="$(find "${docker_marker_dir}" -type f -mtime +1 -exec echo -n {} \;)"
	display_alert "Expired marker?" "${EXPIRED_MARKER}" "debug"

	if [[ "x${EXPIRED_MARKER}x" != "xx" ]]; then
		display_alert "More than" "1 day since last pull, pulling again" "info"
		do_force_pull="yes"
	fi

	if [[ "${do_force_pull}" == "no" ]]; then
		# Check if the base image is up to date.
		local_image_sha="$(docker images --no-trunc --quiet "${DOCKER_ARMBIAN_BASE_IMAGE}")"
		display_alert "Checking if base image exists at all" "local_image_sha: '${local_image_sha}'" "debug"
		if [[ -n "${local_image_sha}" ]]; then
			display_alert "Armbian docker image" "already exists: ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
		else
			display_alert "Armbian docker image" "does not exist: ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
			do_force_pull="yes"
		fi
	fi

	if [[ "${do_force_pull:-yes}" == "yes" ]]; then
		display_alert "Pulling" "${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
		local pull_failed="yes"
		run_host_command_logged docker pull "${DOCKER_ARMBIAN_BASE_IMAGE}" && pull_failed="no"

		if [[ "${pull_failed}" == "no" ]]; then
			local_image_sha="$(docker images --no-trunc --quiet "${DOCKER_ARMBIAN_BASE_IMAGE}")"
			display_alert "New local image sha after pull" "local_image_sha: ${local_image_sha}" "debug"
			# print current date and time in epoch format; touches mtime of file
			echo "${DOCKER_ARMBIAN_BASE_IMAGE}|${local_image_sha}|$(date +%s)" >> "${docker_marker_dir}"/last-pull
		else
			display_alert "Failed to pull" "${DOCKER_ARMBIAN_BASE_IMAGE}; will build from scratch instead" "wrn"
		fi
	fi

	# If we get here without a local_image_sha, we need to build from scratch, so we need to re-create the Dockerfile.
	if [[ -z "${local_image_sha}" ]]; then
		display_alert "Base image not in local cache, building from scratch" "${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
		export DOCKERFILE_USE_ARMBIAN_IMAGE_AS_BASE=no
		export DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE_SCRATCH}"
		docker_prepare_cli_skip_exts="yes" docker_cli_prepare
		display_alert "Re-created" "Dockerfile, proceeding, build from scratch" "debug"
	fi

	display_alert "Building" "Dockerfile via '${DOCKER_BUILDX_OR_BUILD[*]}'" "info"

	BUILDKIT_COLORS="run=123,20,245:error=yellow:cancel=blue:warning=white" \
		run_host_command_logged docker "${DOCKER_BUILDX_OR_BUILD[@]}" -t "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" -f "${SRC}"/Dockerfile "${SRC}"
}

function docker_cli_prepare_launch() {
	display_alert "Preparing" "common Docker arguments" "debug"
	declare -g -a DOCKER_ARGS=(
		"--rm" # side effect - named volumes are considered not attached to anything and are removed on "docker volume prune", since container was removed.

		"--privileged"         # Running this container in privileged mode is a simple way to solve loop device access issues, required for USB FEL or when writing image directly to the block device, when CARD_DEVICE is defined
		"--cap-add=SYS_ADMIN"  # add only required capabilities instead
		"--cap-add=MKNOD"      # (though MKNOD should be already present)
		"--cap-add=SYS_PTRACE" # CAP_SYS_PTRACE is required for systemd-detect-virt in some cases @TODO: rpardini: so lets eliminate it

		# Pass env var ARMBIAN_RUNNING_IN_CONTAINER to indicate we're running under Docker. This is also set in the Dockerfile; make sure.
		"--env" "ARMBIAN_RUNNING_IN_CONTAINER=yes"

		# This env var is used super early (in entrypoint.sh), so set it as an env to current value.
		"--env" "ARMBIAN_ENABLE_CALL_TRACING=${DOCKER_ARMBIAN_ENABLE_CALL_TRACING:-no}"

		# Change the ccache directory to the named volume or bind created.
		"--env" "CCACHE_DIR=${DOCKER_ARMBIAN_TARGET_PATH}/cache/ccache"

		# Pass down the TERM
		"--env" "TERM=${TERM}"

		# Pass down the CI env var (GitHub Actions, Jenkins, etc)
		"--env" "CI=${CI}"                         # All CI's, hopefully
		"--env" "GITHUB_ACTIONS=${GITHUB_ACTIONS}" # GHA
		# All known valid Github Actions env vars
		"--env" "GITHUB_ACTION=${GITHUB_ACTION}"
		"--env" "GITHUB_ACTOR=${GITHUB_ACTOR}"
		"--env" "GITHUB_API_URL=${GITHUB_API_URL}"
		"--env" "GITHUB_BASE_REF=${GITHUB_BASE_REF}"
		"--env" "GITHUB_ENV=${GITHUB_ENV}"
		"--env" "GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME}"
		"--env" "GITHUB_EVENT_PATH=${GITHUB_EVENT_PATH}"
		"--env" "GITHUB_GRAPHQL_URL=${GITHUB_GRAPHQL_URL}"
		"--env" "GITHUB_HEAD_REF=${GITHUB_HEAD_REF}"
		"--env" "GITHUB_JOB=${GITHUB_JOB}"
		"--env" "GITHUB_PATH=${GITHUB_PATH}"
		"--env" "GITHUB_REF=${GITHUB_REF}"
		"--env" "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
		"--env" "GITHUB_REPOSITORY_OWNER=${GITHUB_REPOSITORY_OWNER}"
		"--env" "GITHUB_RETENTION_DAYS=${GITHUB_RETENTION_DAYS}"
		"--env" "GITHUB_RUN_ID=${GITHUB_RUN_ID}"
		"--env" "GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER}"
		"--env" "GITHUB_SERVER_URL=${GITHUB_SERVER_URL}"
		"--env" "GITHUB_SHA=${GITHUB_SHA}"
		"--env" "GITHUB_WORKFLOW=${GITHUB_WORKFLOW}"
		"--env" "GITHUB_WORKSPACE=${GITHUB_WORKSPACE}"
	)

	# If running on GitHub Actions, mount & forward some paths, so they're accessible inside Docker.
	if [[ "${CI}" == "true" ]] && [[ "${GITHUB_ACTIONS}" == "true" ]]; then
		display_alert "Passing down to Docker" "GITHUB_OUTPUT: '${GITHUB_OUTPUT}'" "info"
		DOCKER_ARGS+=("--mount" "type=bind,source=${GITHUB_OUTPUT},target=${GITHUB_OUTPUT}")
		DOCKER_ARGS+=("--env" "GITHUB_OUTPUT=${GITHUB_OUTPUT}")

		display_alert "Passing down to Docker" "GITHUB_STEP_SUMMARY: '${GITHUB_STEP_SUMMARY}'" "info"
		DOCKER_ARGS+=("--mount" "type=bind,source=${GITHUB_STEP_SUMMARY},target=${GITHUB_STEP_SUMMARY}")
		DOCKER_ARGS+=("--env" "GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY}")
	fi

	# This will receive the mountpoint as $1 and the mountpoint vars in the environment.
	function prepare_docker_args_for_mountpoint() {
		local MOUNT_DIR="$1"
		# shellcheck disable=SC2154 # $docker_kind: the kind of volume to mount on this OS; see mountpoints.sh
		#display_alert "Handling Docker mountpoint" "${MOUNT_DIR} id: ${volume_id} - docker_kind: ${docker_kind}" "debug"

		case "${docker_kind}" in
			anonymous)
				display_alert "Mounting" "anonymous volume for '${MOUNT_DIR}'" "debug"
				# type=volume, without source=, is an anonymous volume -- will be auto cleaned up together with the container;
				# this could also be a type=tmpfs if you had enough ram - but armbian already does tmpfs for you if you
				#                                                         have enough RAM (inside the container) so don't bother.
				DOCKER_ARGS+=("--mount" "type=volume,destination=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
				;;
			bind)
				display_alert "Mounting" "bind mount for '${MOUNT_DIR}'" "debug"
				mkdir -p "${SRC}/${MOUNT_DIR}"
				DOCKER_ARGS+=("--mount" "type=bind,source=${SRC}/${MOUNT_DIR},target=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
				;;
			namedvolume)
				display_alert "Mounting" "named volume id '${volume_id}' for '${MOUNT_DIR}'" "debug"
				DOCKER_ARGS+=("--mount" "type=volume,source=armbian-${volume_id},destination=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
				;;
			*)
				display_alert "Unknown Mountpoint Type" "unknown volume type '${docker_kind}' for '${MOUNT_DIR}'" "err"
				exit 1
				;;
		esac
	}

	loop_over_armbian_mountpoints prepare_docker_args_for_mountpoint

	# @TODO: auto-compute this list; just get the dirs and filter some out?
	for MOUNT_DIR in "lib" "config" "extensions" "packages" "patch" "tools" "userpatches"; do
		mkdir -p "${SRC}/${MOUNT_DIR}"
		DOCKER_ARGS+=("--mount" "type=bind,source=${SRC}/${MOUNT_DIR},target=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
	done

	if [[ "${DOCKER_SERVER_REQUIRES_LOOP_HACKS}" == "yes" ]]; then
		display_alert "Adding /dev/loop* hacks for" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"
		DOCKER_ARGS+=("--security-opt=apparmor:unconfined") # mounting things inside the container on Ubuntu won't work without this https://github.com/moby/moby/issues/16429#issuecomment-217126586
		DOCKER_ARGS+=(--device-cgroup-rule='b 7:* rmw')     # allow loop devices (not required)
		DOCKER_ARGS+=(--device-cgroup-rule='b 259:* rmw')   # allow loop device partitions
		DOCKER_ARGS+=(-v /dev:/tmp/dev:ro)                  # this is an ugly hack (CONTAINER_COMPAT=y), but it is required to get /dev/loopXpY minor number for mknod inside the container, and container itself still uses private /dev internally

		if [[ "${DOCKER_SERVER_USE_STATIC_LOOPS}" == "yes" ]]; then
			for loop_device_host in "/dev/loop-control" "/dev/loop0" "/dev/loop1" "/dev/loop2" "/dev/loop3" "/dev/loop4" "/dev/loop5" "/dev/loop6" "/dev/loop7"; do # static list; "host" is not real, there's a VM intermediary
				display_alert "Passing through host loop device to Docker" "static: ${loop_device_host}" "debug"
				DOCKER_ARGS+=("--device=${loop_device_host}")
			done
		else
			for loop_device_host in /dev/loop*; do # pass through loop devices from host to container; includes `loop-control`
				display_alert "Passing through host loop device to Docker" "host: ${loop_device_host}" "debug"
				DOCKER_ARGS+=("--device=${loop_device_host}")
			done
		fi

	else
		display_alert "Skipping /dev/loop* hacks for" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"
	fi

	if [[ -t 0 ]]; then
		display_alert "Running in a terminal" "passing through stdin" "debug"
		DOCKER_ARGS+=("-it")
	else
		display_alert "Not running in a terminal" "not passing through stdin to Docker" "debug"
	fi

	# if DOCKER_EXTRA_ARGS is an array and has more than zero elements, add its contents to the DOCKER_ARGS array
	if [[ "${DOCKER_EXTRA_ARGS[*]+isset}" == "isset" && "${#DOCKER_EXTRA_ARGS[@]}" -gt 0 ]]; then
		display_alert "Adding extra Docker arguments" "${DOCKER_EXTRA_ARGS[*]}" "debug"
		DOCKER_ARGS+=("${DOCKER_EXTRA_ARGS[@]}")
	fi

}

function docker_cli_launch() {
	display_alert "Showing Docker cmdline" "Docker args: '${DOCKER_ARGS[*]}'" "debug"

	# Hack: if we're running on a Mac/Darwin, get rid of .DS_Store files in critical directories.
	if [[ "${OSTYPE}" == "darwin"* ]]; then
		display_alert "Removing .DS_Store files from source directories" "for Mac/Darwin compatibility" "debug"
		run_host_command_logged find "${SRC}/config" -name ".DS_Store" -type f -delete "||" true
		run_host_command_logged find "${SRC}/packages" -name ".DS_Store" -type f -delete "||" true
		run_host_command_logged find "${SRC}/patch" -name ".DS_Store" -type f -delete "||" true
		run_host_command_logged find "${SRC}/userpatches" -name ".DS_Store" -type f -delete "||" true
	fi

	display_alert "Relaunching in Docker" "${*}" "debug"
	display_alert "-----------------Relaunching in Docker------------------------------------" "here comes the 🐳" "info"

	local -i docker_build_result
	if docker run "${DOCKER_ARGS[@]}" "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" "$@"; then
		docker_build_result=$? # capture exit code of test done in the line above.
		display_alert "-------------Docker run finished------------------------------------------" "successfully" "info"
	else
		docker_build_result=$? # capture exit code of test done 4 lines above.
		display_alert "-------------Docker run failed--------------------------------------------" "with errors" "err"
	fi

	# Find and show the path to the log file for the ARMBIAN_BUILD_UUID.
	local logs_path="${DEST}/logs" log_file
	log_file="$(find "${logs_path}" -type f -name "*${ARMBIAN_BUILD_UUID}*.*" -print -quit)"
	docker_produced_logs=0 # outer scope variable
	if [[ -f "${log_file}" ]]; then
		docker_produced_logs=1 # outer scope variable
		display_alert "Build log done inside Docker" "${log_file}" "debug"
	else
		display_alert "Docker Log file for this run" "not found" "err"
	fi

	# Show and help user understand space usage in Docker volumes.
	# This is done in a loop; `docker df` fails sometimes (for no good reason).
	# @TODO: this is very, very slow when the volumes are full. disable.
	# docker_cli_show_armbian_volumes_disk_usage

	docker_exit_code="${docker_build_result}" # set outer scope variable -- do NOT exit with error.

	# return ${docker_build_result}
	return 0 # always exit with success. caller (CLI) will handle the exit code
}

function docker_cli_show_armbian_volumes_disk_usage() {
	display_alert "Gathering docker volumes disk usage" "docker system df, wait..." "debug"
	sleep_seconds="1" silent_retry="yes" do_with_retries 5 docker_cli_show_armbian_volumes_disk_usage_internal || {
		display_alert "Could not get Docker volumes disk usage" "docker failed to report disk usage" "warn"
		return 0 # not really a problem, just move on.
	}
	local docker_volume_usage
	docker_volume_usage="$(docker system df -v | grep -e "^armbian-" | grep -v "\b0B" | tr -s " " | cut -d " " -f 1,3 | tr " " ":" | xargs echo || true)"
	display_alert "Docker Armbian volume usage" "${docker_volume_usage}" "info"
}

function docker_cli_show_armbian_volumes_disk_usage_internal() {
	# This fails sometimes, for no reason. Test it.
	if docker system df -v &> /dev/null; then
		return 0
	else
		return 1
	fi
}

function docker_purge_deprecated_volumes() {
	prepare_armbian_mountpoints_description_dict
	local mountpoint=""
	for mountpoint in "${ARMBIAN_MOUNTPOINTS_DEPRECATED[@]}"; do
		local volume_id="armbian-${mountpoint//\//-}"
		display_alert "Purging deprecated Docker volume" "${volume_id}" "info"
		if docker volume inspect "${volume_id}" &> /dev/null; then
			run_host_command_logged docker volume rm "${volume_id}"
			display_alert "Purged deprecated Docker volume" "${volume_id} OK" "info"
		else
			display_alert "Deprecated Docker volume not found" "${volume_id} OK" "info"
		fi
	done
}

# Leftovers from original Dockerfile before rewrite
## OLD DOCKERFILE ## RUN locale-gen en_US.UTF-8
## OLD DOCKERFILE ##
## OLD DOCKERFILE ## # Static port for NFSv3 server used for USB FEL boot
## OLD DOCKERFILE ## RUN sed -i 's/\(^STATDOPTS=\).*/\1"--port 32765 --outgoing-port 32766"/' /etc/default/nfs-common \
## OLD DOCKERFILE ##     && sed -i 's/\(^RPCMOUNTDOPTS=\).*/\1"--port 32767"/' /etc/default/nfs-kernel-server
## OLD DOCKERFILE ##
## OLD DOCKERFILE ## ENTRYPOINT [ "/bin/bash", "/root/armbian/compile.sh" ]
