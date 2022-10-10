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

# initialize logging variables.
logging_init

# initialize the traps
traps_init

#############################################################################################################

declare INITIAL_IMAGE_TAG="armbian.local.only/armbian-build:initial"
declare BASE_IMAGE="${BASE_IMAGE:-"ubuntu:jammy"}"
declare DOCKER_ARMBIAN_TARGET_PATH="${DOCKER_ARMBIAN_TARGET_PATH:-"/armbian_host_mounted"}"

declare -a BASIC_DEPS=(
	"bash" "git"
)

# @TODO: grab git info, add as labels et al to Docker...

display_alert "Creating" "Dockerfile" "info"
cat <<- INITIAL_DOCKERFILE > "${SRC}"/Dockerfile
	FROM ${BASE_IMAGE}
	RUN DEBIAN_FRONTEND=noninteractive apt-get update
	RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${BASIC_DEPS[@]}
	WORKDIR ${DOCKER_ARMBIAN_TARGET_PATH}
	COPY lib ${DOCKER_ARMBIAN_TARGET_PATH}/lib
	COPY config ${DOCKER_ARMBIAN_TARGET_PATH}/config
	COPY extensions ${DOCKER_ARMBIAN_TARGET_PATH}/extensions
	COPY VERSION LICENSE compile.sh ${DOCKER_ARMBIAN_TARGET_PATH}/
	RUN ls -laRht ${DOCKER_ARMBIAN_TARGET_PATH}
	RUN uname -a && cat /etc/os-release
	RUN free -h && df -h && lscpu
	RUN /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" REQUIREMENTS_DEFS_ONLY=yes SHOW_DEBUG=yes SHOW_COMMAND=yes SHOW_LOG=yes
INITIAL_DOCKERFILE

if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
	display_alert "Dockerfile generated" "exiting" "info"
	exit 0
fi

display_alert "Armbian docker launcher" "docker" "info"

display_alert "Building" "Dockerfile" "info"
# @TODO: allow for `--pull`
docker buildx build --progress=plain -t "${INITIAL_IMAGE_TAG}" -f "${SRC}"/Dockerfile "${SRC}"

display_alert "Preparing" "common Docker arguments" "info"
declare -a DOCKER_ARGS=(
	"--privileged"         # Running this container in privileged mode is a simple way to solve loop device access issues, required for USB FEL or when writing image directly to the block device, when CARD_DEVICE is defined
	"--cap-add=SYS_ADMIN"  # add only required capabilities instead
	"--cap-add=MKNOD"      # (though MKNOD should be already present)
	"--cap-add=SYS_PTRACE" # CAP_SYS_PTRACE is required for systemd-detect-virt in some cases @TODO: rpardini: so lets eliminate it

	#"--pull"               # pull the base image, don't use outdated local image

	# "--mount" "type=bind,source=${SRC}/lib,target=${DOCKER_ARMBIAN_TARGET_PATH}/lib"

	# type=volume, without source=, is an anonymous volume -- will be auto cleaned up together with the container;
	# this could also be a type=tmpfs if you had enough ram - but armbian already does this for you.
	"--mount" "type=volume,destination=${DOCKER_ARMBIAN_TARGET_PATH}/.tmp"

	# named volumes for different parts of the cache. so easy for user to drop any of them when needed
	"--mount" "type=volume,source=armbian-cache-parent,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache"
	"--mount" "type=volume,source=armbian-cache-gitballs,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/gitballs"
	"--mount" "type=volume,source=armbian-cache-toolchain,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/toolchain"
	"--mount" "type=volume,source=armbian-cache-rootfs,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/rootfs"
	"--mount" "type=volume,source=armbian-cache-initrd,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/initrd"
	"--mount" "type=volume,source=armbian-cache-sources,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/sources"
	"--mount" "type=volume,source=armbian-cache-sources-linux-kernel,destination=${DOCKER_ARMBIAN_TARGET_PATH}/cache/sources/linux-kernel"
)

# @TODO: auto-compute this list; just get the dirs and filter some out
for MOUNT_DIR in "lib" "config" "extensions" "packages" "patch" "tools" "userpatches" "output"; do
	mkdir -p "${SRC}/${MOUNT_DIR}"
	DOCKER_ARGS+=("--mount" "type=bind,source=${SRC}/${MOUNT_DIR},target=${DOCKER_ARMBIAN_TARGET_PATH}/${MOUNT_DIR}")
done

display_alert "Showing Docker characteristics" "Docker args: '${DOCKER_ARGS[*]}'" "info"
docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash -c "uname -a && cat /etc/os-release"
docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash -c "free -h && df -h && lscpu"
docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash -c "mount"

#display_alert "Running" "CONFIG_DEFS_ONLY=yes phase" "info"
#docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" CONFIG_DEFS_ONLY=yes BRANCH=ddk BOARD=uefi-x86 KERNEL_ONLY=no KERNEL_CONFIGURE=no BUILD_DESKTOP=no RELEASE=jammy BUILD_MINIMAL=no SHOW_DEBUG=yes SHOW_COMMAND=yes SHOW_LOG=yes

#display_alert "Running" "real build!" "info"
#docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" BRANCH=ddk BOARD=uefi-x86 KERNEL_ONLY=no KERNEL_CONFIGURE=no BUILD_DESKTOP=no RELEASE=jammy BUILD_MINIMAL=no SHOW_DEBUG=yes SHOW_COMMAND=yes SHOW_LOG=yes SKIP_ARMBIAN_REPO=yes

display_alert "Running" "real build: ${*}" "info"
docker run -it "${DOCKER_ARGS[@]}" "${INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" "$@"

display_alert "Done!"

display_alert "Showing docker volumes usage" "debug"
docker system df -v | grep -e "^armbian-cache" | grep -v "\b0B" | tr -s " " | cut -d " " -f 1,3

