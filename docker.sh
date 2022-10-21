#!/usr/bin/env bash

# @TODO: env passing. people (err... me) pass ENV vars to ./compile.sh so they're active before cmdline options are parsed.
# we'd need to re-pass like (sudo --preserve-env) envs to Docker, or find a solution. or just rewrite overwrites in armbian itself to run super-early & then again where it is now.

# @TODO: integrate logs?

#

#set -o pipefail  # trace ERR through pipes - will be enabled "soon"
#set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable - one day will be enabled
set -e
set -o errtrace # trace ERR through - enabled
set -o errexit  ## set -e : exit the script if any statement returns a non-true return value - enabled
# Important, go read http://mywiki.wooledge.org/BashFAQ/105 NOW!

SRC="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd "${SRC}" || exit

# check for whitespace in ${SRC} and exit for safety reasons
grep -q "[[:space:]]" <<< "${SRC}" && {
	echo "\"${SRC}\" contains whitespace. Not supported. Aborting." >&2
	exit 1
}

# Sanity check.
if [[ ! -f "${SRC}"/lib/single.sh ]]; then
	echo "Error: missing build directory structure"
	echo "Please clone the full repository https://github.com/armbian/build/"
	exit 255
fi

# shellcheck source=lib/single.sh
source "${SRC}"/lib/single.sh

#############################################################################################################

