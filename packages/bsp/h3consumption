#!/bin/bash
#
# h3consumption
#
# This tool patches fex/script.bin, adds commands to /etc/rc.local and
# adjusts /etc/defaults/cpufrequtils to control board consumption. Works
# only with H3 devices running legacy kernel.
#
#############################################################################
#
# Background information:
#
# By controlling a few settings energy consumption of H3 boards can be
# influenced:
#
# - disabling GPU/HDMI on headless devices: 210 mW less idle consumption
#   (memory bandwidth also increases so performance will slightly improve)
# 
# - negotiate only Fast Ethernet on GbE devices: 370 mW less idle consumption
#
# - switch off Ethernet on Fast Ethernet devices: 200 mW less idle consumption
# 
# - limit max cpufreq: does not affect idle consumption but peak/full load
#   (using 912 mhz on NanoPi M1/NEO or Orange Pi One/Lite will prevent VDD_CPU
#   switching to the higher voltage and therfore greatly reduce consumption
#   with only a slight decrease in maximum performance)
# 
# - limit count of active cpu cores: low impact on idle consumption, high on
#   peak/full load consumption
# 
# - lower DRAM clockspeed to 408 MHz: 150 mW less idle consumption
# 
# - disabling all USB ports (it's only 'all or nothing'): 125 mW less idle
#
# Please be aware that WiFi might add significantly to consumption. Since there
# are too many possible configurations (USB WiFi dongles also considered and
# possibilities to tweak power management settings with individual WiFi chips)
# h3consumption does not adjust WiFi settings -- only the -p switch lists
# configured WiFi devices.
# 
# In case you don't need WiFi on the H3 boards with onboard WiFi adjust
# /etc/modules and comment the WiFi module out (8189es, 8189fs or bcmdhd).
# Please keep also in mind that you can control networking consumption also 
# on a 'on demand' basis. In case you use a H3 board as data logger and need
# WiFi only for a short time every 24 hours, disabling WiFi and only enabling
# it for data transfers will save you between 300 and 1000 mW with 8189FTV as 
# used on Orange Pi Lite, PC Plus or Plus 2E for example:
#
# ifconfig wlan0 down && rmmod -f 8189fs / modprobe 8189fs && sleep 0.5 && ifconfig wlan0 up
#
# Same with the Gigabit Ethernet equipped H3 boards: switching there to Fast
# Ethernet when no high speed transfers are needed saves a whopping 370 mW
# (and the same will happen on the switch's side if a more modern Gbit switch
# is in use):
#
# ethtool -s eth0 speed 100 duplex full / ethtool -s eth0 speed 1000 duplex full
#
# More information (and discussion in case questions arise!) in Armbian forum:
# https://forum.armbian.com/index.php/topic/1614-running-h3-boards-with-minimal-consumption/
# https://forum.armbian.com/index.php/topic/1748-sbc-consumptionperformance-comparisons/
# https://forum.armbian.com/index.php/topic/1823-opi-pc-wireless-not-powering-off/
#
#############################################################################
#
# CHANGES:
#
# v0.1: Initial release
#
#############################################################################
#
# TODO:
# 
# - Write documentation as nicely as it's done for h3disp
# - Allow higher DRAM clock in fex file than set from /etc/rc.local
# - Add revert mode, relinking original fex/bin and restore all original
#   settings
#
#############################################################################

Main() {
	export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	
	# ensure script is running as root
	if [ "$(id -u)" != "0" ]; then
	        echo "This script must be executed as root. Exiting" >&2
	        exit 1
	fi

	# check installation
	CheckInstallation

	if [ $# -eq 0 ]; then
		DisplayUsage ; exit 0
	else
		FexSettings="$(mktemp /tmp/${0##*/}.XXXXXX)"
		RCLocalContents="$(mktemp /tmp/${0##*/}.XXXXXX)"
		ReadSettings
		ParseOptions "$@"
		ChangeSettings
		FinalizeSettings
	fi
	
	echo -e "Settings changed. Please reboot for changes to take effect\nand verify settings after the reboot using \"${0##*/} -p\""
	
	# Let's see whether we have to collect debug output
	case ${Debug} in
		TRUE)
			which curl >/dev/null 2>&1 || apt-get -f -qq -y install curl
			echo -e "\nDebug output has been collected at the following URL: \c"
			(cat "${DebugOutput}"; echo -e "\n\n\nfex contents:\n" ; cat "${MyTmpFile}") \
				| curl -F 'sprunge=<-' http://sprunge.us
			;;
	esac
} # Main

