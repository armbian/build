#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

# Downgrade kernel to 4.14 because 4.19 is causing issues with Wifi drivers so far
apt install linux-image-next-sunxi=5.67 -y --allow-downgrades || exit -1
apt-mark hold linux-image-next-sunxi

# We don't want the damn network-manager :/
apt remove network-manager -y || true
apt autoremove -y
cat << EOF >> /etc/apt/preferences
Package: network-manager
Pin: release *
Pin-Priority: -1
EOF
echo "auto eth0" > /etc/network/interfaces.d/eth0.conf
echo "iface eth0 inet dhcp" >> /etc/network/interfaces.d/eth0.conf

# Backports are evil
sed -i '/backport/ s/^deb/#deb/' /etc/apt/sources.list

# resolvconf stuff
rm /etc/resolv.conf
ln -s /etc/resolvconf/run/resolv.conf /etc/resolv.conf

# Avahi and mysql/mariadb needs to do some stuff which conflicts with the
# "change the root password asap" so we disable it temporarily....
chage -d 99999999 root

# Run the install script
curl https://install.yunohost.org/stretch | bash -s -- -a
rm /var/log/yunohost-installation*

# Override the first login script with our own (we don't care about desktop
# stuff + we don't want the user to manually create a user)
rm /etc/profile.d/armbian-check-first-login.sh
cp /tmp/overlay/check_first_login.sh /etc/profile.d/check_first_login.sh
cp /tmp/overlay/check_yunohost_is_installed.sh /etc/profile.d/check_yunohost_is_installed.sh
cp /tmp/overlay/armbian-motd /etc/default/armbian-motd
dpkg-divert --divert /root/armbian-check-first-login.sh --rename /etc/profile.d/armbian-check-first-login.sh
dpkg-divert --divert /root/armbian-motd --rename /etc/default/armbian-motd
touch /root/.not_logged_in_yet

# Clean stuff
chage -d 0 root
apt clean
