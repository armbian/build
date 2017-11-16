#!/bin/bash

# TODO: convert this to use nmcli, improve network interfaces names handling (wl*, en*)
# or drop support for this and remove all related files

do_firstrun_automated_user_configuration()
{
	#-----------------------------------------------------------------------------
	#Notes:
	# - See /boot/armbian_first_run.txt for full list of available variables
	# - Variable names here must here must match ones in packages/bsp/armbian_first_run.txt.template

	#-----------------------------------------------------------------------------
	#Config FP
	local fp_config='/boot/armbian_first_run.txt'

	#-----------------------------------------------------------------------------
	#Grab user requested settings
	if [[ -f $fp_config ]]; then

		# Convert line endings to Unix from Dos
		sed -i $'s/\r$//' "$fp_config"

		# check syntax
		bash -n "$fp_config" || return

		# Load vars directly from file
		source "$fp_config"

		#-----------------------------------------------------------------------------
		# - Remove configuration file
		if [[ $FR_general_delete_this_file_after_completion == 1 ]]; then
			dd if=/dev/urandom of="$fp_config" bs=16K count=1
			sync
			rm "$fp_config"
		else
			mv "$fp_config" "${fp_config}.old"
		fi

		#-----------------------------------------------------------------------------
		# Set Network
		if [[ $FR_net_change_defaults == 1 ]]; then
			# - Get 1st index of available wlan and eth adapters
			local fp_ifconfig_tmp='/tmp/.ifconfig'
			ifconfig -a > "$fp_ifconfig_tmp" #export to file, should be quicker in loop than calling ifconfig each time.

			# find eth[0-9]
			for ((i=0; i<=9; i++))
			do
				if (( $(cat "$fp_ifconfig_tmp" | grep -ci -m1 "eth$i") )); then
					eth_index=$i
					break
				fi
			done

			# find wlan[0-9]
			for ((i=0; i<=9; i++))
			do
				if (( $(cat "$fp_ifconfig_tmp" | grep -ci -m1 "wlan$i") )); then
					wlan_index=$i
					break
				fi
			done

			rm "$fp_ifconfig_tmp"

			# - Kill dhclient
			killall -w dhclient

			# - Drop Connections
			ifdown eth$eth_index --force
			ifdown wlan$wlan_index --force

			# - Wifi enable
			if [[ $FR_net_wifi_enabled == 1 ]]; then

				#Enable Wlan, disable Eth
				FR_net_ethernet_enabled=0
				sed -i "/allow-hotplug wlan$wlan_index/c\allow-hotplug wlan$wlan_index" /etc/network/interfaces
				sed -i "/allow-hotplug eth$eth_index/c\#allow-hotplug eth$eth_index" /etc/network/interfaces

				#Set SSid (covers both WEP and WPA)
				sed -i "/wireless-essid /c\   wireless-essid $FR_net_wifi_ssid" /etc/network/interfaces
				sed -i "/wpa-ssid /c\   wpa-ssid $FR_net_wifi_ssid" /etc/network/interfaces

				#Set Key (covers both WEP and WPA)
				sed -i "/wireless-key /c\   wireless-key $FR_net_wifi_key" /etc/network/interfaces
				sed -i "/wpa-psk /c\   wpa-psk $FR_net_wifi_key" /etc/network/interfaces

				#Set wifi country code
				iw reg set "$FR_net_wifi_countrycode"

				#Disable powersaving for known chips that suffer from powersaving features causing connection dropouts.
				#	This is espically true for the 8192cu and 8188eu.
				#FOURDEE: This may be better located as default in ARMbian during build (eg: common), as currently, not active until after a reboot.
				# - Realtek | all use the same option, so create array.
				local realtek_array=(
					"8192cu"
					"8188eu"
				)

				for ((i=0; i<${#realtek_array[@]}; i++))
				do
					echo -e "options ${realtek_array[$i]} rtw_power_mgnt=0" > /etc/modprobe.d/realtek_"${realtek_array[$i]}".conf
				done

				unset realtek_array

			# - Ethernet enable
			elif [[ $FR_net_ethernet_enabled == 1 ]]; then

				#Enable Eth, disable Wlan
				FR_net_wifi_enabled=0
				sed -i "/allow-hotplug eth$eth_index/c\allow-hotplug eth$eth_index" /etc/network/interfaces
				#sed -i "/allow-hotplug wlan$wlan_index/c\#allow-hotplug wlan$wlan_index" /etc/network/interfaces

			fi

			# - Static IP enable
			if [[ $FR_net_use_static == 1 ]]; then
				if [[ $FR_net_wifi_enabled == 1 ]]; then
					sed -i "/iface wlan$wlan_index inet/c\iface wlan$wlan_index inet static" /etc/network/interfaces
				elif [[ $FR_net_ethernet_enabled == 1 ]]; then
					sed -i "/iface eth$eth_index inet/c\iface eth$eth_index inet static" /etc/network/interfaces
				fi

				#This will change both eth and wlan entries, however, as only 1 adapater is enabled by this feature, should be fine.
				sed -i "/^#address/c\address $FR_net_static_ip" /etc/network/interfaces
				sed -i "/^#netmask/c\netmask $FR_net_static_mask" /etc/network/interfaces
				sed -i "/^#gateway/c\gateway $FR_net_static_gateway" /etc/network/interfaces
				sed -i "/^#dns-nameservers/c\dns-nameservers $FR_net_static_dns" /etc/network/interfaces
			fi

			#This service should be executed before network is started, so don't restart anything

			# - Manually bring up adapters (just incase)
			if [[ $FR_net_wifi_enabled == 1 ]]; then
				ifup wlan$wlan_index
			elif [[ $FR_net_ethernet_enabled == 1 ]]; then
				ifup eth$eth_index
			fi
		fi
	fi
} #do_firstrun_automated_user_configuration

do_firstrun_automated_user_configuration

exit 0

