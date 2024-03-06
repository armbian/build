#!/bin/bash

cmdline=$(cat /proc/cmdline)

if [[ $cmdline == *'bt_mac='* ]]; then
    bt_mac=$(echo $cmdline | grep -o 'bt_mac=[^ ]*' | cut -d'=' -f2)
else
    bt_mac="2C:6D:C1:F1:93:32"
fi

/usr/bin/bluetoothctl mgmt.public-addr $bt_mac
