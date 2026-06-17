#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

ARMBIAN_SUITE="bookworm"
DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
ARMBIAN_MIRROR="http://apt.armbian.com"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <kernel_version> <desktop_environment> [username] [password] [boot_mode]"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then exit 1; fi

KERNEL=$1
DESKTOP_ENV=$2
CUSTOM_USER=${3:-xiaomi}
CUSTOM_PASS=${4:-123456}
BOOT_MODE=${5:-dual}

if [ "$BOOT_MODE" = "single" ]; then
    ROOT_PART="userdata"
    IMG_SUFFIX="singleboot"
else
    ROOT_PART="linux"
    IMG_SUFFIX="dualboot"
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="armbian_${ARMBIAN_SUITE}_${DESKTOP_ENV}_${IMG_SUFFIX}_${TIMESTAMP}.img"

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# Base system bootstrap
debootstrap --arch=arm64 "$ARMBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# DNS configuration
rm -f rootdir/etc/resolv.conf
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > rootdir/etc/resolv.conf

# Repositories configuration
printf "deb %s %s main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$ARMBIAN_SUITE" > rootdir/etc/sources.list
printf "deb %s %s-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$ARMBIAN_SUITE" >> rootdir/etc/sources.list
printf "deb %s-security %s-security main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$ARMBIAN_SUITE" >> rootdir/etc/sources.list

mkdir -p rootdir/usr/share/keyrings
wget -qO- https://apt.armbian.com/armbian.key | gpg --dearmor > rootdir/usr/share/keyrings/armbian.gpg
printf "deb [signed-by=/usr/share/keyrings/armbian.gpg] %s %s main %s-utils %s-desktop\n" "$ARMBIAN_MIRROR" "$ARMBIAN_SUITE" "$ARMBIAN_SUITE" "$ARMBIAN_SUITE" > rootdir/etc/sources.list.d/armbian.list

chroot rootdir apt update

# Install Armbian core packages
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl network-manager openssh-server \
    wpasupplicant dbus kmod initramfs-tools armbian-config armbian-zram-config

# Install local driver packages
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
    KERNEL_MODULE_DIR=$(ls rootdir/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        chroot rootdir /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir locale-gen en_US.UTF-8 || true
chroot rootdir bash -c "echo 'root:$CUSTOM_PASS' | chpasswd"
echo "armbian-${DESKTOP_ENV}" > rootdir/etc/hostname

# Install desktop environment
DM=""
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot rootdir apt install -y --no-install-recommends xorg gdm3 gnome-shell gnome-terminal firefox-esr
    DM="gdm3"
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot rootdir apt install -y --no-install-recommends xorg sddm plasma-desktop konsole firefox-esr
    DM="sddm"
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot rootdir apt install -y --no-install-recommends xorg lightdm xfce4 xfce4-terminal lightdm-gtk-greeter firefox-esr
    DM="lightdm"
fi

# Add default user
chroot rootdir useradd -m -s /bin/bash "$CUSTOM_USER"
echo "$CUSTOM_USER:$CUSTOM_PASS" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev "$CUSTOM_USER"

# TTY and network system configurations
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
chroot rootdir systemctl enable systemd-resolved ssh
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# Hardware specific configurations
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

FW_DIR="rootdir/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"; fi
chroot rootdir apt install -y qrtr-tools || true
chroot rootdir systemctl enable qrtr-ns || true

# Autologin setup
if [ -n "$DM" ]; then
    if [ "$DM" = "gdm3" ]; then
        mkdir -p rootdir/etc/gdm3
        printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$CUSTOM_USER\n" > rootdir/etc/gdm3/daemon.conf
        chroot rootdir systemctl enable gdm3
    elif [ "$DM" = "sddm" ]; then
        mkdir -p rootdir/etc/sddm.conf.d
        printf "[General]\nDisplayServer=x11\nInputMethod=\n" > rootdir/etc/sddm.conf.d/armbian-defaults.conf
        printf "[Autologin]\nUser=$CUSTOM_USER\nSession=plasma\n" > rootdir/etc/sddm.conf.d/autologin.conf
        chroot rootdir systemctl enable sddm
    elif [ "$DM" = "lightdm" ]; then
        mkdir -p rootdir/etc/lightdm/lightdm.conf.d
        printf "[Seat:*]\nautologin-user=$CUSTOM_USER\nautologin-user-timeout=0\n" > rootdir/etc/lightdm/lightdm.conf.d/autologin.conf
        chroot rootdir systemctl enable lightdm
    fi
    chroot rootdir systemctl set-default graphical.target
else
    chroot rootdir systemctl set-default multi-user.target
fi

# Filesystem mount mapping
printf "PARTLABEL=%s / ext4 defaults,noatime,errors=remount-ro 0 1\n" "$ROOT_PART" > rootdir/etc/fstab

# Cleanup and package image
chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true; umount rootdir/dev || true; umount rootdir/proc || true; umount rootdir/sys || true; umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
7z a "armbian_${ARMBIAN_SUITE}_${DESKTOP_ENV}_${IMG_SUFFIX}_${TIMESTAMP}.7z" "$SPARSE_IMG"
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
