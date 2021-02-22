#!/bin/sh

#7.0V 	916 	Recommended threshold to force shutdown system
TH=916

val=$(cat '/sys/bus/iio/devices/iio:device0/in_voltage2_raw')
sca=$(cat '/sys/bus/iio/devices/iio:device0/in_voltage_scale')
adc=$(echo "$val * $sca / 1" | bc)

if [ "$adc" -le $TH ]; then
	/usr/sbin/poweroff
fi
