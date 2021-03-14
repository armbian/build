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

set -e

# Import variable from env file
source /tmp/overlay/image_env.sh

# Disable core dumps because hostname keep crashing in qemu static
ulimit -c 0

if [[ $BOARD == "lime2" ]]
then
    # Freeze armbian/kernel version
    # because current version break dhcp on eth0
    # (since around ~November 2020 ?)

    apt install -y --allow-downgrades \
        armbian-firmware=20.08.17 \
        linux-buster-root-current-lime2=20.08.17 \
        linux-dtb-current-sunxi=20.08.14 \
        linux-image-current-sunxi=20.08.14 \
        linux-u-boot-lime2-current=20.08.13 \
    || exit 1

    apt-mark hold armbian-firmware
    apt-mark hold linux-buster-root-current-lime2
    apt-mark hold linux-dtb-current-sunxi
    apt-mark hold linux-image-current-sunxi
    apt-mark hold linux-u-boot-lime2-current
fi

echo "auto eth0" > /etc/network/interfaces.d/eth0.conf
echo "allow-hotplug eth0" >> /etc/network/interfaces.d/eth0.conf
echo "iface eth0 inet dhcp" >> /etc/network/interfaces.d/eth0.conf
# TODO Use RFC4862 with maybe a local-link prefix
echo " post-up ip a a fe80::42:acab/128 dev eth0" >> /etc/network/interfaces.d/eth0.conf

# Disable those damn supposedly "predictive" interface names
# c.f. https://unix.stackexchange.com/a/338730
ln -s /dev/null /etc/systemd/network/99-default.link

# Prevent dhcp setting the "search" thing in /etc/resolv.conf, leads to many
# weird stuff (e.g. with numericable) where any domain will ping >.>
echo 'supersede domain-name "";'   >> /etc/dhcp/dhclient.conf
echo 'supersede domain-search "";' >> /etc/dhcp/dhclient.conf
echo 'supersede search "";       ' >> /etc/dhcp/dhclient.conf

# Backports are evil
sed -i '/backport/ s/^deb/#deb/' /etc/apt/sources.list

# Avahi and mysql/mariadb needs to do some stuff which conflicts with
# the "change the root password asap" so we disable it. In fact, now
# that YunoHost 3.3 syncs the password with admin password at
# postinstall we are happy with not triggering a password change at
# first boot.  Assuming that ARM-boards won't be exposed to global
# network right after booting the first time ...
chage -d 99999999 root

# Run the install script
wget https://install.yunohost.org/buster -O /tmp/yunohost_install_script
bash /tmp/yunohost_install_script -a -d $YNH_BUILDER_BRANCH
[[ -e /etc/yunohost ]] || exit 1
rm -f /var/log/yunohost-installation*

if [[ $YNH_BUILDER_INSTALL_INTERNETCUBE == "yes" ]]
then
    cp -r /tmp/overlay/install_internetcube /var/www/install_internetcube
    pushd /var/www/install_internetcube/
    source deploy/deploy.sh
    popd
fi

# Override the first login script with our own (we don't care about desktop
# stuff + we don't want the user to manually create a user)
cp /tmp/overlay/check_yunohost_is_installed.sh /etc/profile.d/check_yunohost_is_installed.sh
dpkg-divert --divert /root/armbian-check-first-login.sh --rename /etc/profile.d/armbian-check-first-login.sh
dpkg-divert --divert /root/armbian-motd --rename /etc/default/armbian-motd
rm -f /etc/profile.d/armbian-check-first-login.sh
cp /tmp/overlay/check_first_login.sh /etc/profile.d/check_first_login.sh
cp /tmp/overlay/armbian-motd /etc/default/armbian-motd
touch /root/.not_logged_in_yet

# Make sure resolv.conf points to DNSmasq
# (somehow networkmanager or something else breaks this before...)
rm -f /etc/resolv.conf
ln -s /etc/resolvconf/run/resolv.conf /etc/resolv.conf

# Get the yunohost version for naming the .img
apt-cache policy yunohost | grep -Po 'Installed: \K.+' > /tmp/overlay/yunohost_version

# Clean stuff
apt clean
