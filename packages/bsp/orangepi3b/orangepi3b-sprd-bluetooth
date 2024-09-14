#!/bin/bash

# only run this for boards with sprd bluetooth chip (i.e. v1.1 boards)
if [[ ! -d /proc/device-tree/sprd-mtty ]]; then
	systemctl disable orangepi3b-sprd-bluetooth.service

	exit 0
fi

modprobe -a sprdbt_tty sprdwl_ng
rfkill unblock all
/usr/bin/hciattach_opi -n -s 1500000 /dev/ttyBT0 sprd

exit 0
