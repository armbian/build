#!/bin/bash

function die_on_error {
	if [ ! $? = 0 ]; then
		echo $1
		exit 1
	fi
}


# Kill any rtk_brcm_patchram_plus actually running.
# Do not complain if we didn't kill anything.
killall -q -SIGTERM rock_brcm_patchram_plus

echo "We must stop getty now, You must physically disconnect your USB-UART-Adapter!"
systemctl stop serial-getty@ttyS0 || die_on_error "Could not stop getty"

echo "Using /dev/ttyS0 for Bluetooth"

echo "Power cycle rockpi BT-section"
rfkill block bluetooth
sleep 2
rfkill unblock bluetooth
echo "Start uploader"

/usr/bin/rock_brcm_patchram_plus --enable_hci --no2bytes --use_baudrate_for_download  --tosleep 20000 --baudrate 1500000 --patchram /lib/firmware/brcm/BCM4345C5.hcd /dev/ttyS0 &
