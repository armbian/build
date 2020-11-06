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
ROOTFS_CACHE_MAX=42 # max number of rootfs cache, older ones will be cleaned up

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
SDCARD="${SRC}/.tmp/rootfs-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}-${BUILD_MINIMAL}"
MOUNT="${SRC}/.tmp/mount-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}-${BUILD_MINIMAL}"
DESTIMG="${SRC}/.tmp/image-${BRANCH}-${BOARD}-${RELEASE}-${BUILD_DESKTOP}-${BUILD_MINIMAL}"

[[ ! -f ${SRC}/config/sources/families/$LINUXFAMILY.conf ]] && \
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source "${SRC}/config/sources/families/${LINUXFAMILY}.conf"

if [[ -f $USERPATCHES_PATH/sources/families/$LINUXFAMILY.conf ]]; then
	display_alert "Adding user provided $LINUXFAMILY overrides"
	source "$USERPATCHES_PATH/sources/families/${LINUXFAMILY}.conf"
fi

# load architecture defaults
source "${SRC}/config/sources/${ARCH}.conf"

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

if [[ $RELEASE == xenial || $RELEASE == bionic || $RELEASE == focal || $RELEASE == groovy ]]; then
		DISTRIBUTION="Ubuntu"
	else
		DISTRIBUTION="Debian"
fi

# Base system dependencies. Since adding MINIMAL_IMAGE we rely on "variant=minbase" which has very basic package set
DEBOOTSTRAP_LIST="locales gnupg ifupdown apt-utils apt-transport-https ca-certificates bzip2 console-setup cpio cron \
	dbus init initramfs-tools iputils-ping isc-dhcp-client kmod less libpam-systemd \
	linux-base logrotate netbase netcat-openbsd rsyslog systemd sudo ucf udev whiptail \
	wireless-regdb crda dmsetup rsync tzdata"

[[ $BUILD_DESKTOP == yes ]] && DEBOOTSTRAP_LIST+=" libgtk2.0-bin"

# tab cleanup is mandatory
DEBOOTSTRAP_LIST=$(echo $DEBOOTSTRAP_LIST | sed -e 's,\\[trn],,g')

# For minimal build different set of packages is needed
# Essential packages for minimal build
PACKAGE_LIST="bc cpufrequtils device-tree-compiler fping fake-hwclock psmisc chrony parted dialog \
		ncurses-term sysfsutils toilet figlet u-boot-tools usbutils openssh-server \
		nocache debconf-utils python3-apt"

[[ $ROOTFS_TYPE == xfs ]] && PACKAGE_LIST="$PACKAGE_LIST xfsprogs"

# Non-essential packages for minimal build
PACKAGE_LIST_ADDITIONAL="network-manager wireless-tools lsof htop mmc-utils wget nano sysstat net-tools resolvconf iozone3 jq libcrack2 cracklib-runtime curl"

if [[ "$BUILD_MINIMAL" != "yes"  ]]; then
	# Essential packages
	PACKAGE_LIST="$PACKAGE_LIST bridge-utils build-essential fbset \
		iw wpasupplicant sudo linux-base crda \
		wireless-regdb unattended-upgrades \
		console-setup unicode-data initramfs-tools \
		ca-certificates expect iptables automake html2text \
		bison flex libwrap0-dev libssl-dev libnl-3-dev libnl-genl-3-dev keyboard-configuration"


	# Non-essential packages
	PACKAGE_LIST_ADDITIONAL="$PACKAGE_LIST_ADDITIONAL alsa-utils btrfs-progs dosfstools iotop stress screen \
		ntfs-3g vim pciutils evtest pv libfuse2 libdigest-sha-perl \
		libproc-processtable-perl aptitude dnsutils f3 haveged hdparm rfkill vlan bash-completion \
		hostapd git ethtool unzip ifenslave libpam-systemd iperf3 \
		software-properties-common libnss-myhostname f2fs-tools avahi-autoipd iputils-arping qrencode sunxi-tools"
fi


