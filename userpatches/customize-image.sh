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

## Install APT packets ######################################################################
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
#--------------------------------------------------------------------------------------------

## Add APT repository #######################################################################
# Nimbus repository
echo 'deb https://apt.status.im/nimbus all main' | tee /etc/apt/sources.list.d/nimbus.list
# Import the GPG key
curl https://apt.status.im/pubkey.asc -o /etc/apt/trusted.gpg.d/apt-status-im.asc

# Ethereum PPA for Geth
add-apt-repository -y ppa:ethereum/ethereum 

# Web3 Pi repository
# ToDo: separete repository for Web3 Pi Solo Staking?
wget -O - https://apt.web3pi.io/public-key.gpg | gpg --dearmor -o /etc/apt/keyrings/web3-pi-apt-repo.gpg
echo "deb [signed-by=/etc/apt/keyrings/web3-pi-apt-repo.gpg] https://apt.web3pi.io noble main restricted universe multiverse" | tee /etc/apt/sources.list.d/web3-pi.list

# Grafana repository
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list

apt-get update     # Update the package list to include the new repositories
#--------------------------------------------------------------------------------------------

## Install Ethereum clients #################################################################
apt-get install -y nimbus-beacon-node nimbus-validator-client ethereum
#--------------------------------------------------------------------------------------------

## Install InfluxDB #########################################################################
mkdir -p /opt/web3pi/influxdb
wget https://dl.influxdata.com/influxdb/releases/influxdb_1.8.10_arm64.deb -P /opt/web3pi/influxdb
dpkg -i /opt/web3pi/influxdb/influxdb_1.8.10_arm64.deb
sed -i "s|# flux-enabled =.*|flux-enabled = true|" /etc/influxdb/influxdb.conf
# note: configuration is in rc.local
systemctl enable influxdb
#--------------------------------------------------------------------------------------------

## Install Grafana ##########################################################################
apt-get -y install grafana
# Copy datasources.yaml for grafana
cp /tmp/overlay/grafana/yaml/datasources.yaml /etc/grafana/provisioning/datasources/datasources.yaml
# Copy dashboards.yaml for grafana
cp /tmp/overlay/grafana/yaml/dashboards.yaml /etc/grafana/provisioning/dashboards/dashboards.yaml
# Copy images for grafana
cp /tmp/overlay/grafana/img/*.png /usr/share/grafana/public/img/
# Copy custom dashboards
cp /tmp/overlay/grafana/dashboards/* /opt/web3pi/grafana/dashboards/
systemctl enable grafana-server
#--------------------------------------------------------------------------------------------

## Install Cockpit ##########################################################################
apt-get install -y cockpit cockpit-pcp cockpit-packagekit
#--------------------------------------------------------------------------------------------