function docker_cli_prepare() {
	declare -g DOCKER_ARMBIAN_INITIAL_IMAGE_TAG="armbian.local.only/armbian-build:initial"
	#declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:bookworm"}" # works Linux & Darwin
	#declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:sid"}"      # works Linux & Darwin
	#declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:bullseye"}" # does NOT work under Darwin? loop problems.
	declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"ubuntu:jammy"}" # works Linux & Darwin
	declare -g DOCKER_ARMBIAN_TARGET_PATH="${DOCKER_ARMBIAN_TARGET_PATH:-"/armbian"}"

	# If we're NOT building the public, official image, then USE the public, official image as base.
	# IMPORTANT: This has to match the naming scheme for tag the is used in the GitHub actions workflow.
	if [[ "${DOCKERFILE_USE_ARMBIAN_IMAGE_AS_BASE}" != "no" ]]; then
		local wanted_os_tag="${DOCKER_ARMBIAN_BASE_IMAGE%%:*}"
		local wanted_release_tag="${DOCKER_ARMBIAN_BASE_IMAGE##*:}"

		# @TODO: this is rpardini's build. It's done in a different repo, so that's why the strange "armbian-release" name. It should be armbian/build:ubuntu-jammy-latest or something.
		DOCKER_ARMBIAN_BASE_IMAGE="ghcr.io/rpardini/armbian-release:armbian-next-${wanted_os_tag}-${wanted_release_tag}-latest"

		display_alert "Using official Armbian image as base for '${wanted_os_tag}-${wanted_release_tag}'" "DOCKER_ARMBIAN_BASE_IMAGE: ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
	fi

	# @TODO: this might be unified with prepare_basic_deps
	declare -g -a BASIC_DEPS=("bash" "git" "psmisc" "uuid-runtime")

	#############################################################################################################
	# Prepare some dependencies; these will be used on the Dockerfile

	declare -a -g host_dependencies=()
	REQUIREMENTS_DEFS_ONLY=yes early_prepare_host_dependencies
	display_alert "Pre-game dependencies" "${host_dependencies[*]}" "info"

	#############################################################################################################
	# Detect some docker info.

	DOCKER_SERVER_VERSION="$(docker info | grep -i -e "Server Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server version" "${DOCKER_SERVER_VERSION}" "info"

	DOCKER_SERVER_KERNEL_VERSION="$(docker info | grep -i -e "Kernel Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Kernel version" "${DOCKER_SERVER_KERNEL_VERSION}" "info"

	DOCKER_BUILDX_VERSION="$(docker info | grep -i -e "buildx\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Buildx version" "${DOCKER_BUILDX_VERSION}" "info"

	DOCKER_SERVER_TOTAL_RAM="$(docker info | grep -i -e "Total memory\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Total RAM" "${DOCKER_SERVER_TOTAL_RAM}" "info"

	DOCKER_SERVER_CPUS="$(docker info | grep -i -e "CPUs\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server CPUs" "${DOCKER_SERVER_CPUS}" "info"

	DOCKER_SERVER_OS="$(docker info | grep -i -e "Operating System\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server OS" "${DOCKER_SERVER_OS}" "info"

	declare -g DOCKER_ARMBIAN_HOST_OS_UNAME
	DOCKER_ARMBIAN_HOST_OS_UNAME="$(uname)"
	display_alert "Local uname" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "info"

	declare -g DOCKER_HAS_BUILDX=no
	declare -g -a DOCKER_BUILDX_OR_BUILD=("build")
	if [[ -n "${DOCKER_BUILDX_VERSION}" ]]; then
		DOCKER_HAS_BUILDX=yes
		DOCKER_BUILDX_OR_BUILD=("buildx" "build" "--progress=plain")
	fi
	display_alert "Docker has buildx?" "${DOCKER_HAS_BUILDX}" "info"

	# @TODO: grab git info, add as labels et al to Docker...

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

	display_alert "Creating" "Dockerfile" "info"
	cat <<- INITIAL_DOCKERFILE > "${SRC}"/Dockerfile
		FROM ${DOCKER_ARMBIAN_BASE_IMAGE}
		# PLEASE DO NOT MODIFY THIS FILE. IT IS AUTOGENERATED AND WILL BE OVERWRITTEN. Please don't build this Dockerfile yourself either. Use Armbian helpers instead.
		RUN echo "--> CACHE MISS IN DOCKERFILE: apt packages." >&2 && \
			DEBIAN_FRONTEND=noninteractive apt-get -y update && \
			DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${BASIC_DEPS[@]} ${host_dependencies[@]}
		WORKDIR ${DOCKER_ARMBIAN_TARGET_PATH}
		ENV ARMBIAN_RUNNING_IN_CONTAINER=yes
		ADD . ${DOCKER_ARMBIAN_TARGET_PATH}/
		RUN echo "--> CACHE MISS IN DOCKERFILE: build system script files changed." >&2 && \
			ls -laRht ${DOCKER_ARMBIAN_TARGET_PATH}
		RUN echo "--> CACHE MISS IN DOCKERFILE: running Armbian requirements initialization." >&2 && \
			uname -a && cat /etc/os-release && \
			free -h && df -h && lscpu && \
			/bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" REQUIREMENTS_DEFS_ONLY=yes SHOW_DEBUG=yes SHOW_COMMAND=yes SHOW_LOG=yes && \
			rm -rfv "${DOCKER_ARMBIAN_TARGET_PATH}/output" "${DOCKER_ARMBIAN_TARGET_PATH}/.tmp" "${DOCKER_ARMBIAN_TARGET_PATH}/cache" 
	INITIAL_DOCKERFILE

}
function docker_cli_build_dockerfile() {
	display_alert "Armbian docker launcher" "docker" "info"
	local do_force_pull="no"
	local local_image_sha

	mkdir -p "${SRC}"/cache/docker

	# Find files under "${SRC}"/cache/docker that are older than 1 day, and delete them.
	EXPIRED_MARKER="$(find "${SRC}"/cache/docker -type f -mtime +1 -exec echo -n {} \;)"
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
		run_host_command_logged docker pull "${DOCKER_ARMBIAN_BASE_IMAGE}"
		local_image_sha="$(docker images --no-trunc --quiet "${DOCKER_ARMBIAN_BASE_IMAGE}")"
		display_alert "New local image sha after pull" "local_image_sha: ${local_image_sha}" "debug"
		# print current date and time in epoch format; touches mtime of file
		echo "${DOCKER_ARMBIAN_BASE_IMAGE}|${local_image_sha}|$(date +%s)" >> "${SRC}"/cache/docker/last-pull
	fi

	display_alert "Building" "Dockerfile via '${DOCKER_BUILDX_OR_BUILD[*]}'" "info"

	BUILDKIT_COLORS="run=123,20,245:error=yellow:cancel=blue:warning=white" \
		run_host_command_logged docker "${DOCKER_BUILDX_OR_BUILD[@]}" -t "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" -f "${SRC}"/Dockerfile "${SRC}"
}