CheckInstallation() {
	# check if tool can rely on Armbian environment
	if [ ! -f /etc/armbian.txt ]; then
		echo -e "Error. This tool requires an Armbian installation. Exiting." >&2
		exit 1
	fi
	
	# check platform and kernel
	case $(uname -r) in
		3.4.*)
			HARDWARE=$(awk '/Hardware/ {print $3}' </proc/cpuinfo)
			if [ "X${HARDWARE}" != "Xsun8i" ]; then
				echo "This tool works only on H3 devices. Exiting." >&2
				exit 1
			fi
			;;
		*)
			echo "This tool requires legacy kernel on H3 devices. Exiting." >&2
			exit 1
			;;
	esac
	
	# ensure ethtool is installed
	which ethtool >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo -e "\nPlease be patient, external requirements are to be installed.\n"
		apt-get -f -qq -y install ethtool >/dev/null 2>&1
	fi
} # CheckInstallation

ParseOptions() {
	while getopts 'hHvVpPe:E:m:M:c:C:d:D:u:U:g:G:w:W:' c ; do
	case ${c} in
		H)
			export FullUsage=TRUE
			DisplayUsage
			exit 0
			;;
		h)
			DisplayUsage
			exit 0
			;;
		v|V)
			# Increase verbosity. Will try to upload debug output from script
			# to ease reporting of bugs or strange behaviour. Use only when 
			# asked for.
			export Debug=TRUE
			DebugOutput="$(mktemp /tmp/${0##*/}.XXXXXX)"
			trap "rm \"${DebugOutput}\" ; exit 0" 0 1 2 3 15
			set -x
			exec 2>"${DebugOutput}"
			;;
		e|E)
			# Ethernet: either none, fast or gbit
			Ethernet=$(echo -n ${OPTARG} | tr '[:upper:]' '[:lower:]')
			;;
		g|G)
			# GPU/HDMI: either on or off
			GPUHDMI=$(echo -n ${OPTARG} | tr '[:upper:]' '[:lower:]')
			;;
		m|M)
			# maximum allowed cpu clockspeed
			MaxClockspeed=$(echo -n ${OPTARG} | tr -d -c '[:digit:]')
			;;
		c|C)
			# count of cpu cores: 1 - 4
			CPUCores=$(echo -n ${OPTARG} | tr -d -c '[:digit:]')
			;;
		d)
			# dram clockspeed: 408 - 624 mhz
			DRAMLowerLimit=408
			DramClockspeed=$(echo -n ${OPTARG} | tr -d -c '[:digit:]')
			;;
		D)
			# dram clockspeed: 132 - 624 mhz
			DRAMLowerLimit=132
			DramClockspeed=$(echo -n ${OPTARG} | tr -d -c '[:digit:]')
			;;
		u|U)
			# All USB ports on or off
			USBUsed=$(echo -n ${OPTARG} | tr '[:upper:]' '[:lower:]')
			;;
		p|P)
			# print active settings
			PrintActiveSettings
			exit 0
			;;
		w|W)
			# Wi-Fi powermanagement
			WiFi=$(echo -n ${OPTARG} | tr '[:upper:]' '[:lower:]')
			;;
	esac
	done
} # ParseOptions

