#!/bin/bash

mac="$(echo $(cat /etc/machine-id; echo bluetooth)| sha256sum -)"
bt_mac=$(echo "42:${mac:0:2}:${mac:4:2}:${mac:8:2}:${mac:12:2}:${mac:16:2}")
echo $bt_mac
/usr/bin/bluetoothctl mgmt.public-addr $bt_mac
