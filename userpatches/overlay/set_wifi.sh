#!/bin/bash

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot


Main() {
  read -p "WiFi SSID: " ssid_net
  read -p "WiFi Password: " ssid_pwd
  sed -i "s/ssid=[\"]*[\"]/ssid=[\"]$ssid_net[\"]/" ../etc/wpa_supplicant/wpa_supplicant.conf
  sed -i "s/psk=[\"]*[\"]/psk=[\"]$ssid_pwd[\"]/" ../etc/wpa_supplicant/wpa_supplicant.conf
} #Main
