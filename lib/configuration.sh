#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# common options
# daily beta build contains date in subrevision
#if [[ $BETA == yes && -z $SUBREVISION ]]; then SUBREVISION="."$(date --date="tomorrow" +"%j"); fi
REVISION=$(cat "${SRC}"/VERSION)"$SUBREVISION" # all boards have same revision
[[ -z $ROOTPWD ]] && ROOTPWD="1234" # Must be changed @first login
[[ -z $MAINTAINER ]] && MAINTAINER="Igor Pecovnik" # deb signature
[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
TZDATA=$(cat /etc/timezone) # Timezone for target is taken from host or defined here.
USEALLCORES=yes # Use all CPU cores for compiling
EXIT_PATCHING_ERROR="" # exit patching if failed
[[ -z $HOST ]] && HOST="$BOARD" # set hostname to the board
cd "${SRC}" || exit
ROOTFSCACHE_VERSION=1
CHROOT_CACHE_VERSION=7
BUILD_REPOSITORY_URL=$(improved_git remote get-url $(improved_git remote 2>/dev/null | grep origin) 2>/dev/null)
BUILD_REPOSITORY_COMMIT=$(improved_git describe --match=d_e_a_d_b_e_e_f --always --dirty 2>/dev/null)
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
[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=64

# used by multiple sources - reduce code duplication
[[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]] && MAINLINE_MIRROR=google
case $MAINLINE_MIRROR in
	google) MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable' ;;
	tuna) MAINLINE_KERNEL_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git' ;;
	*) MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git' ;;
esac
MAINLINE_KERNEL_DIR='linux-mainline'

if [[ $USE_GITHUB_UBOOT_MIRROR == yes ]]; then
	MAINLINE_UBOOT_SOURCE='https://github.com/RobertCNelson/u-boot'
else
	MAINLINE_UBOOT_SOURCE='git://git.denx.de/u-boot.git'
fi
MAINLINE_UBOOT_DIR='u-boot'

# Let's set default data if not defined in board configuration above
[[ -z $OFFSET ]] && OFFSET=4 # offset to 1st partition (we use 4MiB boundaries by default)
ARCH=armhf
KERNEL_IMAGE_TYPE=zImage
CAN_BUILD_STRETCH=yes
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
[[ -z $AUFS ]] && AUFS="yes"
[[ -z $IMAGE_PARTITION_TABLE ]] && IMAGE_PARTITION_TABLE="msdos"

# single ext4 partition is the default and preferred configuration
#BOOTFS_TYPE=''

# set unique mounting directory
SDCARD="${SRC}/.tmp/rootfs-${BRANCH}-${BOARD}-${RELEASE}-${DESKTOP_ENVIRONMENT:+"$DESKTOP_ENVIRONMENT-"}${BUILD_DESKTOP}-${SELECTED_CONFIGURATION}"
MOUNT="${SRC}/.tmp/mount-${BRANCH}-${BOARD}-${RELEASE}-${DESKTOP_ENVIRONMENT:+"$DESKTOP_ENVIRONMENT-"}${BUILD_DESKTOP}-${SELECTED_CONFIGURATION}"
DESTIMG="${SRC}/.tmp/image-${BRANCH}-${BOARD}-${RELEASE}-${DESKTOP_ENVIRONMENT:+"$DESKTOP_ENVIRONMENT-"}${BUILD_DESKTOP}-${SELECTED_CONFIGURATION}"

