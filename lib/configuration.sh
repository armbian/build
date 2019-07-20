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
if [[ $BETA == yes && -z $SUBREVISION ]]; then SUBREVISION="."$(date --date="tomorrow" +"%y%m%d"); fi
REVISION=$(cat ${SRC}/VERSION)"$SUBREVISION" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
[[ -z $MAINTAINER ]] && MAINTAINER="Igor Pecovnik" # deb signature
[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
TZDATA=$(cat /etc/timezone) # Timezone for target is taken from host or defined here.
USEALLCORES=yes # Use all CPU cores for compiling
EXIT_PATCHING_ERROR="" # exit patching if failed
HOST="$(echo "$BOARD" | cut -f1 -d-)" # set hostname to the board
ROOTFSCACHE_VERSION=4
CHROOT_CACHE_VERSION=6
BUILD_REPOSITORY_URL=$(git remote get-url $(git remote 2>/dev/null) 2>/dev/null)
BUILD_REPOSITORY_COMMIT=$(git describe --match=d_e_a_d_b_e_e_f --always --dirty 2>/dev/null)
ROOTFS_CACHE_MAX=16 # max number of rootfs cache, older ones will be cleaned up

# TODO: fixed name can't be used for parallel image building
ROOT_MAPPER="armbian-root"

[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
[[ "ext4 f2fs btrfs nfs fel" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

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
SERIALCON=ttyS0
CAN_BUILD_STRETCH=yes
[[ -z $CRYPTROOT_SSH_UNLOCK ]] && CRYPTROOT_SSH_UNLOCK=yes
[[ -z $CRYPTROOT_SSH_UNLOCK_PORT ]] && CRYPTROOT_SSH_UNLOCK_PORT=2022
[[ -z $WIREGUARD ]] && WIREGUARD="no"
[[ -z $EXTRAWIFI ]] && EXTRAWIFI="yes"

# single ext4 partition is the default and preferred configuration
#BOOTFS_TYPE=''

# set unique mounting directory
SDCARD="${SRC}/.tmp/rootfs-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"
MOUNT="${SRC}/.tmp/mount-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"
DESTIMG="${SRC}/.tmp/image-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"

[[ ! -f ${SRC}/config/sources/$LINUXFAMILY.conf ]] && \
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source "${SRC}/config/sources/${LINUXFAMILY}.conf"

if [[ -f $USERPATCHES_PATH/sources/$LINUXFAMILY.conf ]]; then
	display_alert "Adding user provided $LINUXFAMILY overrides"
	source "$USERPATCHES_PATH/sources/${LINUXFAMILY}.conf"
fi

# dropbear needs to be configured differently
[[ $CRYPTROOT_ENABLE == yes && ($RELEASE == jessie || $RELEASE == xenial) ]] && exit_with_error "Encrypted rootfs is not supported in Jessie or Xenial"

[[ $RELEASE == stretch && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Debian Stretch images with selected kernel is not supported"
[[ $RELEASE == bionic && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Ubuntu Bionic images with selected kernel is not supported"
[[ $RELEASE == bionic && $(lsb_release -sc) == xenial ]] && exit_with_error "Building Ubuntu Bionic images requires a Bionic build host. Please upgrade your host or select a different target OS"

[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

case $ARCH in
	arm64)
	[[ -z $KERNEL_COMPILER ]] && KERNEL_COMPILER="aarch64-linux-gnu-"
	[[ -z $UBOOT_COMPILER ]] && UBOOT_COMPILER="aarch64-linux-gnu-"
	ATF_COMPILER="aarch64-linux-gnu-"
	[[ -z $INITRD_ARCH ]] && INITRD_ARCH=arm64
	QEMU_BINARY="qemu-aarch64-static"
	ARCHITECTURE=arm64
	;;

	armhf)
	[[ -z $KERNEL_COMPILER ]] && KERNEL_COMPILER="arm-linux-gnueabihf-"
	[[ -z $UBOOT_COMPILER ]] && UBOOT_COMPILER="arm-linux-gnueabihf-"
	[[ -z $INITRD_ARCH ]] && INITRD_ARCH=arm
	QEMU_BINARY="qemu-arm-static"
	ARCHITECTURE=arm
	;;
esac

BOOTCONFIG_VAR_NAME=BOOTCONFIG_${BRANCH^^}
[[ -n ${!BOOTCONFIG_VAR_NAME} ]] && BOOTCONFIG=${!BOOTCONFIG_VAR_NAME}
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
[[ -z $BOOTPATCHDIR ]] && BOOTPATCHDIR="u-boot-$LINUXFAMILY"
[[ -z $KERNELPATCHDIR ]] && KERNELPATCHDIR="$LINUXFAMILY-$BRANCH"

if [[ $RELEASE == xenial || $RELEASE == bionic || $RELEASE == disco ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

# Base system dependencies
DEBOOTSTRAP_LIST="locales,gnupg,ifupdown,apt-transport-https,ca-certificates"
[[ $BUILD_DESKTOP == yes ]] && DEBOOTSTRAP_LIST+=",libgtk2.0-bin"

# Essential packages
PACKAGE_LIST="bc bridge-utils build-essential cpufrequtils device-tree-compiler figlet fbset fping \
	iw fake-hwclock wpasupplicant psmisc ntp parted rsync sudo curl linux-base dialog crda \
	wireless-regdb ncurses-term python3-apt sysfsutils toilet u-boot-tools unattended-upgrades \
	usbutils wireless-tools console-setup unicode-data openssh-server initramfs-tools \
	ca-certificates resolvconf expect iptables automake nocache debconf-utils html2text \
	bison flex libwrap0-dev libssl-dev libnl-3-dev libnl-genl-3-dev"


# Non-essential packages
PACKAGE_LIST_ADDITIONAL="armbian-firmware alsa-utils btrfs-tools dosfstools iotop iozone3 stress screen \
	ntfs-3g vim pciutils evtest htop pv lsof libfuse2 libdigest-sha-perl \
	libproc-processtable-perl aptitude dnsutils f3 haveged hdparm rfkill vlan sysstat bash-completion \
	hostapd git ethtool network-manager unzip ifenslave command-not-found libpam-systemd iperf3 \
	software-properties-common libnss-myhostname f2fs-tools avahi-autoipd iputils-arping qrencode mmc-utils sunxi-tools"


# Dependent desktop packages
PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-video-fbdev gvfs-backends gvfs-fuse xfonts-base xinit \
	x11-xserver-utils xfce4 lxtask xfce4-terminal thunar-volman gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf \
	libgtk2.0-bin network-manager-gnome xfce4-notifyd gnome-keyring gcr libgck-1-0 p11-kit pasystray pavucontrol \
	pulseaudio pavumeter bluez bluez-tools pulseaudio-module-bluetooth blueman libpam-gnome-keyring \
	libgl1-mesa-dri policykit-1 profile-sync-daemon gnome-orca numix-gtk-theme synaptic onboard lightdm lightdm-gtk-greeter"


# Recommended desktop packages
PACKAGE_LIST_DESKTOP_RECOMMENDS="mirage galculator hexchat xfce4-screenshooter network-manager-openvpn-gnome mpv fbi cups-pk-helper \
	cups geany atril xarchiver"


# For minimal build different set of packages is needed
if [[ $BUILD_MINIMAL == yes  ]]; then

	# Essential packages for minimal build
	PACKAGE_LIST="bc cpufrequtils device-tree-compiler fping \
		fake-hwclock psmisc ntp parted sudo linux-base dialog \
		ncurses-term sysfsutils toilet u-boot-tools unattended-upgrades \
		usbutils console-setup openssh-server initramfs-tools \
		ca-certificates resolvconf iptables nocache debconf-utils"

	# Non-essential packages for minimal build
	PACKAGE_LIST_ADDITIONAL="autofs cron lsof htop overlayroot vim mmc-utils sunxi-tools"

	# Dependent desktop packages for minimal build
	PACKAGE_LIST_DESKTOP=""

	# Recommended desktop packages for minimal build
	PACKAGE_LIST_DESKTOP_RECOMMENDS=""

fi

# Release specific packages
case $RELEASE in

	jessie)
		DEBOOTSTRAP_COMPONENTS="main"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="less kbd gnupg2 dirmngr sysbench"
		PACKAGE_LIST_DESKTOP+=" paman libgcr-3-common gcj-jre-headless policykit-1-gnome eject numix-icon-theme libgnome2-perl pulseaudio-module-gconf"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" iceweasel pluma system-config-printer leafpad"
	;;

	xenial)
		DEBOOTSTRAP_COMPONENTS="main"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db wget nano sysbench"
		PACKAGE_LIST_DESKTOP+=" paman libgcr-3-common gcj-jre-headless paprefs numix-icon-theme libgnome2-perl pulseaudio-module-gconf"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium-browser language-selector-gnome system-config-printer-common system-config-printer-gnome leafpad"
	;;

	stretch)
		DEBOOTSTRAP_COMPONENTS="main"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db less kbd net-tools netcat-openbsd gnupg2 dirmngr sysbench"
		PACKAGE_LIST_DESKTOP+=" paman libgcr-3-common gcj-jre-headless paprefs dbus-x11 libgnome2-perl pulseaudio-module-gconf"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium system-config-printer-common system-config-printer leafpad"
	;;

	bionic)
		DEBOOTSTRAP_COMPONENTS="main,universe"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db less kbd net-tools netcat-openbsd gnupg2 dirmngr nano wget"
		PACKAGE_LIST_DESKTOP+=" xserver-xorg-input-all paprefs dbus-x11 libgnome2-perl pulseaudio-module-gconf"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium-browser system-config-printer-common system-config-printer language-selector-gnome leafpad"
	;;

	buster)
		DEBOOTSTRAP_COMPONENTS="main"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db less kbd net-tools netcat-openbsd gnupg2 dirmngr wget"
		PACKAGE_LIST_DESKTOP+=" paprefs dbus-x11 numix-icon-theme"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium system-config-printer-common system-config-printer"
	;;

	disco)
		DEBOOTSTRAP_COMPONENTS="main,universe"
		[[ $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db less kbd net-tools netcat-openbsd gnupg2 dirmngr nano wget"
		PACKAGE_LIST_DESKTOP+=" xserver-xorg-input-all paprefs dbus-x11 pulseaudio-module-gsettings"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium-browser system-config-printer-common system-config-printer language-selector-gnome"
		# temp disable
		PACKAGE_LIST_ADDITIONAL="${PACKAGE_LIST_ADDITIONAL/armbian-firmware /}"
	;;

esac


DEBIAN_MIRROR='httpredir.debian.org/debian'
UBUNTU_MIRROR='ports.ubuntu.com/'

if [[ $DOWNLOAD_MIRROR == china ]] ; then
	DEBIAN_MIRROR='mirrors.tuna.tsinghua.edu.cn/debian'
	UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/'
fi

# For user override
if [[ -f $USERPATCHES_PATH/lib.config ]]; then
	display_alert "Using user configuration override" "userpatches/lib.config" "info"
	source "$USERPATCHES_PATH"/lib.config
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
#if [[ $ARCH == arm64 ]]; then
	#PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP/iceweasel/iceweasel:armhf}"
	#PACKAGE_LIST_DESKTOP="${PACKAGE_LIST_DESKTOP/thunderbird/thunderbird:armhf}"
#fi
[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP $PACKAGE_LIST_DESKTOP_RECOMMENDS"

# remove any packages defined in PACKAGE_LIST_RM in lib.config
if [[ -n $PACKAGE_LIST_RM ]]; then
	PACKAGE_LIST=$(sed -r "s/\b($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\b//g" <<< "${PACKAGE_LIST}")
fi

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
$(getfacl -p "${SRC}"/.tmp)

## BUILD CONFIGURATION

Build target:
Board: $BOARD
Branch: $BRANCH
Minimal: $BUILD_MINIMAL
Desktop: $BUILD_DESKTOP

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
