#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

### Attention: we can't use any interactive programs, read from stdin, nor use non-coreutils utilities here.

function do_main_configuration() {
	display_alert "Starting main configuration" "${MOUNT_UUID}" "info"

	# Obsolete stuff, make sure not defined, then make readonly
	declare -g -r DEBOOTSTRAP_LIST
	declare -g -r PACKAGE_LIST
	declare -g -r PACKAGE_LIST_BOARD
	declare -g -r PACKAGE_LIST_ADDITIONAL
	declare -g -r PACKAGE_LIST_EXTERNAL
	declare -g -r PACKAGE_LIST_DESKTOP

	# common options
	# daily beta build contains date in subrevision
	#if [[ $BETA == yes && -z $SUBREVISION ]]; then SUBREVISION="."$(date --date="tomorrow" +"%j"); fi
	if [ -f $USERPATCHES_PATH/VERSION ]; then
		REVISION=$(cat "${USERPATCHES_PATH}"/VERSION)"$SUBREVISION" # all boards have same revision
	else
		REVISION=$(cat "${SRC}"/VERSION)"$SUBREVISION" # all boards have same revision
	fi
	[[ -z $VENDOR ]] && VENDOR="Armbian"
	[[ -z $ROOTPWD ]] && ROOTPWD="1234"                                  # Must be changed @first login
	[[ -z $MAINTAINER ]] && MAINTAINER="Igor Pecovnik"                   # deb signature
	[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
	DEST_LANG="${DEST_LANG:-"en_US.UTF-8"}"                              # en_US.UTF-8 is default locale for target
	display_alert "DEST_LANG..." "DEST_LANG: ${DEST_LANG}" "debug"

	export SKIP_EXTERNAL_TOOLCHAINS="${SKIP_EXTERNAL_TOOLCHAINS:-yes}" # don't use any external toolchains, by default.

	# Timezone
	if [[ -f /etc/timezone ]]; then # Timezone for target is taken from host, if it exists.
		TZDATA=$(cat /etc/timezone)
		display_alert "Using host's /etc/timezone for" "TZDATA: ${TZDATA}" "debug"
	else
		display_alert "Host has no /etc/timezone" "Using Etc/UTC by default" "debug"
		TZDATA="Etc/UTC" # If not /etc/timezone at host, default to UTC.
	fi

	USEALLCORES=yes # Use all CPU cores for compiling

	[[ -z $EXIT_PATCHING_ERROR ]] && EXIT_PATCHING_ERROR="" # exit patching if failed
	[[ -z $HOST ]] && HOST="$BOARD"                         # set hostname to the board
	cd "${SRC}" || exit

	[[ -z "${CHROOT_CACHE_VERSION}" ]] && CHROOT_CACHE_VERSION=7

	if [[ -d "${SRC}/.git" && "${CONFIG_DEFS_ONLY}" != "yes" ]]; then # don't waste time if only gathering config defs
		display_alert "Getting git info for repo" "${SRC}" "debug"
		BUILD_REPOSITORY_URL="$(git remote get-url "$(git remote | grep origin || true)" || true)" # ignore all errors
		BUILD_REPOSITORY_COMMIT="$(git describe --match=d_e_a_d_b_e_e_f --always --dirty || true)" # ignore error
	fi

	ROOTFS_CACHE_MAX=200 # max number of rootfs cache, older ones will be cleaned up

	# .deb compression. xz is standard, but is slow, so if avoided by default if not running in CI. one day, zstd.
	if [[ -z ${DEB_COMPRESS} ]]; then
		DEB_COMPRESS="none"                          # none is very fast bug produces big artifacts.
		[[ "${CI}" == "true" ]] && DEB_COMPRESS="xz" # xz is small and slow
	fi
	display_alert ".deb compression" "DEB_COMPRESS=${DEB_COMPRESS}" "debug"

	if [[ $BETA == yes ]]; then
		DEB_STORAGE=$DEST/debs-beta
	else
		DEB_STORAGE=$DEST/debs
	fi

	# image artefact destination with or without subfolder
	FINALDEST="${DEST}/images"
	if [[ -n "${MAKE_FOLDERS}" ]]; then
		FINALDEST="${DEST}"/images/"${BOARD}"/"${MAKE_FOLDERS}"
		install -d "${FINALDEST}"
	fi

	# Prepare rootfs filesystem support
	[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
	case "$ROOTFS_TYPE" in
		ext4 | fel) # nothing extra here
			;;
		nfs)
			FIXED_IMAGE_SIZE=256 # small SD card with kernel, boot script and .dtb/.bin files
			;;
		f2fs)
			enable_extension "fs-f2fs-support"
			# Fixed image size is in 1M dd blocks (MiB)
			# to get size of block device /dev/sdX execute as root: echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
			[[ -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE for use with f2fs"
			;;
		xfs)
			enable_extension "fs-xfs-support"
			;;
		btrfs)
			enable_extension "fs-btrfs-support"
			[[ -z $BTRFS_COMPRESSION ]] && BTRFS_COMPRESSION=zlib # default btrfs filesystem compression method is zlib
			[[ ! $BTRFS_COMPRESSION =~ zlib|lzo|zstd|none ]] && exit_with_error "Unknown btrfs compression method" "$BTRFS_COMPRESSION"
			;;
		*)
			exit_with_error "Unknown rootfs type: ROOTFS_TYPE='${ROOTFS_TYPE}'"
			;;
	esac

	# Support for LUKS / cryptroot
	if [[ $CRYPTROOT_ENABLE == yes ]]; then
		enable_extension "fs-cryptroot-support" # add the tooling needed, cryptsetup
		ROOT_MAPPER="armbian-root"              # TODO: fixed name can't be used for parallel image building (rpardini: ?)
		if [[ -z $CRYPTROOT_PASSPHRASE ]]; then # a passphrase is mandatory if rootfs encryption is enabled
			exit_with_error "Root encryption is enabled but CRYPTROOT_PASSPHRASE is not set"
		fi
		[[ -z $CRYPTROOT_SSH_UNLOCK ]] && CRYPTROOT_SSH_UNLOCK=yes
		[[ -z $CRYPTROOT_SSH_UNLOCK_PORT ]] && CRYPTROOT_SSH_UNLOCK_PORT=2022
		# Default to pdkdf2, this used to be the default with cryptroot <= 2.0, however
		# cryptroot 2.1 changed that to Argon2i. Argon2i is a memory intensive
		# algorithm which doesn't play well with SBCs (need 1GiB RAM by default !)
		# https://gitlab.com/cryptsetup/cryptsetup/-/issues/372
		[[ -z $CRYPTROOT_PARAMETERS ]] && CRYPTROOT_PARAMETERS="--pbkdf pbkdf2"
	fi

	# Since we are having too many options for mirror management,
	# then here is yet another mirror related option.
	# Respecting user's override in case a mirror is unreachable.
	case $REGIONAL_MIRROR in
		china)
			[[ -z $USE_MAINLINE_GOOGLE_MIRROR ]] && [[ -z $MAINLINE_MIRROR ]] && MAINLINE_MIRROR=tuna
			[[ -z $USE_GITHUB_UBOOT_MIRROR ]] && [[ -z $UBOOT_MIRROR ]] && UBOOT_MIRROR=gitee
			[[ -z $GITHUB_MIRROR ]] && GITHUB_MIRROR=gitclone
			[[ -z $DOWNLOAD_MIRROR ]] && DOWNLOAD_MIRROR=china
			;;
		*) ;;

	esac

	# used by multiple sources - reduce code duplication
	[[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]] && MAINLINE_MIRROR=google

	# URL for the git bundle used to "bootstrap" local git copies without too much server load. This applies independently of git mirror below.
	export MAINLINE_KERNEL_TORVALDS_BUNDLE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/clone.bundle" # this is plain torvalds, single branch
	export MAINLINE_KERNEL_STABLE_BUNDLE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/clone.bundle"     # this is all stable branches. with tags!
	export MAINLINE_KERNEL_COLD_BUNDLE_URL="${MAINLINE_KERNEL_COLD_BUNDLE_URL:-${MAINLINE_KERNEL_TORVALDS_BUNDLE_URL}}"          # default to Torvalds; everything else is small enough with this

	case $MAINLINE_MIRROR in
		google)
			MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
			MAINLINE_FIRMWARE_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
			;;
		tuna)
			MAINLINE_KERNEL_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git'
			MAINLINE_FIRMWARE_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-firmware.git'
			;;
		bfsu)
			MAINLINE_KERNEL_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-stable.git'
			MAINLINE_FIRMWARE_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-firmware.git'
			;;
		*)
			MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git' # "linux-stable" was renamed to "linux"
			MAINLINE_FIRMWARE_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
			;;
	esac

	MAINLINE_KERNEL_DIR='linux-mainline'

	[[ $USE_GITHUB_UBOOT_MIRROR == yes ]] && UBOOT_MIRROR=github

	case $UBOOT_MIRROR in
		gitee)
			MAINLINE_UBOOT_SOURCE='https://gitee.com/mirrors/u-boot.git'
			;;
		github)
			MAINLINE_UBOOT_SOURCE='https://github.com/u-boot/u-boot'
			;;
		*)
			MAINLINE_UBOOT_SOURCE='https://source.denx.de/u-boot/u-boot.git'
			;;
	esac

	MAINLINE_UBOOT_DIR='u-boot'

	case $GITHUB_MIRROR in
		fastgit)
			GITHUB_SOURCE='https://hub.fastgit.xyz'
			;;
		gitclone)
			GITHUB_SOURCE='https://gitclone.com/github.com'
			;;
		*)
			GITHUB_SOURCE='https://github.com'
			;;
	esac

	# Let's set default data if not defined in board configuration above
	[[ -z $OFFSET ]] && OFFSET=4 # offset to 1st partition (we use 4MiB boundaries by default)
	[[ -z $ARCH ]] && ARCH=armhf # makes little sense to default to anything...
	KERNEL_IMAGE_TYPE=zImage
	ATF_COMPILE=yes
	[[ -z $WIREGUARD ]] && WIREGUARD="yes"
	[[ -z $EXTRAWIFI ]] && EXTRAWIFI="yes"
	[[ -z $SKIP_BOOTSPLASH ]] && SKIP_BOOTSPLASH="no"
	[[ -z $PLYMOUTH ]] && PLYMOUTH="yes"
	[[ -z $AUFS ]] && AUFS="yes"
	[[ -z $IMAGE_PARTITION_TABLE ]] && IMAGE_PARTITION_TABLE="msdos"
	[[ -z $EXTRA_BSP_NAME ]] && EXTRA_BSP_NAME=""
	[[ -z $EXTRA_ROOTFS_MIB_SIZE ]] && EXTRA_ROOTFS_MIB_SIZE=0
	[[ -z $CONSOLE_AUTOLOGIN ]] && CONSOLE_AUTOLOGIN="yes"

	# single ext4 partition is the default and preferred configuration
	#BOOTFS_TYPE=''

	## ------ Sourcing family config ---------------------------

	declare -a family_source_paths=("${SRC}/config/sources/families/${LINUXFAMILY}.conf" "${USERPATCHES_PATH}/config/sources/families/${LINUXFAMILY}.conf")
	declare -i family_sourced_ok=0
	for family_source_path in "${family_source_paths[@]}"; do
		[[ ! -f "${family_source_path}" ]] && continue

		display_alert "Sourcing family configuration" "${family_source_path}" "info"
		# shellcheck source=/dev/null
		source "${family_source_path}"

		# @TODO: reset error handling, go figure what they do in there.

		family_sourced_ok=$((family_sourced_ok + 1))
	done

	# If no families sourced (and not allowed by ext var), bail out
	if [[ ${family_sourced_ok} -lt 1 ]]; then
		if [[ "${allow_no_family:-"no"}" != "yes" ]]; then
			exit_with_error "Sources configuration not found" "tried ${family_source_paths[*]}"
		fi
	fi

	# load "all-around common arch defaults" common.conf
	display_alert "Sourcing common arch configuration" "common.conf" "debug"
	# shellcheck source=config/sources/common.conf
	source "${SRC}/config/sources/common.conf"

	# load architecture defaults
	display_alert "Sourcing arch configuration" "${ARCH}.conf" "info"
	# shellcheck source=/dev/null
	source "${SRC}/config/sources/${ARCH}.conf"

	if [[ "$HAS_VIDEO_OUTPUT" == "no" ]]; then
		SKIP_BOOTSPLASH="yes"
		PLYMOUTH="no"
		[[ $BUILD_DESKTOP != "no" ]] && exit_with_error "HAS_VIDEO_OUTPUT is set to no. So we shouldn't build desktop environment"
	fi

	## Extensions: at this point we've sourced all the config files that will be used,
	##             and (hopefully) not yet invoked any extension methods. So this is the perfect
	##             place to initialize the extension manager. It will create functions
	##             like the 'post_family_config' that is invoked below.
	initialize_extension_manager

	call_extension_method "post_family_config" "config_tweaks_post_family_config" <<- 'POST_FAMILY_CONFIG'
		*give the config a chance to override the family/arch defaults*
		This hook is called after the family configuration (`sources/families/xxx.conf`) is sourced.
		Since the family can override values from the user configuration and the board configuration,
		it is often used to in turn override those.
	POST_FAMILY_CONFIG

	# A secondary post_family_config hook, this time with the BRANCH in the name, lowercase.
	call_extension_method "post_family_config_branch_${BRANCH,,}" <<- 'POST_FAMILY_CONFIG_PER_BRANCH'
		*give the config a chance to override the family/arch defaults, per branch*
		This hook is called after the family configuration (`sources/families/xxx.conf`) is sourced,
		and after `post_family_config()` hook is already run.
		The sole purpose of this is to avoid "case ... esac for $BRANCH" in the board configuration, 
		allowing separate functions for different branches. You're welcome.
	POST_FAMILY_CONFIG_PER_BRANCH

	# Lets make some variables readonly.
	# We don't want anything changing them, it's exclusively for family config.
	declare -g -r PACKAGE_LIST_FAMILY="${PACKAGE_LIST_FAMILY}"
	declare -g -r PACKAGE_LIST_FAMILY_REMOVE="${PACKAGE_LIST_FAMILY_REMOVE}"

	display_alert "Done with do_main_configuration" "do_main_configuration" "debug"
}