function docker_cli_prepare_launch() {
	# array for the generic armbian 'volumes' and their paths. Less specific first.
	# @TODO: actually use this for smth.
	declare -A -g DOCKER_ARMBIAN_VOLUMES=(
		[".tmp"]="linux=anonymous darwin=anonymous"                    # tmpfs, discard, anonymous; whatever you wanna call  it. It just needs to be 100% local to the container, and there's very little value in being able to look at it from the host.
		["output"]="linux=bind darwin=bind"                            # catch-all output. specific subdirs are mounted below. it's a bind mount by default on both Linux and Darwin.
		["output/images"]="linux=bind darwin=bind"                     # 99% of users want this as the result of their build, no matter if it's slow or not. bind on both.
		["output/debs"]="linux=bind darwin=namedvolume"                # generated output .deb files. not everyone is interested in this: most users just want images. Linux has fast binds, so bound by default. Darwin has slow binds, so it's a volume by default.
		["output/logs"]="linux=bind darwin=bind"                       # log files produced. 100% of users want this. Bind on both Linux and Darwin. Is used to integrate launcher and actual-build logs, so must exist and work otherwise confusion ensues.
		["cache"]="linux=bind darwin=namedvolume"                      # catch-all cache, could be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/gitballs"]="linux=bind darwin=namedvolume"             # tarballs of git repos, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/toolchain"]="linux=bind darwin=namedvolume"            # toolchain cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/aptcache"]="linux=bind darwin=namedvolume"             # .deb apt cache, replaces apt-cacher-ng. Can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/rootfs"]="linux=bind darwin=namedvolume"               # rootfs .tar.zst cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/initrd"]="linux=bind darwin=namedvolume"               # initrd.img cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/sources"]="linux=bind darwin=namedvolume"              # operating directory. many things are cloned in here, and some are even built inside. needs to be local to the container, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/sources/linux-kernel"]="linux=bind darwin=namedvolume" # working tree for kernel builds. huge. contains both sources and the built object files. needs to be local to the container, so it's a volume by default. On Linux, it's a bind-mount by default.
	)

	display_alert "Preparing" "common Docker arguments" "info"
	declare -g -a DOCKER_ARGS=(
		"--rm" # side effect - named volumes are considered not attached to anything and are removed on "docker volume prune", since container was removed.

		"--privileged"         # Running this container in privileged mode is a simple way to solve loop device access issues, required for USB FEL or when writing image directly to the block device, when CARD_DEVICE is defined
		"--cap-add=SYS_ADMIN"  # add only required capabilities instead
		"--cap-add=MKNOD"      # (though MKNOD should be already present)
		"--cap-add=SYS_PTRACE" # CAP_SYS_PTRACE is required for systemd-detect-virt in some cases @TODO: rpardini: so lets eliminate it

		# "--mount" "type=bind,source=${SRC}/lib,target=${DOCKER_ARMBIAN_TARGET_PATH}/lib"

		# type=volume, without source=, is an anonymous volume -- will be auto cleaned up together with the container;
		# this could also be a type=tmpfs if you had enough ram - but armbian already does tmpfs for you if you
		#                                                         have enough RAM (inside the container) so don't bother.
		"--mount" "type=volume,destination=${DOCKER_ARMBIAN_TARGET_PATH}/.tmp"

		# named volumes for different parts of the cache. so easy for user to drop any of them when needed
		# @TODO: refactor this; this is only ideal for Darwin right now. Use DOCKER_ARMBIAN_VOLUMES to generate this.
		"--mount" "type=volume,source=armbian-cache-parent,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache"
		"--mount" "type=volume,source=armbian-cache-gitballs,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/gitballs"
		"--mount" "type=volume,source=armbian-cache-toolchain,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/toolchain"
		"--mount" "type=volume,source=armbian-cache-aptcache,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/aptcache"
		"--mount" "type=volume,source=armbian-cache-rootfs,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/rootfs"
		"--mount" "type=volume,source=armbian-cache-initrd,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/initrd"
		"--mount" "type=volume,source=armbian-cache-sources,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/sources"
		"--mount" "type=volume,source=armbian-cache-sources-linux-kernel,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/sources/linux-kernel"

		# Pass env var ARMBIAN_RUNNING_IN_CONTAINER to indicate we're running under Docker. This is also set in the Dockerfile; make sure.
		"--env" "ARMBIAN_RUNNING_IN_CONTAINER=yes"
	)

	# @TODO: auto-compute this list; just get the dirs and filter some out
	for MOUNT_DIR in "lib" "config" "extensions" "packages" "patch" "tools" "userpatches" "output"; do
		mkdir -p "${SRC}/${MOUNT_DIR}"
		DOCKER_ARGS+=("--mount" "type=bind,source=${SRC}/${MOUNT_DIR},target=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
	done

	# eg: NOT on Darwin with Docker Desktop, that works simply with --priviledged and the extra caps.
	# those actually _break_ Darwin with Docker Desktop, so we need to detect that.
	if [[ "${DOCKER_ARMBIAN_HOST_OS_UNAME}" == "Linux" ]]; then
		display_alert "Adding /dev/loop* hacks for" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"
		DOCKER_ARGS+=("--security-opt=apparmor:unconfined") # mounting things inside the container on Ubuntu won't work without this https://github.com/moby/moby/issues/16429#issuecomment-217126586
		DOCKER_ARGS+=(--device-cgroup-rule='b 7:* rmw')     # allow loop devices (not required)
		DOCKER_ARGS+=(--device-cgroup-rule='b 259:* rmw')   # allow loop device partitions
		DOCKER_ARGS+=(-v /dev:/tmp/dev:ro)                  # this is an ugly hack (CONTAINER_COMPAT=y), but it is required to get /dev/loopXpY minor number for mknod inside the container, and container itself still uses private /dev internally
		for loop_device_host in /dev/loop*; do              # pass through loop devices from host to container; includes `loop-control`
			DOCKER_ARGS+=("--device=${loop_device_host}")
		done
	else
		display_alert "Skipping /dev/loop* hacks for" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"
	fi

}

function docker_cli_launch() {
	display_alert "Showing Docker characteristics" "Docker args: '${DOCKER_ARGS[*]}'" "info"

	display_alert "Running" "real build: ${*}" "info"
	docker run -it "${DOCKER_ARGS[@]}" "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" "$@"

	display_alert "Done!"

	display_alert "Showing docker volumes usage" "debug"
	docker system df -v | grep -e "^armbian-cache" | grep -v "\b0B" | tr -s " " | cut -d " " -f 1,3
}

# 'main'
export SHOW_LOG=${SHOW_LOG:-yes}
export SHOW_DEBUG=${SHOW_DEBUG:-yes}
export SHOW_COMMAND=${SHOW_COMMAND:-yes}
export SHOW_TRAPS=${SHOW_TRAPS:-yes}
# initialize logging variables.
logging_init

# initialize the traps
traps_init

# create a temp dir where we'll do our business; follow the Armbian convention so we can re-use their functions
export DEST="${SRC}/output/docker-stuff" # required by do_with_logging, not really used
export LOGDIR="${DEST}"
mkdir -p "${DEST}" "${LOGDIR}"

LOG_SECTION="docker_cli_prepare" do_with_logging docker_cli_prepare "$@"

if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
	display_alert "Dockerfile generated" "exiting" "info"
	exit 0
fi

LOG_SECTION="docker_cli_build_dockerfile" do_with_logging docker_cli_build_dockerfile "$@"
LOG_SECTION="docker_cli_prepare_launch" do_with_logging docker_cli_prepare_launch "$@"
docker_cli_launch "$@"