ChangeSettings() {
	# Ethernet
	case ${Ethernet} in
		"")
			: ;;
		fast)
			echo 'ethtool -s eth0 speed 100 duplex full' >>"${RCLocalContents}"
			;;
		on)
			BOARD=$(awk -F"=" '/^BOARD=/ {print $2}' </etc/armbian-release)
			if [ "X${BOARD}" = "X" ]; then
				echo "Armbian installation too old, please apt-get upgrade before. Exiting." >&2
				exit 1
			else
				OrigSettings=$(bin2fex /boot/bin/${BOARD}.bin 2>/dev/null | awk -F" " '/^gmac_used/ {print $3}')
				sed -i -e "s/^gmac_used\ =\ 0/gmac_used = ${OrigSettings}/g" "${FexSettings}"
			fi
			;;
		off)
			sed -i -e 's/^gmac_used\ =\ \(.*\)/gmac_used = 0/g' "${FexSettings}"
			;;
		*)
			echo "Parameter error: -e requires either on, fast or off. Exiting" >&2
			exit 1
			;;
	esac

	# Wi-Fi powermanagement
	case ${WiFi} in
		"")
			: ;;
		on)
			rm -f /etc/NetworkManager/dispatcher.d/99enable-power-management \
				/etc/NetworkManager/dispatcher.d/99disable-power-management \
				/etc/NetworkManager/conf.d/zz-override-wifi-powersave-off.conf

			;;
		off)
			rm -f /etc/NetworkManager/dispatcher.d/99enable-power-management \
				/etc/NetworkManager/dispatcher.d/99disable-power-management \
				/etc/NetworkManager/conf.d/zz-override-wifi-powersave-off.conf

			echo "Note: This action applies only to NetworkManager based connections"

			case "$(lsb_release -sc)" in
			jessie)
				mkdir -p /etc/NetworkManager/dispatcher.d/
				cat <<-'EOF' > /etc/NetworkManager/dispatcher.d/99disable-power-management
				#!/bin/sh
				case "$2" in
					up) /sbin/iwconfig $1 power off || true ;;
					down) /sbin/iwconfig $1 power on || true ;;
				esac
				EOF
				chmod 755 /etc/NetworkManager/dispatcher.d/99disable-power-management
				;;
			xenial)
				mkdir -p /etc/NetworkManager/conf.d/
				cat <<-EOF > /etc/NetworkManager/conf.d/zz-override-wifi-powersave-off.conf
				[connection]
				wifi.powersave = 2
				EOF
				;;
			*)
				echo "This action is supported only in Jessie and Xenial based releases. Exiting" >&2
				exit 1
				;;
			esac
			;;
		*)
			echo "Parameter error: -w requires either on or off. Exiting" >&2
			exit 1
			;;
	esac

	# Maximum cpu clock in mhz
	case ${MaxClockspeed} in
		"")
			: ;;
		*)	
			HardwareUpperLimit=$(awk -F" " '/^max_freq = / {print $3 / 1000000}' <"${FexSettings}")
			HardwareLowerLimit=$(awk -F" " '/^min_freq = / {print $3 / 1000000}' <"${FexSettings}")
			if [ ${MaxClockspeed} -lt ${HardwareLowerLimit} ]; then
				# adjust to lowest allowed clockspeed
				sed -i "s/MAX_SPEED=\(.*\)/MAX_SPEED=${HardwareLowerLimit}000/" /etc/default/cpufrequtils
			elif [ ${MaxClockspeed} -gt ${HardwareUpperLimit} ]; then
				# adjust to highest allowed clockspeed
				sed -i "s/MAX_SPEED=\(.*\)/MAX_SPEED=${HardwareUpperLimit}000/" /etc/default/cpufrequtils
			else
				# check cpufreq since not every value is possible
				for i in $(awk -F" " '{print $1}' </sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state | sed 's/000$//') ; do
					if [ $i -ge ${MaxClockspeed} ]; then
						sed -i "s/MAX_SPEED=\(.*\)/MAX_SPEED=${i}000/" /etc/default/cpufrequtils
						break
					fi
				done
			fi
			
		;;
	esac
	
	# dram clockspeed in mhz
	case ${DramClockspeed} in
		"")
			: ;;
		*)
			BOARD=$(awk -F"=" '/^BOARD=/ {print $2}' </etc/armbian-release)
			case ${BOARD} in
				nanopineo|nanopiair)
					HardwareUpperLimit=432
					;;
				*)
					HardwareUpperLimit=624
					;;
			esac
			if [ ${DramClockspeed} -lt ${DRAMLowerLimit} ]; then
				# adjust to lowest allowed clockspeed
				DramClockspeed=${DRAMLowerLimit}
			elif [ ${DramClockspeed} -gt ${HardwareUpperLimit} ]; then
				# adjust to highest allowed clockspeed
				DramClockspeed=${HardwareUpperLimit}
			else
				# round dramfreq since not every value is possible: between 132 and 384 mhz
				# 12 mhz steps are possible, above 24 mhz steps
				if [ ${DramClockspeed} -le 384 ]; then
					RoundedValue=$(( ${DramClockspeed} / 12 ))
					DramClockspeed=$(( ${RoundedValue} * 12 ))
				else
					RoundedValue=$(( ${DramClockspeed} / 24 ))
					DramClockspeed=$(( ${RoundedValue} * 24 ))
				fi
			fi
			echo "echo ${DramClockspeed}000 >/sys/devices/platform/sunxi-ddrfreq/devfreq/sunxi-ddrfreq/userspace/set_freq" \
				>>"${RCLocalContents}"
			sed -i "s/dram_clk\ =\ \(.*\)/dram_clk = ${DramClockspeed}/" "${FexSettings}"
		;;
	esac
	
	# Active CPU cores
	case ${CPUCores} in
		""|4)
			# enable corekeeper
			sed -i -e 's/^corekeeper_enabled\ =\ 0/corekeeper_enabled = 1/g' "${FexSettings}"
			echo "# All CPU cores active" >>"${RCLocalContents}"
			;;
		3)
			# disable corekeeper and 1 core in /etc/rc.local
			sed -i -e 's/^corekeeper_enabled\ =\ 1/corekeeper_enabled = 0/g' "${FexSettings}"
			echo "echo 0 >/sys/devices/system/cpu/cpu\3/online" >>"${RCLocalContents}"
			;;
		2)
			# disable corekeeper and 2 cores in /etc/rc.local
			sed -i -e 's/^corekeeper_enabled\ =\ 1/corekeeper_enabled = 0/g' "${FexSettings}"
			echo "for i in 3 2; do echo 0 >/sys/devices/system/cpu/cpu\${i}/online; done" >>"${RCLocalContents}"
			;;
		1)
			# disable corekeeper and 3 cores in /etc/rc.local
			sed -i -e 's/^corekeeper_enabled\ =\ 1/corekeeper_enabled = 0/g' "${FexSettings}"
			echo "for i in 3 2 1; do echo 0 >/sys/devices/system/cpu/cpu\${i}/online; done" >>"${RCLocalContents}"
			;;
		*)
			echo "Parameter error: -c requires 1, 2, 3 or 4. Exiting" >&2
			exit 1
			;;
	esac

	# GPU/HDMI
	case ${GPUHDMI} in
		"")
			: ;;
		on)
			sed -i -e 's/^hdmi_used\ =\ 0/hdmi_used = 1/' \
				-e 's/^mali_used\ =\ 0/mali_used = 1/' \
				-e 's/^disp_init_enable\ =\ 0/disp_init_enable = 1/' "${FexSettings}"
			;;
		off)
			sed -i -e 's/^hdmi_used\ =\ 1/hdmi_used = 0/' \
				-e 's/^mali_used\ =\ 1/mali_used = 0/' \
				-e 's/^disp_init_enable\ =\ 1/disp_init_enable = 0/' "${FexSettings}"
			;;
		*)
			echo "Parameter error: -g requires either on or off. Exiting" >&2
			exit 1
			;;
	esac

	# USB
	case ${USBUsed} in
		"")
			: ;;
		on)
			sed -i -e 's/^usb_used\ =\ 0/usb_used = 1/g' "${FexSettings}"
			;;
		off)
			sed -i -e 's/^usb_used\ =\ 1/usb_used = 0/g' "${FexSettings}"
			;;
		*)
			echo "Parameter error: -u requires either on or off. Exiting" >&2
			exit 1
			;;
		esac
} # ChangeSettings