function do_extra_configuration() {
	[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
	[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
	[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

	declare BOOTCONFIG_VAR_NAME="BOOTCONFIG_${BRANCH^^}"
	[[ -n ${!BOOTCONFIG_VAR_NAME} ]] && BOOTCONFIG=${!BOOTCONFIG_VAR_NAME}
	[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
	[[ -z $BOOTPATCHDIR ]] && BOOTPATCHDIR="u-boot-$LINUXFAMILY"
	[[ -z $ATFPATCHDIR ]] && ATFPATCHDIR="atf-$LINUXFAMILY"
	[[ -z $KERNELPATCHDIR ]] && KERNELPATCHDIR="$LINUXFAMILY-$BRANCH"

	if [[ "$RELEASE" =~ ^(focal|jammy|kinetic|lunar)$ ]]; then
		DISTRIBUTION="Ubuntu"
	else
		DISTRIBUTION="Debian"
	fi

	DEBIAN_MIRROR='deb.debian.org/debian'
	DEBIAN_SECURTY='security.debian.org/'
	[[ "${ARCH}" == "amd64" ]] &&
		UBUNTU_MIRROR='archive.ubuntu.com/ubuntu/' ||
		UBUNTU_MIRROR='ports.ubuntu.com/'

	if [[ $DOWNLOAD_MIRROR == "china" ]]; then
		DEBIAN_MIRROR='mirrors.tuna.tsinghua.edu.cn/debian'
		DEBIAN_SECURTY='mirrors.tuna.tsinghua.edu.cn/debian-security'
		[[ "${ARCH}" == "amd64" ]] &&
			UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu/' ||
			UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/'
	fi

	if [[ $DOWNLOAD_MIRROR == "bfsu" ]]; then
		DEBIAN_MIRROR='mirrors.bfsu.edu.cn/debian'
		DEBIAN_SECURTY='mirrors.bfsu.edu.cn/debian-security'
		[[ "${ARCH}" == "amd64" ]] &&
			UBUNTU_MIRROR='mirrors.bfsu.edu.cn/ubuntu/' ||
			UBUNTU_MIRROR='mirrors.bfsu.edu.cn/ubuntu-ports/'
	fi

	if [[ "${ARCH}" == "amd64" ]]; then
		UBUNTU_MIRROR='archive.ubuntu.com/ubuntu' # ports are only for non-amd64, of course.
		if [[ -n ${CUSTOM_UBUNTU_MIRROR} ]]; then # ubuntu redirector doesn't work well on amd64
			UBUNTU_MIRROR="${CUSTOM_UBUNTU_MIRROR}"
		fi
	fi

	if [[ "${ARCH}" == "arm64" ]]; then
		if [[ -n ${CUSTOM_UBUNTU_MIRROR_ARM64} ]]; then
			display_alert "Using custom ports/arm64 mirror" "${CUSTOM_UBUNTU_MIRROR_ARM64}" "info"
			UBUNTU_MIRROR="${CUSTOM_UBUNTU_MIRROR_ARM64}"
		fi
	fi

	# Debian needs the ports repo when strapping riscv64 - revise after bookworm release
	if [[ "${ARCH}" == "riscv64" ]] && [[ $DISTRIBUTION == Debian ]]; then
		DEBIAN_MIRROR='deb.debian.org/debian-ports'
	fi

	# Control aria2c's usage of ipv6.
	[[ -z $DISABLE_IPV6 ]] && DISABLE_IPV6="true"

	# For (late) user override.
	# Notice: it is too late to define hook functions or add extensions in lib.config, since the extension initialization already ran by now.
	#         in case the user tries to use them in lib.config, hopefully they'll be detected as "wishful hooking" and the user will be wrn'ed.
	if [[ -f $USERPATCHES_PATH/lib.config ]]; then
		display_alert "Using user configuration override" "$USERPATCHES_PATH/lib.config" "info"
		source "$USERPATCHES_PATH"/lib.config
	fi

	call_extension_method "user_config" <<- 'USER_CONFIG'
		*Invoke function with user override*
		Allows for overriding configuration values set anywhere else.
		It is called after sourcing the `lib.config` file if it exists,
		but before assembling any package lists.
	USER_CONFIG

	display_alert "Extensions: prepare configuration" "extension_prepare_config" "debug"
	call_extension_method "extension_prepare_config" <<- 'EXTENSION_PREPARE_CONFIG'
		*allow extensions to prepare their own config, after user config is done*
		Implementors should preserve variable values pre-set, but can default values an/or validate them.
		This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
	EXTENSION_PREPARE_CONFIG

	# apt-cacher-ng mirror configurarion
	APT_MIRROR=$DEBIAN_MIRROR
	if [[ $DISTRIBUTION == Ubuntu ]]; then
		APT_MIRROR=$UBUNTU_MIRROR
	fi

	[[ -n "${APT_PROXY_ADDR}" ]] && display_alert "Using custom apt proxy address" "APT_PROXY_ADDR=${APT_PROXY_ADDR}" "info"

	# @TODO: allow to run aggregation, for CONFIG_DEFS_ONLY? rootfs_aggregate_packages

	# Give the option to configure DNS server used in the chroot during the build process
	[[ -z $NAMESERVER ]] && NAMESERVER="1.0.0.1" # default is cloudflare alternate

	display_alert "Done with do_extra_configuration" "do_extra_configuration" "debug"
}

function write_config_summary_output_file() {
	local debug_dpkg_arch debug_uname debug_virt debug_src_mount
	debug_dpkg_arch="$(dpkg --print-architecture)"
	debug_uname="$(uname -a)"
	# We might not have systemd-detect-virt, specially inside docker. Docker images have no systemd...
	debug_virt="unknown-nosystemd"
	if [[ -n "$(command -v systemd-detect-virt)" ]]; then
		debug_virt="$(systemd-detect-virt || true)"
	fi
	debug_src_mount="$(findmnt --output TARGET,SOURCE,FSTYPE,AVAIL --target "${SRC}" --uniq)"

	display_alert "Writing build config summary to" "debug log" "debug"
	LOG_ASSET="build.summary.txt" do_with_log_asset cat <<- EOF
		## BUILD SCRIPT ENVIRONMENT

		Repository: $REPOSITORY_URL
		Version: $REPOSITORY_COMMIT

		Host OS: $HOSTRELEASE
		Host arch: ${debug_dpkg_arch}
		Host system: ${debug_uname}
		Virtualization type: ${debug_virt}

		## Build script directories
		Build directory is located on:
		${debug_src_mount}

		## BUILD CONFIGURATION

		Build target:
		Board: $BOARD
		Branch: $BRANCH
		Minimal: $BUILD_MINIMAL
		Desktop: $BUILD_DESKTOP
		Desktop Environment: $DESKTOP_ENVIRONMENT
		Software groups: $DESKTOP_APPGROUPS_SELECTED

		Kernel configuration:
		Repository: $KERNELSOURCE
		Branch: $KERNELBRANCH
		Config file: $LINUXCONFIG

		U-boot configuration:
		Repository: $BOOTSOURCE
		Branch: $BOOTBRANCH
		Config file: $BOOTCONFIG

		Partitioning configuration: $IMAGE_PARTITION_TABLE offset: $OFFSET
		Boot partition type: ${BOOTFS_TYPE:-(none)} ${BOOTSIZE:+"(${BOOTSIZE} MB)"}
		Root partition type: $ROOTFS_TYPE ${FIXED_IMAGE_SIZE:+"(${FIXED_IMAGE_SIZE} MB)"}

		CPU configuration: $CPUMIN - $CPUMAX with $GOVERNOR
	EOF
}
