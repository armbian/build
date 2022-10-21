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
# Usage: if is_docker_ready_to_go; then ...; fi
function is_docker_ready_to_go() {
	# For either Linux or Darwin.
	# Gotta tick all these boxes:
	# 0) NOT ALREADY UNDER DOCKER.
	# 1) can find the `docker` command in the path, via command -v
	# 2) can run `docker info` without errors
	if [[ "$ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		display_alert "Can't use Docker" "Actually ALREADY UNDER DOCKER!" "debug"
		return 1
	fi
	if [[ ! -n "$(command -v docker)" ]]; then
		display_alert "Can't use Docker" "docker command not found" "debug"
		return 1
	fi
	if ! docker info > /dev/null 2>&1; then
		display_alert "Can't use Docker" "docker info failed" "debug"
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

		display_alert "Using prebuilt Armbian image as base for '${wanted_os_tag}-${wanted_release_tag}'" "DOCKER_ARMBIAN_BASE_IMAGE: ${DOCKER_ARMBIAN_BASE_IMAGE}" "info"
	fi

	# @TODO: this might be unified with prepare_basic_deps
	declare -g -a BASIC_DEPS=("bash" "git" "psmisc" "uuid-runtime")

	#############################################################################################################
	# Prepare some dependencies; these will be used on the Dockerfile

	declare -a -g host_dependencies=()
	REQUIREMENTS_DEFS_ONLY=yes early_prepare_host_dependencies
	display_alert "Pre-game dependencies" "${host_dependencies[*]}" "debug"

	#############################################################################################################
	# Detect some docker info.

	DOCKER_SERVER_VERSION="$(docker info | grep -i -e "Server Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server version" "${DOCKER_SERVER_VERSION}" "debug"

	DOCKER_SERVER_KERNEL_VERSION="$(docker info | grep -i -e "Kernel Version\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Kernel version" "${DOCKER_SERVER_KERNEL_VERSION}" "debug"

	DOCKER_SERVER_TOTAL_RAM="$(docker info | grep -i -e "Total memory\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server Total RAM" "${DOCKER_SERVER_TOTAL_RAM}" "debug"

	DOCKER_SERVER_CPUS="$(docker info | grep -i -e "CPUs\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server CPUs" "${DOCKER_SERVER_CPUS}" "debug"

	DOCKER_SERVER_OS="$(docker info | grep -i -e "Operating System\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Server OS" "${DOCKER_SERVER_OS}" "debug"

	declare -g DOCKER_ARMBIAN_HOST_OS_UNAME
	DOCKER_ARMBIAN_HOST_OS_UNAME="$(uname)"
	display_alert "Local uname" "${DOCKER_ARMBIAN_HOST_OS_UNAME}" "debug"

	DOCKER_BUILDX_VERSION="$(docker info | grep -i -e "buildx\:" | cut -d ":" -f 2 | xargs echo -n)"
	display_alert "Docker Buildx version" "${DOCKER_BUILDX_VERSION}" "debug"

	declare -g DOCKER_HAS_BUILDX=no
	declare -g -a DOCKER_BUILDX_OR_BUILD=("build")
	if [[ -n "${DOCKER_BUILDX_VERSION}" ]]; then
		DOCKER_HAS_BUILDX=yes
		DOCKER_BUILDX_OR_BUILD=("buildx" "build" "--progress=plain")
	fi
	display_alert "Docker has buildx?" "${DOCKER_HAS_BUILDX}" "debug"

	DOCKER_SERVER_NAME_HOST="$(docker info | grep -i -e "name\:" | cut -d ":" -f 2 | xargs echo -n)"
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

	display_alert "Creating" "Dockerfile" "info"
	cat <<- INITIAL_DOCKERFILE > "${SRC}"/Dockerfile
		FROM ${DOCKER_ARMBIAN_BASE_IMAGE}
		# PLEASE DO NOT MODIFY THIS FILE. IT IS AUTOGENERATED AND WILL BE OVERWRITTEN. Please don't build this Dockerfile yourself either. Use Armbian helpers instead.
		RUN echo "--> CACHE MISS IN DOCKERFILE: apt packages." && \
			DEBIAN_FRONTEND=noninteractive apt-get -y update && \
			DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${BASIC_DEPS[@]} ${host_dependencies[@]}
		WORKDIR ${DOCKER_ARMBIAN_TARGET_PATH}
		ENV ARMBIAN_RUNNING_IN_CONTAINER=yes
		ADD . ${DOCKER_ARMBIAN_TARGET_PATH}/
		RUN echo "--> CACHE MISS IN DOCKERFILE: running Armbian requirements initialization." && \
			/bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" requirements SHOW_LOG=yes && \
			rm -rf "${DOCKER_ARMBIAN_TARGET_PATH}/output" "${DOCKER_ARMBIAN_TARGET_PATH}/.tmp" "${DOCKER_ARMBIAN_TARGET_PATH}/cache" 
	INITIAL_DOCKERFILE

}
function docker_cli_build_dockerfile() {
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

	display_alert "Preparing" "common Docker arguments" "debug"
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
	# 20/Oct/2022: trying with Rancher Desktop in dockerd mode on Mac M1, this is required; also loops have to be hardcoded.
	# How to detect this? It's Darwin, but not "real" Docker. How to find out?
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

}

function docker_cli_launch() {
	display_alert "Showing Docker cmdline" "Docker args: '${DOCKER_ARGS[*]}'" "debug"

	display_alert "Relaunching in Docker" "${*}" "debug"
	display_alert "Relaunching in Docker" "here comes the 🐳" "info"
	local -i docker_build_result=1
	if docker run -it "${DOCKER_ARGS[@]}" "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" /bin/bash "${DOCKER_ARMBIAN_TARGET_PATH}/compile.sh" "$@"; then
		display_alert "Docker Build finished" "successfully" "info"
		docker_build_result=0
	else
		display_alert "Docker Build failed" "with errors" "err"
	fi

	# Find and show the path to the log file for the ARMBIAN_BUILD_UUID.
	local logs_path="${DEST}/logs" log_file
	log_file="$(find "${logs_path}" -type f -name "*${ARMBIAN_BUILD_UUID}*.*" -print -quit)"
	display_alert "Build log done inside Docker" "${log_file}" "info"

	# Show and help user understand space usage in Docker volumes.
	# This is done in a loop; `docker df` fails sometimes (for no good reason).
	docker_cli_show_armbian_volumes_disk_usage

	return ${docker_build_result}
}

function docker_cli_show_armbian_volumes_disk_usage() {
	display_alert "Gathering docker volumes disk usage" "docker system df, wait..." "debug"
	sleep_seconds="1" silent_retry="yes" do_with_retries 5 docker_cli_show_armbian_volumes_disk_usage_internal || {
		display_alert "Could not get Docker volumes disk usage" "docker failed to report disk usage" "warn"
		return 0 # not really a problem, just move on.
	}
	local docker_volume_usage
	docker_volume_usage="$(docker system df -v | grep -e "^armbian-cache" | grep -v "\b0B" | tr -s " " | cut -d " " -f 1,3 | tr " " ":" | xargs echo || true)"
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

# Leftovers from original Dockerfile before rewrite
## OLD DOCKERFILE ## RUN locale-gen en_US.UTF-8
## OLD DOCKERFILE ##
## OLD DOCKERFILE ## # Static port for NFSv3 server used for USB FEL boot
## OLD DOCKERFILE ## RUN sed -i 's/\(^STATDOPTS=\).*/\1"--port 32765 --outgoing-port 32766"/' /etc/default/nfs-common \
## OLD DOCKERFILE ##     && sed -i 's/\(^RPCMOUNTDOPTS=\).*/\1"--port 32767"/' /etc/default/nfs-kernel-server
## OLD DOCKERFILE ##
## OLD DOCKERFILE ## ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TERM=screen
## OLD DOCKERFILE ## WORKDIR /root/armbian
## OLD DOCKERFILE ## LABEL org.opencontainers.image.source="https://github.com/armbian/build/blob/master/config/templates/Dockerfile" \
## OLD DOCKERFILE ##     org.opencontainers.image.url="https://github.com/armbian/build/pkgs/container/build"  \
## OLD DOCKERFILE ##     org.opencontainers.image.vendor="armbian" \
## OLD DOCKERFILE ##     org.opencontainers.image.title="Armbian build framework" \
## OLD DOCKERFILE ##     org.opencontainers.image.description="Custom Linux build framework" \
## OLD DOCKERFILE ##     org.opencontainers.image.documentation="https://docs.armbian.com" \
## OLD DOCKERFILE ##     org.opencontainers.image.authors="Igor Pecovnik" \
## OLD DOCKERFILE ##     org.opencontainers.image.licenses="GPL-2.0"
## OLD DOCKERFILE ## ENTRYPOINT [ "/bin/bash", "/root/armbian/compile.sh" ]
