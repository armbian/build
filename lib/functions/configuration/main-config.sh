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

function do_main_configuration() {

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
	[[ -z $DEB_COMPRESS ]] && DEB_COMPRESS="xz"                          # compress .debs with XZ by default. Use 'none' for faster/larger builds
	TZDATA=$(cat /etc/timezone)                                          # Timezone for target is taken from host or defined here.
	USEALLCORES=yes                                                      # Use all CPU cores for compiling
	HOSTRELEASE=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)
	[[ -z $HOSTRELEASE ]] && HOSTRELEASE=$(cut -d'/' -f1 /etc/debian_version)
	[[ -z $EXIT_PATCHING_ERROR ]] && EXIT_PATCHING_ERROR="" # exit patching if failed
	[[ -z $HOST ]] && HOST="$BOARD"                         # set hostname to the board
	cd "${SRC}" || exit

	[[ -z "${CHROOT_CACHE_VERSION}" ]] && CHROOT_CACHE_VERSION=7
	BUILD_REPOSITORY_URL=$(improved_git remote get-url $(improved_git remote 2> /dev/null | grep origin) 2> /dev/null)
	BUILD_REPOSITORY_COMMIT=$(improved_git describe --match=d_e_a_d_b_e_e_f --always --dirty 2> /dev/null)
	ROOTFS_CACHE_MAX=200 # max number of rootfs cache, older ones will be cleaned up

	if [[ $BETA == yes ]]; then
		DEB_STORAGE=$DEST/debs-beta
		REPO_STORAGE=$DEST/repository-beta
		REPO_CONFIG="aptly-beta.conf"
	else
		DEB_STORAGE=$DEST/debs
		REPO_STORAGE=$DEST/repository
		REPO_CONFIG="aptly.conf"
	fi

	# image artefact destination with or without subfolder
	FINALDEST=$DEST/images
	if [[ -n "${MAKE_FOLDERS}" ]]; then

		FINALDEST=$DEST/images/"${BOARD}"/"${MAKE_FOLDERS}"
		install -d ${FINALDEST}

	fi

	# TODO: fixed name can't be used for parallel image building
	ROOT_MAPPER="armbian-root"

	[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
	[[ "ext4 f2fs btrfs xfs nfs fel" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

	[[ -z $BTRFS_COMPRESSION ]] && BTRFS_COMPRESSION=zlib # default btrfs filesystem compression method is zlib
	[[ ! $BTRFS_COMPRESSION =~ zlib|lzo|zstd|none ]] && exit_with_error "Unknown btrfs compression method" "$BTRFS_COMPRESSION"

	# Fixed image size is in 1M dd blocks (MiB)
	# to get size of block device /dev/sdX execute as root:
	# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
	[[ "f2fs" == *$ROOTFS_TYPE* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE"

	# a passphrase is mandatory if rootfs encryption is enabled
	if [[ $CRYPTROOT_ENABLE == yes && -z $CRYPTROOT_PASSPHRASE ]]; then
		exit_with_error "Root encryption is enabled but CRYPTROOT_PASSPHRASE is not set"
	fi

	# small SD card with kernel, boot script and .dtb/.bin files
	[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=256

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
			MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
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
	ARCH=armhf
	KERNEL_IMAGE_TYPE=zImage
	ATF_COMPILE=yes
	[[ -z $CRYPTROOT_SSH_UNLOCK ]] && CRYPTROOT_SSH_UNLOCK=yes
	[[ -z $CRYPTROOT_SSH_UNLOCK_PORT ]] && CRYPTROOT_SSH_UNLOCK_PORT=2022
	# Default to pdkdf2, this used to be the default with cryptroot <= 2.0, however
	# cryptroot 2.1 changed that to Argon2i. Argon2i is a memory intensive
	# algorithm which doesn't play well with SBCs (need 1GiB RAM by default !)
	# https://gitlab.com/cryptsetup/cryptsetup/-/issues/372
	[[ -z $CRYPTROOT_PARAMETERS ]] && CRYPTROOT_PARAMETERS="--pbkdf pbkdf2"
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
	[[ ! -f ${SRC}/config/sources/families/$LINUXFAMILY.conf ]] &&
		exit_with_error "Sources configuration not found" "$LINUXFAMILY"

	source "${SRC}/config/sources/families/${LINUXFAMILY}.conf"

	if [[ -f $USERPATCHES_PATH/sources/families/$LINUXFAMILY.conf ]]; then
		display_alert "Adding user provided $LINUXFAMILY overrides"
		source "$USERPATCHES_PATH/sources/families/${LINUXFAMILY}.conf"
	fi

	# load architecture defaults
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

	call_extension_method "post_family_config" "config_tweaks_post_family_config" << 'POST_FAMILY_CONFIG'
*give the config a chance to override the family/arch defaults*
This hook is called after the family configuration (`sources/families/xxx.conf`) is sourced.
Since the family can override values from the user configuration and the board configuration,
it is often used to in turn override those.
POST_FAMILY_CONFIG

	interactive_desktop_main_configuration

	#exit_with_error 'Testing'

	# set unique mounting directory
	MOUNT_UUID=$(uuidgen)
	SDCARD="${SRC}/.tmp/rootfs-${MOUNT_UUID}"
	MOUNT="${SRC}/.tmp/mount-${MOUNT_UUID}"
	DESTIMG="${SRC}/.tmp/image-${MOUNT_UUID}"

	[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
	[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
	[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

	BOOTCONFIG_VAR_NAME=BOOTCONFIG_${BRANCH^^}
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

	CLI_CONFIG_PATH="${SRC}/config/cli/${RELEASE}"
	DEBOOTSTRAP_CONFIG_PATH="${CLI_CONFIG_PATH}/debootstrap"

	if [[ $? != 0 ]]; then
		exit_with_error "The desktop environment ${DESKTOP_ENVIRONMENT} is not available for your architecture ${ARCH}"
	fi

	AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS="
	${SRC}/config
	${SRC}/config/optional/_any_board/_config
	${SRC}/config/optional/architectures/${ARCH}/_config
	${SRC}/config/optional/families/${LINUXFAMILY}/_config
	${SRC}/config/optional/boards/${BOARD}/_config
	${USERPATCHES_PATH}
	"

	DEBOOTSTRAP_SEARCH_RELATIVE_DIRS="
	cli/_all_distributions/debootstrap
	cli/${RELEASE}/debootstrap
	"

	CLI_SEARCH_RELATIVE_DIRS="
	cli/_all_distributions/main
	cli/${RELEASE}/main
	"

	PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS="
	${SRC}/packages
	${SRC}/config/optional/_any_board/_packages
	${SRC}/config/optional/architectures/${ARCH}/_packages
	${SRC}/config/optional/families/${LINUXFAMILY}/_packages
	${SRC}/config/optional/boards/${BOARD}/_packages
	"

	DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS="
	desktop/_all_distributions/environments/_all_environments
	desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}
	desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
	desktop/${RELEASE}/environments/_all_environments
	desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}
	desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
	"

	DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS="
	desktop/_all_distributions/appgroups
	desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/appgroups
	desktop/${RELEASE}/appgroups
	desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/appgroups
	"

	DEBOOTSTRAP_LIST="$(one_line aggregate_all_debootstrap "packages" " ")"
	DEBOOTSTRAP_COMPONENTS="$(one_line aggregate_all_debootstrap "components" " ")"
	DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS// /,}"
	PACKAGE_LIST="$(one_line aggregate_all_cli "packages" " ")"
	PACKAGE_LIST_ADDITIONAL="$(one_line aggregate_all_cli "packages.additional" " ")"

	LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/debootstrap-list.log"
	show_checklist_variables "DEBOOTSTRAP_LIST DEBOOTSTRAP_COMPONENTS PACKAGE_LIST PACKAGE_LIST_ADDITIONAL PACKAGE_LIST_UNINSTALL"

	# Dependent desktop packages
	# Myy : Sources packages from file here

	# Myy : FIXME Rename aggregate_all to aggregate_all_desktop
	if [[ $BUILD_DESKTOP == "yes" ]]; then
		PACKAGE_LIST_DESKTOP+="$(one_line aggregate_all_desktop "packages" " ")"
		echo -e "\nGroups selected ${DESKTOP_APPGROUPS_SELECTED} -> PACKAGES :" >> "${LOG_OUTPUT_FILE}"
		show_checklist_variables PACKAGE_LIST_DESKTOP
	fi
	unset LOG_OUTPUT_FILE

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

	[[ -z $DISABLE_IPV6 ]] && DISABLE_IPV6="true"

	# For (late) user override.
	# Notice: it is too late to define hook functions or add extensions in lib.config, since the extension initialization already ran by now.
	#         in case the user tries to use them in lib.config, hopefully they'll be detected as "wishful hooking" and the user will be wrn'ed.
	if [[ -f $USERPATCHES_PATH/lib.config ]]; then
		display_alert "Using user configuration override" "$USERPATCHES_PATH/lib.config" "info"
		source "$USERPATCHES_PATH"/lib.config
	fi

	call_extension_method "user_config" << 'USER_CONFIG'
*Invoke function with user override*
Allows for overriding configuration values set anywhere else.
It is called after sourcing the `lib.config` file if it exists,
but before assembling any package lists.
USER_CONFIG

	call_extension_method "extension_prepare_config" << 'EXTENSION_PREPARE_CONFIG'
*allow extensions to prepare their own config, after user config is done*
Implementors should preserve variable values pre-set, but can default values an/or validate them.
This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
EXTENSION_PREPARE_CONFIG

	# apt-cacher-ng mirror configurarion
	if [[ $DISTRIBUTION == Ubuntu ]]; then
		APT_MIRROR=$UBUNTU_MIRROR
	else
		APT_MIRROR=$DEBIAN_MIRROR
	fi

	[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

	# Build final package list after possible override
	PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"
	PACKAGE_MAIN_LIST="$(cleanup_list PACKAGE_LIST)"

	[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP"
	PACKAGE_LIST="$(cleanup_list PACKAGE_LIST)"

	# remove any packages defined in PACKAGE_LIST_RM in lib.config
	aggregated_content="${PACKAGE_LIST_RM} "
	aggregate_all_cli "packages.remove" " "
	aggregate_all_desktop "packages.remove" " "
	PACKAGE_LIST_RM="$(cleanup_list aggregated_content)"
	unset aggregated_content

	aggregated_content=""
	aggregate_all_cli "packages.uninstall" " "
	aggregate_all_desktop "packages.uninstall" " "
	PACKAGE_LIST_UNINSTALL="$(cleanup_list aggregated_content)"
	unset aggregated_content

	if [[ -n $PACKAGE_LIST_RM ]]; then
		display_alert "Package remove list ${PACKAGE_LIST_RM}"
		# Turns out that \b can be tricked by dashes.
		# So if you remove mesa-utils but still want to install "mesa-utils-extra"
		# a "\b(mesa-utils)\b" filter will convert "mesa-utils-extra" to "-extra".
		# \W is not tricked by this but consumes the surrounding spaces, so we
		# replace the occurence by one space, to avoid sticking the next word to
		# the previous one after consuming the spaces.
		DEBOOTSTRAP_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${DEBOOTSTRAP_LIST} ")
		PACKAGE_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST} ")
		PACKAGE_MAIN_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_MAIN_LIST} ")
		if [[ $BUILD_DESKTOP == "yes" ]]; then
			PACKAGE_LIST_DESKTOP=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST_DESKTOP} ")
			# Removing double spaces... AGAIN, since we might have used a sed on them
			# Do not quote the variables. This would defeat the trick.
			PACKAGE_LIST_DESKTOP="$(echo ${PACKAGE_LIST_DESKTOP})"
		fi

		# Removing double spaces... AGAIN, since we might have used a sed on them
		# Do not quote the variables. This would defeat the trick.
		DEBOOTSTRAP_LIST="$(echo ${DEBOOTSTRAP_LIST})"
		PACKAGE_LIST="$(echo ${PACKAGE_LIST})"
		PACKAGE_MAIN_LIST="$(echo ${PACKAGE_MAIN_LIST})"
	fi

	LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/debootstrap-list.log"
	echo -e "\nVariables after manual configuration" >> $LOG_OUTPUT_FILE
	show_checklist_variables "DEBOOTSTRAP_COMPONENTS DEBOOTSTRAP_LIST PACKAGE_LIST PACKAGE_MAIN_LIST"
	unset LOG_OUTPUT_FILE

	# Give the option to configure DNS server used in the chroot during the build process
	[[ -z $NAMESERVER ]] && NAMESERVER="1.0.0.1" # default is cloudflare alternate

	call_extension_method "post_aggregate_packages" "user_config_post_aggregate_packages" << 'POST_AGGREGATE_PACKAGES'
*For final user override, using a function, after all aggregations are done*
Called after aggregating all package lists, before the end of `compilation.sh`.
Packages will still be installed after this is called, so it is the last chance
to confirm or change any packages.
POST_AGGREGATE_PACKAGES

	# debug
	cat <<- EOF >> "${DEST}"/${LOG_SUBPATH}/output.log

		## BUILD SCRIPT ENVIRONMENT

		Repository: $REPOSITORY_URL
		Version: $REPOSITORY_COMMIT

		Host OS: $HOSTRELEASE
		Host arch: $(dpkg --print-architecture)
		Host system: $(uname -a)
		Virtualization type: $(systemd-detect-virt)

		## Build script directories
		Build directory is located on:
		$(findmnt --output TARGET,SOURCE,FSTYPE,AVAIL --target "${SRC}" --uniq)

		Build directory permissions:
		$(getfacl -p "${SRC}")

		Temp directory permissions:
		$(getfacl -p "${SRC}"/.tmp 2> /dev/null)

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
