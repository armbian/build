#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

# Path to a file indicating that the operations have already been executed
INIT_FLAG_CUSTOMIZE_IMAGE_SH="/root/.customize-image.sh.firstrun.done"

## CHECKS ###################################################################################
# If the inode number for '/' differs from the real root, we are inside chroot
if [ "$(stat -c %i /)" != "$(stat -c %i /proc/1/root/.)" ]; then
    echo "Running in chroot environment."
else
    echo "Running on a regular host system."
    exit 0
fi

# Check if the script has already been run
if [ ! -f "$INIT_FLAG_CUSTOMIZE_IMAGE_SH" ]; then
    echo "Running customize-image.sh in chroot for the first time."
else
    echo "One-time tasks have already been completed. Skipping customize-image.sh."
    exit 0
fi
#--------------------------------------------------------------------------------------------

## Misc #####################################################################################
# ToDo: Setting hostname here doesn't work, probably overwritten later.
# hostname -b "w3p-staking-1"   # Set the hostname to w3p-staking-1
rm /root/.not_logged_in_yet     # Remove any first-login instructions
chmod +x /etc/update-motd.d/*   # Enable motd
mkdir -p /opt/web3pi            # Create the web3pi directory
#--------------------------------------------------------------------------------------------

## rc.local #################################################################################
# Add rc.local file and rc-local.service
cp /tmp/overlay/rc.local /etc/rc.local
chmod +x /etc/rc.local
cp /tmp/overlay/rc-local.service /etc/systemd/system/rc-local.service
systemctl enable rc-local.service
#--------------------------------------------------------------------------------------------

## Add install.sh ###########################################################################
cp /tmp/overlay/install.sh /opt/web3pi/.install.sh     # Copy the install script to /opt/web3pi
chmod +x /opt/web3pi/.install.sh
#--------------------------------------------------------------------------------------------

## install APT packets ######################################################################
# ToDo: cleanup unnecessary packages
apt update
apt install -y neofetch software-properties-common apt-utils chrony avahi-daemon git-extras python3-pip python3-netifaces flashrom iw python3-dev libpython3.12-dev python3.12-venv 
apt install -y bpytop iotop screen bpytop ccze nvme-cli jq git speedtest-cli file vim net-tools telnet apt-transport-https figlet
apt install -y gcc jq git libraspberrypi-bin iotop screen bpytop ccze nvme-cli speedtest-cli ufw
#--------------------------------------------------------------------------------------------

## UFW (firewall) ###########################################################################
apt install -y ufw
# ToDo: set up firewall rules

# ufw allow 22/tcp comment "SSH"
# ufw --force enable
#----------------------------------------------------------------------------------------