# dropbear needs to be configured differently
[[ $CRYPTROOT_ENABLE == yes && $RELEASE == xenial ]] && exit_with_error "Encrypted rootfs is not supported in Xenial"
[[ $RELEASE == stretch && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Debian Stretch images with selected kernel is not supported"
[[ $RELEASE == bionic && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Ubuntu Bionic images with selected kernel is not supported"
[[ $RELEASE == bionic && $(lsb_release -sc) == xenial ]] && exit_with_error "Building Ubuntu Bionic images requires a Bionic build host. Please upgrade your host or select a different target OS"

[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

BOOTCONFIG_VAR_NAME=BOOTCONFIG_${BRANCH^^}
[[ -n ${!BOOTCONFIG_VAR_NAME} ]] && BOOTCONFIG=${!BOOTCONFIG_VAR_NAME}
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
[[ -z $BOOTPATCHDIR ]] && BOOTPATCHDIR="u-boot-$LINUXFAMILY"
[[ -z $ATFPATCHDIR ]] && ATFPATCHDIR="atf-$LINUXFAMILY"
[[ -z $KERNELPATCHDIR ]] && KERNELPATCHDIR="$LINUXFAMILY-$BRANCH"

if [[ "$RELEASE" =~ ^(xenial|bionic|focal|groovy)$ ]]; then
		DISTRIBUTION="Ubuntu"
	else
		DISTRIBUTION="Debian"
fi

CLI_CONFIG_PATH="${SRC}/config/cli/${RELEASE}"
DEBOOTSTRAP_CONFIG_PATH="${CLI_CONFIG_PATH}/debootstrap"

desktop_element_available_for_arch "${DESKTOP_CONFIGS_DIR}/${DESKTOP_ENVIRONMENT}" "${ARCH}"

if [[ $? != 0 ]]; then
	exit_with_error "The desktop environment ${DESKTOP_ENVIRONMENT} is not available for your architecture ${ARCH}"
fi

aggregate_all_debootstrap() {
	local looked_up_subpath="${1}"
	local separator="${2}"
	local potential_paths="${DEBOOTSTRAP_CONFIG_PATH}/${looked_up_subpath}"
	potential_paths+=" ${DEBOOTSTRAP_CONFIG_PATH}/custom/boards/${BOARD}/${looked_up_subpath}"
	display_alert "SELECTED_CONFIGURATION : ${SELECTED_CONFIGURATION}"
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		potential_paths+=" ${DEBOOTSTRAP_CONFIG_PATH}/debootstrap/config_${SELECTED_CONFIGURATION}/${looked_up_subpath}"
		potential_paths+=" ${DEBOOTSTRAP_CONFIG_PATH}/debootstrap/custom/boards/${BOARD}/config_${SELECTED_CONFIGURATION}/${looked_up_subpath}"
	fi

	aggregate_content
}

aggregated_content=""
aggregate_all_debootstrap "packages"
DEBOOTSTRAP_LIST="${aggregated_content}"
display_alert "DEBOOTSTRAP LIST : ${DEBOOTSTRAP_LIST}"
unset aggregated_content

aggregated_content=""
aggregate_all_debootstrap "components"
DEBOOTSTRAP_COMPONENTS="${aggregated_content}"
display_alert "DEBOOTSTRAP_COMPONENTS : ${DEBOOTSTRAP_COMPONENTS}"
unset aggregated_content

# Base system dependencies. Since adding MINIMAL_IMAGE we rely on "variant=minbase" which has very basic package set
#DEBOOTSTRAP_LIST="locales gnupg ifupdown apt-utils apt-transport-https ca-certificates bzip2 console-setup cpio cron \
#	dbus init initramfs-tools iputils-ping isc-dhcp-client kmod less libpam-systemd \
#	linux-base logrotate netbase netcat-openbsd rsyslog systemd sudo ucf udev whiptail \
#	wireless-regdb crda dmsetup rsync tzdata"

display_alert "Debootstrap packages list : $DEBOOTSTRAP_LIST"

# Myy : ???
# [[ $BUILD_DESKTOP == yes ]] && DEBOOTSTRAP_LIST+=" libgtk2.0-bin"

aggregate_all_cli() {
	local looked_up_subpath="${1}"
	local separator="${2}"
	local potential_paths="${CLI_CONFIG_PATH}/main/${looked_up_subpath}"
	potential_paths+=" ${CLI_CONFIG_PATH}/main/custom/boards/${BOARD}/${looked_up_subpath}"
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		potential_paths+=" ${CLI_CONFIG_PATH}/main/config_${SELECTED_CONFIGURATION}/${looked_up_subpath}"
		potential_paths+=" ${CLI_CONFIG_PATH}/main/custom/boards/${BOARD}/config_${SELECTED_CONFIGURATION}/${looked_up_subpath}"
	fi
	
	aggregate_content
}

aggregated_content=""
aggregate_all_cli "packages" " "
display_alert "Aggregated content : ${aggregated_content}"
PACKAGE_LIST="${aggregated_content}"
unset aggregated_content

aggregated_content=""
aggregate_all_cli "packages.additional" " "
PACKAGE_LIST_ADDITIONAL="${aggregated_content}"
unset aggregated_content

# For minimal build different set of packages is needed
# Essential packages for minimal build
# PACKAGE_LIST="bc cpufrequtils device-tree-compiler fping fake-hwclock psmisc chrony parted dialog \
# 		ncurses-term sysfsutils toilet figlet u-boot-tools usbutils openssh-server \
# 		nocache debconf-utils python3-apt"

# # Non-essential packages for minimal build
# PACKAGE_LIST_ADDITIONAL="network-manager wireless-tools lsof htop mmc-utils wget nano sysstat net-tools resolvconf iozone3 jq libcrack2 cracklib-runtime curl"

# if [[ "$BUILD_MINIMAL" != "yes"  ]]; then
# 	# Essential packages
# 	PACKAGE_LIST="$PACKAGE_LIST bridge-utils build-essential fbset \
# 		iw wpasupplicant sudo linux-base crda \
# 		wireless-regdb unattended-upgrades \
# 		console-setup unicode-data initramfs-tools \
# 		ca-certificates expect iptables automake html2text \
# 		bison flex libwrap0-dev libssl-dev libnl-3-dev libnl-genl-3-dev keyboard-configuration"


# 	# Non-essential packages
# 	PACKAGE_LIST_ADDITIONAL="$PACKAGE_LIST_ADDITIONAL software-properties-common alsa-utils btrfs-progs dosfstools iotop stress screen \
# 		ntfs-3g vim pciutils evtest pv libfuse2 libdigest-sha-perl \
# 		libproc-processtable-perl aptitude dnsutils f3 haveged hdparm rfkill vlan bash-completion \
# 		hostapd git ethtool unzip ifenslave libpam-systemd iperf3 \
# 		libnss-myhostname f2fs-tools avahi-autoipd iputils-arping qrencode sunxi-tools"
# fi


# Dependent desktop packages
# Myy : Sources packages from file here

# Myy : FIXME Rename aggregate_all to aggregate_all_desktop
aggregated_content=""
aggregate_all "packages" " "

PACKAGE_LIST_DESKTOP+="${aggregated_content}"

unset aggregated_content

echo "Groups selected ${DESKTOP_APPGROUPS_SELECTED} -> PACKAGES : ${PACKAGE_LIST_DESKTOP}"

# Myy : Clean the Debootstrap lists. The packages list will be cleaned when necessary.
# This horrendous cleanup syntax is used to remove trailing and leading spaces.

# Previous comment : tab cleanup is mandatory

DEBOOTSTRAP_LIST="${DEBOOTSTRAP_LIST#"${DEBOOTSTRAP_LIST%%[![:space:]]*}"}"
DEBOOTSTRAP_LIST="${DEBOOTSTRAP_LIST%"${DEBOOTSTRAP_LIST##*[![:space:]]}"}"

DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS#"${DEBOOTSTRAP_COMPONENTS%%[![:space:]]*}"}"
DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS%"${DEBOOTSTRAP_COMPONENTS##*[![:space:]]}"}"
DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS// /,}"

display_alert "Deboostrap"
display_alert "Components ${DEBOOTSTRAP_COMPONENTS}"
display_alert "Packages ${DEBOOTSTRAP_LIST}"
display_alert "----"
display_alert "CLI packages"
display_alert "Standard : ${PACKAGE_LIST}"
display_alert "Additional : ${PACKAGE_LIST_ADDITIONAL}"

DEBIAN_MIRROR='deb.debian.org/debian'
DEBIAN_SECURTY='security.debian.org/'
UBUNTU_MIRROR='ports.ubuntu.com/'

if [[ $DOWNLOAD_MIRROR == china ]] ; then
	DEBIAN_MIRROR='mirrors.tuna.tsinghua.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.tuna.tsinghua.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/'
fi

# For user override
if [[ -f $USERPATCHES_PATH/lib.config ]]; then
	display_alert "Using user configuration override" "$USERPATCHES_PATH/lib.config" "info"
	source "$USERPATCHES_PATH"/lib.config
fi

if [[ "$(type -t user_config)" == "function" ]]; then
	display_alert "Invoke function with user override" "user_config" "info"
	user_config
fi

# apt-cacher-ng mirror configurarion
if [[ $DISTRIBUTION == Ubuntu ]]; then
	APT_MIRROR=$UBUNTU_MIRROR
else
	APT_MIRROR=$DEBIAN_MIRROR
fi

[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"

# Clean up the list
# Myy : Replace any single or multiple instance of 'space' characters
# (spaces, tabs, newlines) by a single space character
# DO NOT PUT quotes after 'echo', else the trick won't work.
PACKAGE_LIST="${PACKAGE_LIST#"${PACKAGE_LIST%%[![:space:]]*}"}"
PACKAGE_LIST="${PACKAGE_LIST%"${PACKAGE_LIST##*[![:space:]]}"}"
PACKAGE_LIST="$(echo ${PACKAGE_LIST})"

PACKAGE_MAIN_LIST="${PACKAGE_LIST}"

# FIXME Myy: Factorize this...
PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP#"${PACKAGE_LIST_DESKTOP%%[![:space:]]*}"}"
PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP%"${PACKAGE_LIST_DESKTOP##*[![:space:]]}"}"
PACKAGE_LIST_DESKTOP="$(echo ${PACKAGE_LIST_DESKTOP})"

[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP"

# remove any packages defined in PACKAGE_LIST_RM in lib.config
aggregated_content=""
aggregate_all_cli "packages.remove" " "
aggregate_all "packages.remove" " "
PACKAGE_LIST_RM="${PACKAGE_LIST_RM} ${aggregated_content}"
unset aggregated_content

aggregated_content=""
aggregate_all_cli "packages.uninstall" " "
aggregate_all "packages.uninstall" " "
PACKAGE_LIST_UNINSTALL="$(cleanup_list aggregated_content)"
unset aggregated_content

PACKAGE_LIST_RM="${PACKAGE_LIST_RM#"${PACKAGE_LIST_RM%%[![:space:]]*}"}"
PACKAGE_LIST_RM="${PACKAGE_LIST_RM%"${PACKAGE_LIST_RM##*[![:space:]]}"}"
PACKAGE_LIST_RM="$(echo ${PACKAGE_LIST_RM})"

display_alert "PACKAGE_MAIN_LIST : ${PACKAGE_MAIN_LIST}"
display_alert "PACKAGE_LIST : ${PACKAGE_LIST}"
display_alert "PACKAGE_LIST_RM : ${PACKAGE_LIST_RM}"
display_alert "PACKAGE_LIST_UNINSTALL : ${PACKAGE_LIST_UNINSTALL}"

if [[ -n $PACKAGE_LIST_RM ]]; then
	display_alert "Remove filter : $(tr ' ' '|' <<< ${PACKAGE_LIST_RM})"
	# Turns out that \b can be tricked by dashes.
	# So if you remove mesa-utils but still want to install "mesa-utils-extra"
	# a "\b(mesa-utils)\b" filter will convert "mesa-utils-extra" to "-extra".
	# \W is not tricked by this but consumes the surrounding spaces, so we
	# replace the occurence by one space, to avoid sticking the next word to
	# the previous one after consuming the spaces.
	PACKAGE_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST} ")
	PACKAGE_MAIN_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_MAIN_LIST} ")
	PACKAGE_LIST_DESKTOP=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST_DESKTOP} ")
fi

# Removing double spaces
# Do not quote the variables. This would defeat the trick.
PACKAGE_LIST="$(echo ${PACKAGE_LIST})"
PACKAGE_MAIN_LIST="$(echo ${PACKAGE_MAIN_LIST})"
PACKAGE_LIST_DESKTOP="$(echo ${PACKAGE_LIST_DESKTOP})"

display_alert "After removal of packages.remove packages"
display_alert "PACKAGE_MAIN_LIST : \"${PACKAGE_MAIN_LIST}\""
display_alert "PACKAGE_LIST : \"${PACKAGE_LIST}\""

# Give the option to configure DNS server used in the chroot during the build process
[[ -z $NAMESERVER ]] && NAMESERVER="1.0.0.1" # default is cloudflare alternate

# debug
cat <<-EOF >> "${DEST}"/debug/output.log

## BUILD SCRIPT ENVIRONMENT

Repository: $REPOSITORY_URL
Version: $REPOSITORY_COMMIT

Host OS: $(lsb_release -sc)
Host arch: $(dpkg --print-architecture)
Host system: $(uname -a)
Virtualization type: $(systemd-detect-virt)

## Build script directories
Build directory is located on:
$(findmnt -o TARGET,SOURCE,FSTYPE,AVAIL -T "${SRC}")

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

Partitioning configuration:
Root partition type: $ROOTFS_TYPE
Boot partition type: ${BOOTFS_TYPE:-(none)}
User provided boot partition size: ${BOOTSIZE:-0}
Offset: $OFFSET

CPU configuration:
$CPUMIN - $CPUMAX with $GOVERNOR
EOF