PrintActiveSettings() {
	# function that prints the active consumption relevant settings
	# cpu settings
	echo -e "Active settings:\n"
	HardwareLimit=$(awk -F" " '/^max_freq = / {print $3 / 1000000}' <"${FexSettings}")
	SoftwareLimit=$(awk -F"=" '/^MAX_SPEED/ {print $2 / 1000}' </etc/default/cpufrequtils)
	CountOfActiveCores=$(grep -c '^processor' /proc/cpuinfo)
	echo -e "cpu       ${SoftwareLimit} mhz allowed, ${HardwareLimit} mhz possible, ${CountOfActiveCores} cores active\n"
	# dram settings
	echo -e "dram      $(sed 's/000$//' </sys/devices/platform/sunxi-ddrfreq/devfreq/sunxi-ddrfreq/cur_freq) mhz\n"
	# display active or headless mode
	echo -e "hdmi/gpu  $(awk -F" " '/^hdmi_used/ {print $3}' <"${FexSettings}" | head -n 1 | sed -e 's/1/active/' -e 's/0/off/')\n"
	# USB ports active or disabled
	echo -e "usb ports $(awk -F" " '/^usb_used/ {print $3}' <"${FexSettings}" | head -n 1 | sed -e 's/1/active/' -e 's/0/off/')\n"
	# network
	ethtool eth0 >/dev/null 2>&1 && echo -e "eth0      $(ethtool eth0 | grep -E "Speed|Link d|Duplex" | tr "\n" " " | awk '{print $2"/"$4", Link: "$7}')\n"
	ListOfWiFis=$(iwconfig 2>&1 | grep -Ev "lo|tunl0|eth0" | grep -v "^ " | awk -F" " '{print $1}')
	for i in ${ListOfWiFis} ; do
		iwconfig $i
	done
} # PrintActiveSettings

