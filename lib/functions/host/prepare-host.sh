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

	# fix for Locales settings
	if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
		sudo sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		sudo locale-gen
	fi

	export LC_ALL="en_US.UTF-8"

	# packages list for host
	# NOTE: please sync any changes here with the Dockerfile and Vagrantfile
	declare -a host_dependencies=(
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
		pkg-config pv python3-dev python3-distutils qemu-user-static rsync swig
		systemd-container u-boot-tools udev uuid-dev whiptail
		zlib1g-dev busybox

		# python2, including headers, mostly used by some u-boot builds (2017 et al, odroidxu4 and others).
		python2 python2-dev

		# non-mess below?
		file ccze colorized-logs tree                   # logging utilities
		unzip zip p7zip-full pigz pixz pbzip2 lzop zstd # compressors et al
		parted gdisk                                    # partition tools
		aria2 curl wget                                 # downloaders et al
		parallel                                        # do things in parallel
		# toolchains. NEW: using metapackages, allow us to have same list of all arches; brings both C and C++ compilers
		crossbuild-essential-armhf crossbuild-essential-armel # for ARM 32-bit, both HF and EL are needed in some cases.
		crossbuild-essential-arm64                            # For ARM 64-bit, arm64.
		crossbuild-essential-amd64                            # For AMD 64-bit, x86_64.
	)

	if [[ $(dpkg --print-architecture) == amd64 ]]; then
		:
	elif [[ $(dpkg --print-architecture) == arm64 ]]; then
		host_dependencies+=(libc6-amd64-cross qemu) # Support for running x86 binaries on ARM64 under qemu.
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
	if [[ -z $HOSTRELEASE || "buster bullseye focal impish hirsute jammy debbie tricia ulyana ulyssa uma una" != *"$HOSTRELEASE"* ]]; then
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

	if systemd-detect-virt -q -c; then
		display_alert "Running in container" "$(systemd-detect-virt)" "info"
		# disable apt-cacher unless NO_APT_CACHER=no is not specified explicitly
		if [[ $NO_APT_CACHER != no ]]; then
			display_alert "apt-cacher is disabled in containers, set NO_APT_CACHER=no to override" "" "wrn"
			NO_APT_CACHER=yes
		fi
		CONTAINER_COMPAT=yes
		# trying to use nested containers is not a good idea, so don't permit EXTERNAL_NEW=compile
		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi
		SYNC_CLOCK=no
	fi

	# Skip verification if you are working offline
	if ! $offline; then

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

		display_alert "Installing build dependencies"

		# don't prompt for apt cacher selection. this is to skip the prompt only, since we'll manage acng config later.
		sudo echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | sudo debconf-set-selections

		# This handles the wanted list in $host_dependencies, updates apt only if needed
		install_host_side_packages "${host_dependencies[@]}"

		run_host_command_logged update-ccache-symlinks

		export FINAL_HOST_DEPS="${host_dependencies[*]}"
		call_extension_method "host_dependencies_ready" <<- 'HOST_DEPENDENCIES_READY'
			*run after all host dependencies are installed*
			At this point we can read `${FINAL_HOST_DEPS}`, but changing won't have any effect.
			All the dependencies, including the default/core deps and the ones added via `${EXTRA_BUILD_DEPS}`
			are installed at this point. The system clock has not yet been synced.
		HOST_DEPENDENCIES_READY

		# Manage apt-cacher-ng
		acng_configure_and_restart_acng

		# sync clock
		if [[ $SYNC_CLOCK != no ]]; then
			display_alert "Syncing clock" "host" "info"
			run_host_command_logged ntpdate "${NTP_SERVER:-pool.ntp.org}"
		fi

		# create directory structure # @TODO: this should be close to DEST, otherwise super-confusing
		mkdir -p "${SRC}"/{cache,output} "${USERPATCHES_PATH}"
		if [[ -n $SUDO_USER ]]; then
			chgrp --quiet sudo cache output "${USERPATCHES_PATH}"
			# SGID bit on cache/sources breaks kernel dpkg packaging
			chmod --quiet g+w,g+s output "${USERPATCHES_PATH}"
			# fix existing permissions
			find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -group sudo -exec chgrp --quiet sudo {} \;
			find "${SRC}"/output "${USERPATCHES_PATH}" -type d ! -perm -g+w,g+s -exec chmod --quiet g+w,g+s {} \;
		fi
		# @TODO: original: mkdir -p "${DEST}"/debs-beta/extra "${DEST}"/debs/extra "${DEST}"/{config,debug,patch} "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp
		mkdir -p "${USERPATCHES_PATH}"/overlay "${SRC}"/cache/{sources,hash,hash-beta,toolchain,utility,rootfs} "${SRC}"/.tmp

		# Mostly deprecated.
		download_external_toolchains

	fi # check offline

	# enable arm binary format so that the cross-architecture chroot environment will work
	if [[ $KERNEL_ONLY != yes ]]; then
		modprobe -q binfmt_misc || display_alert "Failed to modprobe" "binfmt_misc" "warn"
		mountpoint -q /proc/sys/fs/binfmt_misc/ || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
		if [[ "$(arch)" != "aarch64" ]]; then
			test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
			test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
		fi
	fi

	[[ ! -f "${USERPATCHES_PATH}"/customize-image.sh ]] && run_host_command_logged cp -pv "${SRC}"/config/templates/customize-image.sh.template "${USERPATCHES_PATH}"/customize-image.sh

	# @TODO: what is this, and why?
	if [[ ! -f "${USERPATCHES_PATH}"/README ]]; then
		rm -f "${USERPATCHES_PATH}"/readme.txt
		echo 'Please read documentation about customizing build configuration' > "${USERPATCHES_PATH}"/README
		echo 'https://www.armbian.com/using-armbian-tools/' >> "${USERPATCHES_PATH}"/README

		# create patches directory structure under USERPATCHES_PATH
		find "${SRC}"/patch -maxdepth 2 -type d ! -name . | sed "s%/.*patch%/$USERPATCHES_PATH%" | xargs mkdir -p
	fi

	# check free space (basic) @TODO probably useful to refactor and implement in multiple spots.
	local free_space_bytes
	free_space_bytes=$(findmnt --target "${SRC}" -n -o AVAIL -b 2> /dev/null) # in bytes
	if [[ -n $free_space_bytes && $((free_space_bytes / 1073741824)) -lt 10 ]]; then
		display_alert "Low free space left" "$((free_space_bytes / 1073741824)) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read # @TODO: this fails if stdin is not a tty, or just hangs
	fi
}