# Dependent desktop packages
PACKAGE_LIST_DESKTOP="xserver-xorg xserver-xorg-video-fbdev gvfs-backends gvfs-fuse xfonts-base xinit \
	x11-xserver-utils xfce4 lxtask xfce4-terminal thunar-volman gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf \
	libgtk2.0-bin network-manager-gnome xfce4-notifyd gnome-keyring gcr libgck-1-0 p11-kit pasystray pavucontrol \
	pulseaudio pavumeter bluez bluez-tools pulseaudio-module-bluetooth blueman libpam-gnome-keyring \
	libgl1-mesa-dri policykit-1 profile-sync-daemon gnome-orca numix-gtk-theme synaptic apt-xapian-index lightdm lightdm-gtk-greeter"


# Recommended desktop packages
PACKAGE_LIST_DESKTOP_RECOMMENDS="galculator hexchat xfce4-screenshooter network-manager-openvpn-gnome mpv fbi \
	cups-pk-helper cups geany atril xarchiver"

# Full desktop packages
PACKAGE_LIST_DESKTOP_FULL="libreoffice libreoffice-style-breeze meld remmina kazam avahi-daemon transmission"

# Packages installed before desktop.
PACKAGE_LIST_PREDEPENDS=""

# Release specific packages
case $RELEASE in

	xenial)
		DEBOOTSTRAP_COMPONENTS="main"
		DEBOOTSTRAP_LIST+=" btrfs-tools"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db sysbench command-not-found selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" paman libgcr-3-common gcj-jre-headless paprefs numix-icon-theme libgnome2-perl \
								pulseaudio-module-gconf onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium-browser language-selector-gnome system-config-printer-common \
								system-config-printer-gnome leafpad mirage"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
	;;

	stretch)
		DEBOOTSTRAP_COMPONENTS="main"
		DEBOOTSTRAP_LIST+=" rng-tools"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr sysbench command-not-found selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" paman libgcr-3-common gcj-jre-headless paprefs dbus-x11 libgnome2-perl pulseaudio-module-gconf onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium system-config-printer-common system-config-printer leafpad mirage"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
	;;

	bionic)
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=" rng-tools fdisk"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr networkd-dispatcher command-not-found selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" xserver-xorg-input-all paprefs dbus-x11 libgnome2-perl pulseaudio-module-gconf onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium-browser system-config-printer-common system-config-printer \
								language-selector-gnome leafpad mirage"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
	;;

	buster)
		DEBOOTSTRAP_COMPONENTS="main"
		DEBOOTSTRAP_LIST+=" rng-tools fdisk"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr networkd-dispatcher command-not-found selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" paprefs dbus-x11 numix-icon-theme onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" chromium system-config-printer-common system-config-printer mirage"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
	;;

	bullseye)
		DEBOOTSTRAP_COMPONENTS="main"
		DEBOOTSTRAP_LIST+=" haveged fdisk"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr networkd-dispatcher command-not-found"
		PACKAGE_LIST_DESKTOP+=" paprefs dbus-x11 numix-icon-theme"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" firefox-esr system-config-printer-common system-config-printer"
		PACKAGE_LIST_DESKTOP_FULL+=""
	;;


	focal)
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=" rng-tools fdisk"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr networkd-dispatcher selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" xserver-xorg-input-all paprefs dbus-x11 pulseaudio-module-gsettings onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" firefox system-config-printer-common system-config-printer \
								language-selector-gnome viewnior"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
		PACKAGE_LIST_PREDEPENDS="policykit-1-gnome notification-daemon"
	;;

	groovy)
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=" rng-tools fdisk"
		[[ -z $BUILD_MINIMAL || $BUILD_MINIMAL == no ]] && PACKAGE_LIST_RELEASE="man-db kbd net-tools gnupg2 dirmngr networkd-dispatcher selinux-policy-default"
		PACKAGE_LIST_DESKTOP+=" xserver-xorg-input-all paprefs dbus-x11 pulseaudio-module-gsettings onboard"
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" firefox system-config-printer-common system-config-printer \
								language-selector-gnome mirage"
		PACKAGE_LIST_DESKTOP_FULL+=" thunderbird"
		PACKAGE_LIST_PREDEPENDS="policykit-1-gnome notification-daemon"
	;;

esac


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
$(getfacl -p "${SRC}"/.tmp 2> /dev/null)

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
