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

Main() {
    case $RELEASE in
        jessie)
            ;;
        stretch)
            InstallYunohostStretch
            ;;
    esac
} # Main

InstallYunohostStretch()
{
    # Override the first login script with our own (we don't care about desktop
    # stuff + we don't want the user to manually create a user)
    cp /tmp/overlay/check_first_login.sh /etc/profile.d/check_first_login.sh

    # Avahi and mysql/mariadb needs to do some stuff which conflicts with the
    # "change the root password asap" so we disable it temporarily....
    chage -d 99999999 root

    # Go to tmp and run the install script
    cd /tmp/
    wget -O install_yunohost https://install.yunohost.org/stretch
    chmod +x /tmp/install_yunohost
    ./install_yunohost -a

    chage -d 0 root

    # FIXME !!! Should clean stuff here (c.f. clean_image in script)
    apt clean
}

Main "$@"
