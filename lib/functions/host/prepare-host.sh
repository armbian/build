#!/usr/bin/env bash
# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host() {
	display_alert "Preparing" "host" "info"

	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	# wait until package manager finishes possible system maintanace
	wait_for_package_manager

	# fix for Locales settings, if locale-gen is installed, and /etc/locale.gen exists.
	if [[ -n "$(command -v locale-gen)" && -f /etc/locale.gen ]]; then
		if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
			local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
			${sudo_prefix} sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
			${sudo_prefix} locale-gen
		fi
	else
		display_alert "locale-gen is not installed @host" "skipping locale-gen -- problems might arise" "warn"
	fi

	export LC_ALL="en_US.UTF-8"

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

	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		:
	elif [[ $(dpkg --print-architecture) == arm64 ]]; then
		:
	else
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "https://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on non x86_64 or arm64 build host is not supported"
	fi

	display_alert "Build host OS release" "${HOSTRELEASE:-(unknown)}" "info"

	# Ubuntu 21.04.x (Hirsute) x86_64 is the only fully supported host OS release
	# Using Docker/VirtualBox/Vagrant is the only supported way to run the build script on other Linux distributions
	#
	# NO_HOST_RELEASE_CHECK overrides the check for a supported host system
	# Disable host OS check at your own risk. Any issues reported with unsupported releases will be closed without discussion
	if [[ -z $HOSTRELEASE || "buster bullseye bookworm focal impish hirsute jammy lunar kinetic debbie tricia ulyana ulyssa uma una vanessa vera" != *"$HOSTRELEASE"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${HOSTRELEASE:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "It seems you ignore documentation and run an unsupported build system: ${HOSTRELEASE:-(unknown)}"
		fi
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		if [ -f /.dockerenv ]; then
			display_alert "Building images using Docker on WSL2 may fail" "" "wrn"
		else
			exit_with_error "Windows subsystem for Linux is not a supported build environment"
		fi
	fi

	declare -g USE_LOCAL_APT_DEB_CACHE=${USE_LOCAL_APT_DEB_CACHE:-yes} # Use SRC/cache/aptcache as local apt cache by default
	display_alert "Using local apt cache?" "USE_LOCAL_APT_DEB_CACHE: ${USE_LOCAL_APT_DEB_CACHE}" "debug"

	if armbian_is_running_in_container; then
		display_alert "Running in container" "Adding provisions for container building" "info"
		declare -g CONTAINER_COMPAT=yes # this controls mknod usage for loop devices.
		declare -g NO_APT_CACHER=yes # disable apt-cacher; we use local cache in Docker volumes.
		
		# trying to use nested containers is not a good idea, so don't permit EXTERNAL_NEW=compile
		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi
		
		SYNC_CLOCK=no
	else
		display_alert "NOT running in container" "No special provisions for container building" "debug"
	fi

	# Skip verification if you are working offline
	if ! $offline; then
		install_host_dependencies "dependencies during prepare_release"

		# Manage apt-cacher-ng
		acng_configure_and_restart_acng

		# sync clock
		if [[ $SYNC_CLOCK != no ]]; then
			display_alert "Syncing clock" "host" "info"
			run_host_command_logged ntpdate "${NTP_SERVER:-pool.ntp.org}"
		fi

		# create directory structure # @TODO: this should be close to DEST, otherwise super-confusing
		mkdir -p "${SRC}"/{cache,output} "${USERPATCHES_PATH}"

		# @TODO: original: mkdir -p "${DEST}"/debs-beta/extra "${DEST}"/debs/extra "${DEST}"/{config,debug,patch} "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp
		mkdir -p "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp

		# Mostly deprecated.
		download_external_toolchains

	fi # check offline

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
		fi
	fi

	# @TODO: rpardini: this does not belong here, instead with the other templates, pre-configuration.
	[[ ! -f "${USERPATCHES_PATH}"/customize-image.sh ]] && run_host_command_logged cp -pv "${SRC}"/config/templates/customize-image.sh.template "${USERPATCHES_PATH}"/customize-image.sh

	# @TODO: what is this, and why?
	if [[ ! -f "${USERPATCHES_PATH}"/README ]]; then
		rm -f "${USERPATCHES_PATH}"/readme.txt
		echo 'Please read documentation about customizing build configuration' > "${USERPATCHES_PATH}"/README
		echo 'https://www.armbian.com/using-armbian-tools/' >> "${USERPATCHES_PATH}"/README

		# create patches directory structure under USERPATCHES_PATH
		find "${SRC}"/patch -maxdepth 2 -type d ! -name . | sed "s%/.*patch%/$USERPATCHES_PATH%" | xargs mkdir -p
	fi

	# Reset owner of userpatches if so required
	reset_uid_owner "${USERPATCHES_PATH}" # Fix owner of files in the final destination

	# @TODO: check every possible mount point. Not only one. People might have different mounts / Docker volumes...
	# check free space (basic) @TODO probably useful to refactor and implement in multiple spots.
	declare -i free_space_bytes
	free_space_bytes=$(findmnt --noheadings --output AVAIL --bytes --target "${SRC}" --uniq 2> /dev/null) # in bytes
	if [[ -n "$free_space_bytes" && $((free_space_bytes / 1073741824)) -lt 10 ]]; then
		display_alert "Low free space left" "$((free_space_bytes / 1073741824)) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read # @TODO: this fails if stdin is not a tty, or just hangs
	fi
}

function early_prepare_host_dependencies() {
	# packages list for host
	# NOTE: please sync any changes here with the Dockerfile and Vagrantfile
	declare -a -g host_dependencies=(
		# big bag of stuff from before
		acl aptly bc binfmt-support bison btrfs-progs
		build-essential ca-certificates ccache cpio cryptsetup
		debian-archive-keyring debian-keyring debootstrap device-tree-compiler
		dialog dirmngr dosfstools dwarves f2fs-tools fakeroot flex gawk
		gnupg gpg imagemagick jq kmod libbison-dev
		libelf-dev libfdt-dev libfile-fcntllock-perl libmpc-dev
		libfl-dev liblz4-tool libncurses-dev libssl-dev
		libusb-1.0-0-dev linux-base locales ncurses-base ncurses-term
		ntpdate patchutils
		pkg-config pv qemu-user-static rsync swig
		u-boot-tools udev uuid-dev whiptail
		zlib1g-dev busybox fdisk

		# distcc, experimental, optional; see cli-distcc.sh and kernel.sh
		distcc

		# python3 stuff (eg, for modern u-boot)
		python3-dev python3-distutils python3-setuptools
		# python3 pip (for Armbian's Python utilities) @TODO virtualenv?
		python3-pip

		# python2, including headers, mostly used by some u-boot builds (2017 et al, odroidxu4 and others).
		python2 python2-dev
		# Attention: 'python-setuptools' (Python2's setuptools) does not exist in Debian Sid. Use Python3 instead.

		# systemd-container brings in systemd-nspawn, which is used by the buildpkg functionality
		# systemd-container # @TODO: bring this back eventually. I don't think trying to use those inside a container is a good idea.

		# non-mess below?
		file ccze colorized-logs tree expect            # logging utilities; expect is needed for 'unbuffer' command
		unzip zip p7zip-full pigz pixz pbzip2 lzop zstd # compressors et al
		parted gdisk                                    # partition tools
		aria2 curl wget axel                            # downloaders et al
		parallel                                        # do things in parallel
		# toolchains. NEW: using metapackages, allow us to have same list of all arches; brings both C and C++ compilers
		crossbuild-essential-armhf crossbuild-essential-armel # for ARM 32-bit, both HF and EL are needed in some cases.
		crossbuild-essential-arm64                            # For ARM 64-bit, arm64.
		crossbuild-essential-amd64                            # For AMD 64-bit, x86_64.
		gcc-riscv64-linux-gnu                                 # For RISC-V 64-bit, riscv64; crossbuild-essential-riscv64 is not available.
		libc6-amd64-cross                                     # Support for running x86 binaries (under qemu on other arches)
	)

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then
		host_dependencies+=("apt-cacher-ng")
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
	display_alert "Installing build dependencies"
	display_alert "Installing build dependencies" "$*" "debug"

	# don't prompt for apt cacher selection. this is to skip the prompt only, since we'll manage acng config later.
	local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
	${sudo_prefix} echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | ${sudo_prefix} debconf-set-selections

	# This handles the wanted list in $host_dependencies, updates apt only if needed
	# $host_dependencies is produced by early_prepare_host_dependencies()
	install_host_side_packages "${host_dependencies[@]}"

	run_host_command_logged update-ccache-symlinks

	export FINAL_HOST_DEPS="${host_dependencies[*]}"

	call_extension_method "host_dependencies_ready" <<- 'HOST_DEPENDENCIES_READY'
		*run after all host dependencies are installed*
		At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
		All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
		are installed at this point. The system clock has not yet been synced.
	HOST_DEPENDENCIES_READY
}
