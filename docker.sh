#!/usr/bin/env bash

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
	#declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"debian:bullseye"}"
	declare -g DOCKER_ARMBIAN_BASE_IMAGE="${DOCKER_ARMBIAN_BASE_IMAGE:-"ubuntu:jammy"}"
	declare -g DOCKER_ARMBIAN_TARGET_PATH="${DOCKER_ARMBIAN_TARGET_PATH:-"/armbian_host_mounted"}"

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
		RUN DEBIAN_FRONTEND=noninteractive apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${BASIC_DEPS[@]} ${host_dependencies[@]}
		WORKDIR ${DOCKER_ARMBIAN_TARGET_PATH}
		ENV ARMBIAN_RUNNING_IN_CONTAINER=yes
		COPY lib ${DOCKER_ARMBIAN_TARGET_PATH}/lib
		COPY config ${DOCKER_ARMBIAN_TARGET_PATH}/config
		COPY extensions ${DOCKER_ARMBIAN_TARGET_PATH}/extensions
		COPY VERSION LICENSE compile.sh ${DOCKER_ARMBIAN_TARGET_PATH}/
		RUN ls -laRht ${DOCKER_ARMBIAN_TARGET_PATH}
		RUN uname -a && cat /etc/os-release
		RUN free -h && df -h && lscpu
		RUN /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" REQUIREMENTS_DEFS_ONLY=yes SHOW_DEBUG=yes SHOW_COMMAND=yes SHOW_LOG=yes
	INITIAL_DOCKERFILE

}
function docker_cli_build_dockerfile() {
	display_alert "Armbian docker launcher" "docker" "info"

	display_alert "Building" "Dockerfile via '${DOCKER_BUILDX_OR_BUILD[*]}'" "info"

	# @TODO: allow for `--pull`
	run_host_command_logged docker "${DOCKER_BUILDX_OR_BUILD[@]}" -t "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" -f "${SRC}"/Dockerfile "${SRC}"
}

function docker_cli_prepare_launch() {
	display_alert "Preparing" "common Docker arguments" "info"
	declare -g -a DOCKER_ARGS=(
		"--rm" # bad side effect - named volumes are considered not attached to anything and are removed on "docker volume prune"

		"--privileged"         # Running this container in privileged mode is a simple way to solve loop device access issues, required for USB FEL or when writing image directly to the block device, when CARD_DEVICE is defined
		"--cap-add=SYS_ADMIN"  # add only required capabilities instead
		"--cap-add=MKNOD"      # (though MKNOD should be already present)
		"--cap-add=SYS_PTRACE" # CAP_SYS_PTRACE is required for systemd-detect-virt in some cases @TODO: rpardini: so lets eliminate it

		"--security-opt=apparmor:unconfined" # mounting things inside the container on Ubuntu won't work without this https://github.com/moby/moby/issues/16429#issuecomment-217126586

		#"--pull"               # pull the base image, don't use outdated local image

		# "--mount" "type=bind,source=${SRC}/lib,target=${DOCKER_ARMBIAN_TARGET_PATH}/lib"

		# type=volume, without source=, is an anonymous volume -- will be auto cleaned up together with the container;
		# this could also be a type=tmpfs if you had enough ram - but armbian already does this for you.
		"--mount" "type=volume,destination=${DOCKER_ARMBIAN_TARGET_PATH}/.tmp"

		# named volumes for different parts of the cache. so easy for user to drop any of them when needed
		# @TODO: refactor this.
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
		DOCKER_ARGS+=(--device-cgroup-rule='b 7:* rmw')   # allow loop devices (not required)
		DOCKER_ARGS+=(--device-cgroup-rule='b 259:* rmw') # allow loop device partitions
		DOCKER_ARGS+=(-v /dev:/tmp/dev:ro)                # this is an ugly hack, but it is required to get /dev/loopXpY minor number for mknod inside the container, and container itself still uses private /dev internally
		for loop_device_host in /dev/loop*; do            # pass through loop devices from host to container; includes `loop-control`
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
