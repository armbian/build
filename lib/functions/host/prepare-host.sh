#!/usr/bin/env bash
# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
function prepare_host() {
	# Now, if NOT interactive, do some basic checks. If interactive, those have already run back in prepare_and_config_main_build_single()
	if [[ ! -t 1 ]]; then
		LOG_SECTION="ni_check_basic_host" do_with_logging check_basic_host
	fi

	LOG_SECTION="prepare_host_noninteractive" do_with_logging prepare_host_noninteractive
	return 0
}

function check_basic_host() {
	display_alert "Checking" "basic host setup" "info"
	obtain_and_check_host_release_and_arch # sets HOSTRELEASE and validates it for sanity; also HOSTARCH
	check_host_has_enough_disk_space       # Checks disk space and exits if not enough
	check_windows_wsl2                     # checks if on Windows, on WSL2, (not 1) and exits if not supported
	wait_for_package_manager               # wait until dpkg is not locked...
}

function prepare_host_noninteractive() {
	display_alert "Preparing" "host" "info"

	# The 'offline' variable must always be set to 'true' or 'false'
	declare offline=false
	if [ "$OFFLINE_WORK" == "yes" ]; then
		offline=true
	fi

	# fix for Locales settings, if locale-gen is installed, and /etc/locale.gen exists.
	if [[ -n "$(command -v locale-gen)" && -f /etc/locale.gen ]]; then
		if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
			# @TODO: rpardini: this is bull, we're always root here. we've been pre-sudo'd.
			local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
			${sudo_prefix} sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
			${sudo_prefix} locale-gen
		fi
	else
		display_alert "locale-gen is not installed @host" "skipping locale-gen -- problems might arise" "warn"
	fi

	# Let's try and get all log output in English, overriding the builder's chosen or default language
	export LANG="en_US.UTF-8"
	export LANGUAGE="en_US.UTF-8"
	export LC_ALL="en_US.UTF-8"
	export LC_MESSAGES="en_US.UTF-8"

	# armbian-next: Armbian mirrors and the download code is highly unstable; disable by default
	# armbian-next: set `SKIP_ARMBIAN_ROOTFS_CACHE=no` to enable
	# don't use mirrors that throws garbage on 404
	if [[ -z ${ARMBIAN_MIRROR} && "${SKIP_ARMBIAN_REPO}" != "yes" && "${SKIP_ARMBIAN_ROOTFS_CACHE:-"yes"}" != "yes" ]]; then
		display_alert "Determining best Armbian mirror to use" "via redirector" "debug"
		declare -i armbian_mirror_tries=1
		while true; do
			display_alert "Obtaining Armbian mirror" "via https://redirect.armbian.com" "debug"
			ARMBIAN_MIRROR=$(wget -SO- -T 1 -t 1 https://redirect.armbian.com 2>&1 | egrep -i "Location" | awk '{print $2}' | head -1)
			if [[ ${ARMBIAN_MIRROR} != *armbian.hosthatch* ]]; then # @TODO: hosthatch is not good enough. Why?
				display_alert "Obtained Armbian mirror OK" "${ARMBIAN_MIRROR}" "debug"
				break
			else
				display_alert "Obtained Armbian mirror is invalid, retrying..." "${ARMBIAN_MIRROR}" "debug"
			fi
			armbian_mirror_tries=$((armbian_mirror_tries + 1))
			if [[ $armbian_mirror_tries -ge 5 ]]; then
				exit_with_error "Unable to obtain ARMBIAN_MIRROR after ${armbian_mirror_tries} tries. Please set ARMBIAN_MIRROR to a valid mirror manually, or avoid the automatic mirror selection by setting SKIP_ARMBIAN_REPO=yes"
			fi
		done
	fi

	declare -g USE_LOCAL_APT_DEB_CACHE=${USE_LOCAL_APT_DEB_CACHE:-yes} # Use SRC/cache/aptcache as local apt cache by default
	display_alert "Using local apt cache?" "USE_LOCAL_APT_DEB_CACHE: ${USE_LOCAL_APT_DEB_CACHE}" "debug"

	if armbian_is_running_in_container; then
		display_alert "Running in container" "Adding provisions for container building" "info"
		declare -g CONTAINER_COMPAT=yes # this controls mknod usage for loop devices.

		if [[ "${MANAGE_ACNG}" == "yes" ]]; then
			display_alert "Running in container" "Disabling ACNG - MANAGE_ACNG=yes not supported in containers" "warn"
			declare -g MANAGE_ACNG=no
		fi

		# trying to use nested containers is not a good idea, so don't permit EXTERNAL_NEW=compile
		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi

		SYNC_CLOCK=no
	else
		display_alert "NOT running in container" "No special provisions for container building" "debug"
	fi

	# If offline, do not try to install dependencies, manage acng, or sync the clock.
	if ! $offline; then
		# Prepare the list of host dependencies; it requires the target arch, the host release and arch
		late_prepare_host_dependencies
		install_host_dependencies "late dependencies during prepare_release"

		# Manage apt-cacher-ng
		acng_configure_and_restart_acng

		# sync clock
		if [[ $SYNC_CLOCK != no && -f /var/run/ntpd.pid ]]; then
			display_alert "ntpd is running, skipping" "SYNC_CLOCK=no" "debug"
			SYNC_CLOCK=no
		fi

		if [[ $SYNC_CLOCK != no ]]; then
			display_alert "Syncing clock" "host" "info"
			run_host_command_logged ntpdate "${NTP_SERVER:-pool.ntp.org}" || true # allow failures
		fi
	fi

	# create directory structure # @TODO: this should be close to DEST, otherwise super-confusing
	mkdir -p "${SRC}"/{cache,output} "${USERPATCHES_PATH}"

	# @TODO: original: mkdir -p "${DEST}"/debs-beta/extra "${DEST}"/debs/extra "${DEST}"/{config,debug,patch} "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp
	mkdir -p "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,rootfs} "${SRC}"/.tmp

	# If offline, do not try to download/install toolchains.
	if ! $offline; then
		download_external_toolchains # Mostly deprecated, since SKIP_EXTERNAL_TOOLCHAINS=yes is the default
	fi

	# if we're building an image, not only packages...
	# ... and the host arch does not match the target arch ...
	# ... we then require binfmt_misc to be enabled.
	# "enable arm binary format so that the cross-architecture chroot environment will work"
	if [[ $KERNEL_ONLY != yes ]]; then
		if dpkg-architecture -e "${ARCH}"; then
			display_alert "Native arch build" "target ${ARCH} on host $(dpkg --print-architecture)" "cachehit"
		else
			local failed_binfmt_modprobe=0

			display_alert "Cross arch build" "target ${ARCH} on host $(dpkg --print-architecture)" "debug"

			# Check if binfmt_misc is loaded; if not, try to load it, but don't fail: it might be built in.
			if grep -q "^binfmt_misc" /proc/modules; then
				display_alert "binfmt_misc is already loaded" "binfmt_misc already loaded" "debug"
			else
				display_alert "binfmt_misc is not loaded" "trying to load binfmt_misc" "debug"

				# try to modprobe. if it fails, emit a warning later, but not here.
				# this is for the in-container case, where the host already has the module, but won't let the container know about it.
				modprobe -q binfmt_misc || failed_binfmt_modprobe=1
			fi

			# Now, /proc/sys/fs/binfmt_misc/ has to be mounted. Mount, or fail with a message
			if mountpoint -q /proc/sys/fs/binfmt_misc/; then
				display_alert "binfmt_misc is already mounted" "binfmt_misc already mounted" "debug"
			else
				display_alert "binfmt_misc is not mounted" "trying to mount binfmt_misc" "debug"
				mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc/ || {
					if [[ $failed_binfmt_modprobe == 1 ]]; then
						display_alert "Failed to load binfmt_misc module" "modprobe binfmt_misc failed" "wrn"
					fi
					display_alert "Check your HOST kernel" "CONFIG_BINFMT_MISC=m is required in host kernel" "warn"
					display_alert "Failed to mount" "binfmt_misc /proc/sys/fs/binfmt_misc/" "err"
					exit_with_error "Failed to mount binfmt_misc"
				}
				display_alert "binfmt_misc mounted" "binfmt_misc mounted" "debug"
			fi

			# @TODO: rpardini: Hmm, this is from long ago. Why? Is it needed? Why not for aarch64?
			if [[ "$(arch)" != "aarch64" ]]; then
				test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
				test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
			fi

			# @TODO: we could create a tiny loop here to test if the binfmt_misc is working, but this is before deps are installed.
		fi
	fi

	# @TODO: rpardini: this does not belong here, instead with the other templates, pre-configuration.
	[[ ! -f "${USERPATCHES_PATH}"/customize-image.sh ]] && run_host_command_logged cp -pv "${SRC}"/config/templates/customize-image.sh.template "${USERPATCHES_PATH}"/customize-image.sh

	if [[ -d "${USERPATCHES_PATH}" ]]; then
		# create patches directory structure under USERPATCHES_PATH
		find "${SRC}"/patch -maxdepth 2 -type d ! -name . | sed "s%/.*patch%/$USERPATCHES_PATH%" | xargs mkdir -p
	fi

	# Reset owner of userpatches if so required
	reset_uid_owner "${USERPATCHES_PATH}" # Fix owner of files in the final destination

	return 0
}

# Early: we've possibly no idea what the host release or arch we're building on, or what the target arch is. All-deps.
# Early: we've a best-guess indication of the host release, but not target. (eg: Dockerfile generate)
# Early: we're certain about the host release and arch, but not anything about the target (eg: docker build of the Dockerfile, cli-requirements)
# Late: we know everything; produce a list that is optimized for the host+target we're building. (eg: Oleg)
function early_prepare_host_dependencies() {
	if [[ "x${host_release:-}x" == "xx" ]]; then
		display_alert "Host release unknown" "host_release not set on call to early_prepare_host_dependencies" "warn"
	fi
	if [[ "x${host_arch:-}x" == "xx" ]]; then
		display_alert "Host arch unknown" "host_arch not set on call to early_prepare_host_dependencies" "debug"
	fi
	adaptative_prepare_host_dependencies
}

function late_prepare_host_dependencies() {
	[[ -z "${ARCH}" ]] && exit_with_error "ARCH is not set"
	[[ -z "${RELEASE}" ]] && exit_with_error "RELEASE is not set"
	[[ -z "${HOSTRELEASE}" ]] && exit_with_error "HOSTRELEASE is not set"
	[[ -z "${HOSTARCH}" ]] && exit_with_error "HOSTARCH is not set"

	target_arch="${ARCH}" host_release="${HOSTRELEASE}" \
		host_arch="${HOSTARCH}" target_release="${RELEASE}" \
		early_prepare_host_dependencies
}

# Adaptive: used by both early & late.
function adaptative_prepare_host_dependencies() {
	if [[ "x${host_release:-"unknown"}x" == "xx" ]]; then
		display_alert "No specified host_release" "preparing for all-hosts, all-targets deps" "debug"
	else
		display_alert "Using passed-in host_release" "${host_release}" "debug"
	fi

	if [[ "x${target_arch:-"unknown"}x" == "xx" ]]; then
		display_alert "No specified target_arch" "preparing for all-hosts, all-targets deps" "debug"
	else
		display_alert "Using passed-in target_arch" "${target_arch}" "debug"
	fi

	#### Common: for all releases, all host arches, and all target arches.
	declare -a -g host_dependencies=(
		# big bag of stuff from before
		bc binfmt-support
		bison
		libc6-dev make dpkg-dev gcc # build-essential, without g++
		ca-certificates ccache cpio
		debootstrap device-tree-compiler dialog dirmngr dosfstools
		dwarves # dwarves has been replaced by "pahole" and is now a transitional package
		fakeroot flex
		gawk gnupg gpg
		imagemagick # required for boot_logo, plymouth: converting images / spinners
		jq          # required for parsing JSON, specially rootfs-caching related.
		kmod        # this causes initramfs rebuild, but is usually pre-installed, so no harm done unless it's an upgrade
		libbison-dev libelf-dev libfdt-dev libfile-fcntllock-perl libmpc-dev libfl-dev liblz4-tool
		libncurses-dev libssl-dev libusb-1.0-0-dev
		linux-base locales
		ncurses-base ncurses-term # for `make menuconfig`
		ntpdate
		patchutils pkg-config pv
		qemu-user-static
		rsync
		swig # swig is needed for some u-boot's. example: "bananapi.conf"
		u-boot-tools
		udev # causes initramfs rebuild, but is usually pre-installed.
		uuid-dev
		zlib1g-dev

		# by-category below
		file tree expect                                # logging utilities; expect is needed for 'unbuffer' command
		unzip zip p7zip-full pigz pixz pbzip2 lzop zstd # compressors et al
		parted gdisk fdisk                              # partition tools @TODO why so many?
		aria2 curl wget axel                            # downloaders et al
		parallel                                        # do things in parallel (used for fast md5 hashing in initrd cache)
	)

	# @TODO: distcc -- handle in extension?

	### Python
	host_deps_add_extra_python # See python-tools.sh::host_deps_add_extra_python()

	# Python3 -- required for Armbian's Python tooling, and also for more recent u-boot builds. Needs 3.9+
	host_dependencies+=("python3-dev" "python3-distutils" "python3-setuptools" "python3-pip")

	# Python2 -- required for some older u-boot builds
	# Debian 'sid' does not carry python2 anymore; in this case some u-boot's might fail to build.
	if [[ "sid bookworm" == *"${host_release}"* ]]; then
		display_alert "Python2 not available on host release '${host_release}'" "old(er) u-boot builds might/will fail" "wrn"
	else
		host_dependencies+=("python2" "python2-dev")
	fi

	# Only install acng if asked to.
	if [[ "${MANAGE_ACNG}" == "yes" ]]; then
		host_dependencies+=("apt-cacher-ng")
	fi

	### ARCH
	declare wanted_arch="${target_arch:-"all"}"

	if [[ "${wanted_arch}" == "amd64" || "${wanted_arch}" == "all" ]]; then
		host_dependencies+=("gcc-x86-64-linux-gnu") # from crossbuild-essential-amd64
	fi

	if [[ "${wanted_arch}" == "arm64" || "${wanted_arch}" == "all" ]]; then
		host_dependencies+=("gcc-aarch64-linux-gnu") # from crossbuild-essential-arm64
	fi

	if [[ "${wanted_arch}" == "armhf" || "${wanted_arch}" == "all" ]]; then
		host_dependencies+=("gcc-arm-linux-gnueabihf" "gcc-arm-linux-gnueabi") # from crossbuild-essential-armhf crossbuild-essential-armel
	fi

	if [[ "${wanted_arch}" == "riscv64" || "${wanted_arch}" == "all" ]]; then
		host_dependencies+=("gcc-riscv64-linux-gnu") # crossbuild-essential-riscv64 is not even available "yet"
	fi

	if [[ "${wanted_arch}" != "amd64" ]]; then
		host_dependencies+=(libc6-amd64-cross) # Support for running x86 binaries (under qemu on other arches)
	fi

	export EXTRA_BUILD_DEPS=""
	call_extension_method "add_host_dependencies" <<- 'ADD_HOST_DEPENDENCIES'
		*run before installing host dependencies*
		you can add packages to install, space separated, to ${EXTRA_BUILD_DEPS} here.
	ADD_HOST_DEPENDENCIES

	if [ -n "${EXTRA_BUILD_DEPS}" ]; then
		# shellcheck disable=SC2206 # I wanna expand. @TODO: later will convert to proper array
		host_dependencies+=(${EXTRA_BUILD_DEPS})
	fi

	export FINAL_HOST_DEPS="${host_dependencies[*]}"
	call_extension_method "host_dependencies_known" <<- 'HOST_DEPENDENCIES_KNOWN'
		*run after all host dependencies are known (but not installed)*
		At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
		All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
		are determined at this point, but not yet installed.
	HOST_DEPENDENCIES_KNOWN
}

function install_host_dependencies() {
	display_alert "Installing build dependencies" "$*" "debug"

	# don't prompt for apt cacher selection. this is to skip the prompt only, since we'll manage acng config later.
	local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
	${sudo_prefix} echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | ${sudo_prefix} debconf-set-selections

	# This handles the wanted list in $host_dependencies, updates apt only if needed
	# $host_dependencies is produced by early_prepare_host_dependencies()
	install_host_side_packages "${host_dependencies[@]}"

	run_host_command_logged update-ccache-symlinks

	declare -g FINAL_HOST_DEPS="${host_dependencies[*]}"

	call_extension_method "host_dependencies_ready" <<- 'HOST_DEPENDENCIES_READY'
		*run after all host dependencies are installed*
		At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
		All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
		are installed at this point. The system clock has not yet been synced.
	HOST_DEPENDENCIES_READY

	unset FINAL_HOST_DEPS # don't leak this after the hook is done
}

function check_host_has_enough_disk_space() {
	# @TODO: check every possible mount point. Not only one. People might have different mounts / Docker volumes...
	# check free space (basic) @TODO probably useful to refactor and implement in multiple spots.
	declare -i free_space_bytes
	free_space_bytes=$(findmnt --noheadings --output AVAIL --bytes --target "${SRC}" --uniq 2> /dev/null) # in bytes
	if [[ -n "$free_space_bytes" && $((free_space_bytes / 1073741824)) -lt 10 ]]; then
		display_alert "Low free space left" "$((free_space_bytes / 1073741824))GiB" "wrn"
		exit_if_countdown_not_aborted 10 "Low free disk space left" # This pauses & exits if error if ENTER is not pressed in 10 seconds
	fi
}
