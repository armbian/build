#!/bin/bash
#
# SPDX-License-Identifier:  GPL-2.0-only
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

function getboardtemp() {
	if [ -f /etc/armbianmonitor/datasources/soctemp ]; then
		read raw_temp </etc/armbianmonitor/datasources/soctemp 2>/dev/null
		if [ ! -z $(echo "$raw_temp" | grep -o "^[1-9][0-9]*\.\?[0-9]*$") ] && (( $(echo "${raw_temp} < 200" |bc -l) )); then
			# Allwinner legacy kernels output degree C
			board_temp=${raw_temp}
		else
			board_temp=$(awk '{printf("%d",$1/1000)}' <<<${raw_temp})
		fi
	elif [ -f /etc/armbianmonitor/datasources/pmictemp ]; then
		# fallback to PMIC temperature
		board_temp=$(awk '{printf("%d",$1/1000)}' </etc/armbianmonitor/datasources/pmictemp)
	fi
	# Some boards, such as the Orange Pi Zero LTS, report shifted CPU temperatures
	board_temp=$((board_temp + CPU_TEMP_OFFSET))
} # getboardtemp

function batteryinfo() {
	# Battery info for Allwinner
	mainline_dir="/sys/power/axp_pmu"
	legacy_dir="/sys/class/power_supply"
	if [[ -e "$mainline_dir" ]]; then
		read status_battery_connected < $mainline_dir/battery/connected 2>/dev/null
		if [[ "$status_battery_connected" == "1" ]]; then
			read status_battery_charging < $mainline_dir/charger/charging
			read status_ac_connect < $mainline_dir/ac/connected
			read battery_percent< $mainline_dir/battery/capacity
			# dispay charging / percentage
			if [[ "$status_ac_connect" == "1" && "$battery_percent" -lt "100" ]]; then
				status_battery_text=" charging"
			elif [[ "$status_ac_connect" == "1" && "$battery_percent" -eq "100" ]]; then
				status_battery_text=" charged"
			else
				status_battery_text=" discharging"
			fi
		fi
	elif [[ -e "$legacy_dir/axp813-ac" ]]; then
		read status_battery_connected < $legacy_dir/axp20x-battery/present
		if [[ "$status_battery_connected" == "1" ]]; then
			status_battery_text=" "$(awk '{print tolower($0)}' < $legacy_dir/axp20x-battery/status)
			read status_ac_connect < $legacy_dir/axp813-ac/present
			read battery_percent< $legacy_dir/axp20x-battery/capacity
		fi
	elif [[ -e "$legacy_dir/battery" ]]; then
		if [[ (("$(cat $legacy_dir/battery/voltage_now)" -gt "5" )) ]]; then
			status_battery_text=" "$(awk '{print tolower($0)}' < $legacy_dir/battery/status)
			read battery_percent <$legacy_dir/battery/capacity
		fi
	fi
} # batteryinfo

function ambienttemp() {
	# define where w1 usually shows up
	W1_DIR="/sys/devices/w1_bus_master1/"
	if [ -f /etc/armbianmonitor/datasources/ambienttemp ]; then
		read raw_temp </etc/armbianmonitor/datasources/ambienttemp 2>/dev/null
		amb_temp=$(awk '{printf("%d",$1/1000)}' <<<${raw_temp})
		echo $amb_temp
	elif [[ -d $W1_DIR && $ONE_WIRE == yes ]]; then
		device=$(ls -1 $W1_DIR | grep -E '^[0-9]{1,4}' | head -1)
		if [[ -n $device ]]; then
			read raw_temp < ${W1_DIR}${device}/hwmon/$(ls -1 ${W1_DIR}${device}/hwmon)/temp1_input 2>/dev/null
			amb_temp=$(awk '{printf("%d",$1/1000)}' <<<${raw_temp})
			echo $amb_temp
		fi
	else
		# read ambient temperature from USB device if available
		if [[ ! -f /usr/bin/temper ]]; then
			echo ""
			return
		fi
		amb_temp=$(temper -c 2>/dev/null)
		case ${amb_temp} in
			*"find the USB device"*)
				echo ""
				;;
			*)
				amb_temp=$(awk '{print $NF}' <<<$amb_temp |  sed 's/C//g')
				echo -n "scale=1;${amb_temp}/1" | grep -oE "\-?[[:digit:]]+\.[[:digit:]]"
		esac
	fi
} # ambienttemp