DisplayUsage() {
	# check if stdout is a terminal...
	if test -t 1; then
		# see if it supports colors...
		ncolors=$(tput colors)
		if test -n "$ncolors" && test $ncolors -ge 8; then
			BOLD="$(tput bold)"
			NC='\033[0m' # No Color
			LGREEN='\033[1;32m'
		fi
	fi
	echo -e "Usage: ${BOLD}${0##*/} [-h/-H] [-p] [-g on|off] [-m max_cpufreq] [-c 1|2|3|4]\n       [-d dram_freq] [-D dram_freq] [-u on|off] [-e on|off|fast] ${NC}\n"
	echo -e "############################################################################"
	if [ ${FullUsage} ]; then
		echo -e "\nDetailed Description:"
		grep "^#" "$0" | grep -v "^#\!/bin/bash" | sed 's/^#//'
	fi
	echo -e "\n This tool allows to adjust a few consumption relevant settings of your\n H3 device. Use the following switches\n"
	echo -e " ${BOLD}-h|-H${NC}           displays help or verbose help text"
	echo -e " ${BOLD}-p${NC}              print currently active settings"
	echo -e " ${BOLD}-g on|off${NC}       disables GPU/HDMI for headless use"
	echo -e " ${BOLD}-m max_cpufreq${NC}  adjusts maximum allowed cpu clockspeed (mhz)"
	echo -e " ${BOLD}-c 1|2|3|4${NC}      activate only this count of CPU cores"
	echo -e " ${BOLD}-d dram_freq${NC}    adjusts dram clockspeed (408 - 624 mhz)"
	echo -e " ${BOLD}-D dram_freq${NC}    like -d but as low as 132 mhz possible (experimental!)"
	echo -e " ${BOLD}-u on|off${NC}       enables/disabled all USB ports"
	echo -e " ${BOLD}-e on|off|fast${NC}  enables/disables Ethernet, the fast switch\n                 forces 100 mbits/sec negotiation on gigabit devices"
	echo -e " ${BOLD}-w on|off${NC}       enables/disables Wi-Fi powermanagement when interface\n                 supports this and is controlled by network-manager\n"
	echo -e "############################################################################\n"
} # DisplayUsage

ReadSettings() {
	# This function parses script.bin and install needed tools if necessary

	# check whether we've the necessary tools available
	Fex2Bin="$(which fex2bin)"
	if [ "X${Fex2Bin}" = "X" ]; then
	        apt-get -f -qq -y install sunxi-tools >/dev/null 2>&1 || InstallSunxiTools >/dev/null 2>&1
	fi
	which fex2bin >/dev/null 2>&1 || (echo -e "Aborted\nfex2bin/bin2fex not found and unable to install. Exiting" >&2 ; exit 1)
	
	# convert script.bin to temporary fex file	
	bin2fex /boot/script.bin "${FexSettings}" >/dev/null 2>&1
} # ReadSettings

FinalizeSettings() {
	# convert modified fex file back to script.bin, modify /etc/rc.local

	# create copy and backup to be able to recover from failed conversion
	cd /boot
	if [ -L script.bin ]; then
		Original="$(readlink -f script.bin)" && (rm script.bin ; cp -p "${Original}" script.bin)
	fi
	cp -p script.bin script.bin.bak
	
	fex2bin "${FexSettings}" /boot/script.bin 2>/dev/null
	if [ $? -ne 0 ]; then
	        mv /boot/script.bin.bak /boot/script.bin
	        echo -e "Aborted\nWriting script.bin went wrong. Nothing changed." >&2
	        logger "Writing script.bin went wrong. Nothing changed"
	        exit 1
	fi
	
	if [ -s "${RCLocalContents}" ];then
		# Adjust /etc/rc.local contents if necessary, first create clean file without h3consumption
		# additions
		grep -Ev "exit\s*0|h3consumption|sun8i-corekeeper" /etc/rc.local | sed '/^\s*$/d' >"${FexSettings}"
		echo -e "\n### do NOT edit the following lines, always use h3consumption instead ###" >>"${FexSettings}"
		cat "${RCLocalContents}" | while read ; do
			echo -e "${REPLY} # h3consumption" >>"${FexSettings}"
		done
		echo -e "\nexit 0" >>"${FexSettings}"
		cat "${FexSettings}" >/etc/rc.local
		rm "${RCLocalContents}"
	fi
	rm "${FexSettings}" 
} # FinalizeSettings

InstallSunxiTools() {
	sleep 1
	apt-get -f -qq -y install libusb-1.0-0-dev || (echo -e "Aborted\nNot possible to install a sunxi-tools requirement" ; exit 1)
	cd /tmp
	git clone https://github.com/linux-sunxi/sunxi-tools
	cd sunxi-tools
	make
	make install
} # InstallSunxiTools

Main "$@"
