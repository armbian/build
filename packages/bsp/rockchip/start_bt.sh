#!/bin/bash

GPIO_CONFIGURED_CHECK_DIRECTORY="/var/run/rtk_bt" 
GPIO_CONFIGURED_CHECK_FILE="/var/run/rtk_bt/gpio_configured"

function die_on_error {
	if [ ! $? = 0 ]; then
		echo $1
		exit 1
	fi
}

# Kill any rtk_hciattach actually running.
# Do not complain if we didn't kill anything.
killall -q -SIGTERM rtk_hciattach

# If the GPIO are not yet configured 
if [ ! -f "$GPIO_CONFIGURED_CHECK_FILE" ];
then
	# We'll create the directory first
	# So that, if the user is not root
	# he'll get a user permission error
	mkdir -p "$GPIO_CONFIGURED_CHECK_DIRECTORY" || die_on_error "Could not create$GPIO_CONFIGURED_CHECK_DIRECTORY"

	echo 146 > /sys/class/gpio/export
	echo 149 > /sys/class/gpio/export
	echo 151 > /sys/class/gpio/export
	echo high > /sys/class/gpio/gpio146/direction
	echo high > /sys/class/gpio/gpio149/direction
	echo high > /sys/class/gpio/gpio151/direction

	echo 1 > $GPIO_CONFIGURED_CHECK_FILE || die_on_error "Could not write to $GPIO_CONFIGURED_CHECK_FILE !"
fi

# If you run the rtk_hciattach once
# you cannot run it again before`
# resetting the device.
# Since resetting the device before
# the first launch generates no issue,
# we always reset the device.

echo "Resetting the Bluetooth chip"
echo 0 > /sys/class/gpio/gpio149/value &&
echo -e "\tBluetooth chip power down..." && 
sleep 1 &&
echo 1 > /sys/class/gpio/gpio149/value &&
echo -e "\tBluetooth chip power up..." &&
sleep 1
echo -e "\tResetting done"

/usr/bin/rtk_hciattach -n -s 115200 /dev/ttyS0 rtk_h5 || die_on_error "Could not create hci0 through rtk_hciattach"
