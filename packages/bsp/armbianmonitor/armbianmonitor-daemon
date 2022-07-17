#!/bin/bash
#
# armbianmonitor-daemon
#
# This script relies on information gathered in armhwinfo. It
# calls armhwinfo in query mode and relies then on the exported
# variables: HARDWARE ARCH KERNELID MACHINE ID VERSION
#
# The purpose is to create an environment for rpimonitord so that 
# relevant hardware informations can be monitored easily. This 
# script starts uses configuration files in /etc/armbianmonitor/,
# collects data sources below /etc/armbianmonitor/datasources/ and
# adjusts templates for RPi-Monitor on the fly. Only if the file
# /etc/armbianmonitor/start-monitoring exists this script relinks
# /etc/rpimonitor/data.conf and starts rpimonitord if not already
# running.
#
# In case the script detects that not all necessary data sources
# are available through sysfs it will act as a daemon to collect
# data on its own and to write it to the approriate file. As an
# example the SoC's temperature: Running on an AXP209 based board 
# the script will check /sys/class/thermal/thermal_zone0/temp and
# if existing link it to /etc/armbianmonitor/datasources/soctemp.
# In case it does not exist the script will create a normal file
# at this location and writes the thermal value to it using the 
# sunxi_axp209_temp binary in an endless loop.
#
# At least the following files/symlinks will be provided below
# /etc/armbianmonitor/datasources/ depending on SoC/PMIC in question:
#
# soctemp (SoC's internal temp in degree Celsius * 1000)
# pmictemp (PMIC's internal temp in degree Celsius * 1000)
# ac_voltage (DC-IN voltage in V * 1000000)
# usb_voltage (USB OTG voltage in V * 1000000)
# battery_voltage (battery voltage in V * 1000000)
# ac_current (DC-IN current in A * 1000000)
# usb_current (USB OTG current in A * 1000000)
# battery_current (battery current in A * 1000000)
#
# When extended debugging has been chosen (using _armbian-monitoring_
# this can be configured. Then /etc/armbianmonitor/start-monitoring
# contains DEBUG) this script will also provide a few more files:
#
# cpustat (cpu_stat,system_stat,user_stat,nice_stat,iowait_stat,irq_stat
#          collected through /proc/cpustat in daemon mode)
# cpu_count (number of active CPU cores)
# vcorevoltage (Vcore in V * 1000 based on sysfs or script.bin/.dtb)
#
# Disk monitoring: For configured disks the following parameters can be
# monitored: temperature, S.M.A.R.T. health, load cycle count and CRC
# errors indicating connection/cable problems. The config file used is
# /etc/armbianmonitoring/disks.conf
#
# Filesystem monitoring: In /etc/armbianmonitoring/filesystems.conf
# mountpoints and trigger values can be defined that will be used to
# create the template stuff for these fs at startup of this script.
#
# The behaviour of this script can be configured through another tool
# called armbian-monitoring. The latter will also check for connected 
# disks, get their name and GUID and let the user choose whether the
# disk should be monitored or not. The information has to be stored in
# /etc/armbianmonitor/disks.conf relying on the GUIDs of the disks.

 # define some variables:
CheckInterval=7.5      # time in seconds between two checks
DiskCheckInterval=60   # time in seconds between disk checks

Main() {
	PreRequisits
	
	case ${BOARD_NAME} in
		Cubieboard|Cubietruck|Orange|"Lamobo R1"|"Lime 2"|Lime|"Banana Pi"|Micro|"Banana Pi"|"Banana Pi Pro")
			DealWithAXP209
			;;
		"Banana M2")
			DealWithNewBoard
			# DealWithAXP221
			;;
		"Cubietruck Plus"|"Banana Pi M3"|"pcDuino8 Uno")
			DealWithNewBoard
			# DealWithAXP818
			;;
		Guitar|"Roseapple Pi")
			DealWithNewBoard
			# DealWithS500
			;;
		"Odroid XU4"|"Odroid XU3")
			DealWithNewBoard
			# DealWithExynos4
			;;
		"Odroid C1")
			DealWithNewBoard
			# DealWithS805
			;;
		Clearfog|"Turris Omnia")
			DealWithNewBoard
			# DealWithArmada38x
			;;
		"Cubox i4"|"HB i2eX"|"Cubox i2eX"|"HB i1"|"HB i2"|"Wandboard")
			DealWithNewBoard
			# DealWithiMX6
			;;
		"Orange Pi PC"|"Orange Pi Plus"|"Orange Pi 2"|"Orange Pi One"|"Orange Pi Lite")
			DealWithNewBoard
			# DealWithH3
			;;
		Geekbox)
			DealWithNewBoard
			# DealWithRK3368
			;;
		*)
			# No templates exist now. Combine sane defaults with some guessing
			DealWithNewBoard
			;;
	esac
	
	# Create the Armbian templates
	CreateTemplates

	exit 0
	
	# Decide depending on existence of /etc/armbianmonitor/start-monitoring
	ShouldMonitoringBeStarted
	
	# Provide missing data in daemon mode
	LoopEndlessly
} # Main

LoopEndlessly() {
	while true ; do
		# get VCore
		read CPUFreq </sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
		GetVCore ${CPUFreq} >/tmp/VCore

		# check disk temperature(s). We execute this only every ${DiskCheckInterval} since 
		# it's a bit costly (S.M.A.R.T. queries). 
		TimeNow=$(( $(date "+%s") / ${DiskCheckInterval} ))
		if [[ ${TimeNow} -gt ${LastDiskCheck} ]]; then
			# time for a disk check. If ${CheckAllDisks} is FALSE and /dev/sda exists we
			# only query this device otherwise all available (might be none)
			CheckDisks
			# update check timestamp
			LastDiskCheck=${TimeNow}
		fi

		# External temperature from weather stations
		# TimeNow=$(( $(date "+%s") / ${TempCheckInterval} ))
		# if [[ ${TimeNow} -gt ${LastTempCheck} ]]; then
			# read in external temp values from 2 different web sources
			# ExternalTemp=$(GetExternalTemp)
			# LastExternalTemp=$(SanitizeValue ${ExternalTemp} ${LastExternalTemp} | tee /tmp/externaltemp)
			# LastTempCheck=${TimeNow}
		# fi
		
		# cpustat
		TimeNow=$(( $(date "+%s") / ${CpuStatCheckInterval} ))
		if [[ ${TimeNow} -gt ${LastCpuStatCheck} ]]; then
			ProcessStats
			LastCpuStatCheck=${TimeNow}
		fi
		sleep ${CheckInterval}
	done
} # LoopEndlessly

CheckDisks() {
	# To be done based on new /etc/armbianmonitoring/disks.conf config file
	:
} # CheckDisks

DealWithAXP209() {
	# check existence of sysfs nodes
	if [ -f /sys/devices/virtual/thermal/thermal_zone0/temp ]; then
		ln -fs /sys/devices/virtual/thermal/thermal_zone0/temp /etc/armbianmonitor/datasources/soctemp
	else
		if [ -L /etc/armbianmonitor/datasources/soctemp ]; then
			rm -f /etc/armbianmonitor/datasources/soctemp
		fi
		echo -n 25000 >/etc/armbianmonitor/datasources/soctemp
		export GetSoCTemp="${ARCH}-${BOARD_NAME}"
	fi
	if [ -d /sys/devices/platform/soc@01c00000/1c2ac00.i2c/i2c-0/0-0034 ]; then
		# mainline kernel and 'axp209 mainline sysfs interface' patch applied
		ln -fs /sys/power/axp_pmu/ac/voltage /etc/armbianmonitor/datasources/ac_voltage
		ln -fs /sys/power/axp_pmu/ac/amperage /etc/armbianmonitor/datasources/ac_current
		ln -fs /sys/power/axp_pmu/vbus/voltage /etc/armbianmonitor/datasources/usb_voltage
		ln -fs /sys/power/axp_pmu/vbus/amperage /etc/armbianmonitor/datasources/usb_current
		ln -fs /sys/power/axp_pmu/battery/voltage /etc/armbianmonitor/datasources/battery_voltage
		ln -fs /sys/power/axp_pmu/battery/amperage /etc/armbianmonitor/datasources/battery_current
		ln -fs /sys/power/axp_pmu/pmu/temp /etc/armbianmonitor/datasources/pmictemp
		ln -fs /sys/power/axp_pmu/battery/capacity /etc/armbianmonitor/datasources/battery_percent
		ln -fs /sys/power/axp_pmu/battery/charging /etc/armbianmonitor/datasources/battery_charging
		ln -fs /sys/power/axp_pmu/charger/amperage /etc/armbianmonitor/datasources/charger_current
		ln -fs /sys/power/axp_pmu/battery/connected /etc/armbianmonitor/datasources/battery_connected
		ln -fs /sys/power/axp_pmu/battery/charge /etc/armbianmonitor/datasources/battery_charge
	fi
	if [ -d /sys/devices/platform/sunxi-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply ]; then
		# sunxi 3.4 kernel
		SysFSPrefix=/sys/devices/platform/sunxi-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply
		ln -fs "${SysFSPrefix}"/ac/voltage_now /etc/armbianmonitor/datasources/ac_voltage
		ln -fs "${SysFSPrefix}"/ac/current_now /etc/armbianmonitor/datasources/ac_current
		ln -fs "${SysFSPrefix}"/usb/voltage_now /etc/armbianmonitor/datasources/usb_voltage
		ln -fs "${SysFSPrefix}"/usb/current_now /etc/armbianmonitor/datasources/usb_current
		ln -fs "${SysFSPrefix}"/battery/voltage_now /etc/armbianmonitor/datasources/battery_voltage
		ln -fs "${SysFSPrefix}"/battery/current_now /etc/armbianmonitor/datasources/battery_current
		ln -fs /sys/devices/platform/sunxi-i2c.0/i2c-0/0-0034/temp1_input /etc/armbianmonitor/datasources/pmictemp
		ln -fs /sys/class/power_supply/battery/capacity /etc/armbianmonitor/datasources/battery_percent
		ln -fs /sys/class/power_supply/battery/charging /etc/armbianmonitor/datasources/battery_charging
		ln -fs /sys/class/power_supply/battery/connected /etc/armbianmonitor/datasources/battery_connected
		ln -fs /sys/class/power_supply/battery/charge /etc/armbianmonitor/datasources/battery_charge
	fi
	# relink template
	if [ "X${DebugMode}" = "XDEBUG" ]; then
		ln -sf /etc/armbianmonitor/templates/axp209_template_debug.conf /etc/armbianmonitor/templates/cpu_pmic.conf
	else
		ln -sf /etc/armbianmonitor/templates/axp209_template.conf /etc/armbianmonitor/templates/cpu_pmic.conf
	fi
} # DealWithAXP209

DealWithNewBoard() {
	# check existence of sysfs nodes
	if [ -f /sys/devices/virtual/thermal/thermal_zone0/temp ]; then
		ln -fs /sys/devices/virtual/thermal/thermal_zone0/temp /etc/armbianmonitor/datasources/soctemp
	elif [ -f /sys/devices/virtual/thermal/thermal_zone1/temp ]; then
		ln -fs /sys/devices/virtual/thermal/thermal_zone1/temp /etc/armbianmonitor/datasources/soctemp
	fi
	# relink template
	if [ "X${DebugMode}" = "XDEBUG" ]; then
		ln -sf /etc/armbianmonitor/templates/unknown_board_template_debug.conf /etc/armbianmonitor/templates/cpu_pmic.conf
	else
		ln -sf /etc/armbianmonitor/templates/unknown_board_template.conf /etc/armbianmonitor/templates/cpu_pmic.conf
	fi
} # DealWithNewBoard

CreateTemplates() {
	# check whether templates we write aren't symlinks to somewhere else
	for i in armbian.conf uptime.conf version.conf ; do
		if [ -L /etc/armbianmonitor/templates/${i} ]; then
			rm /etc/armbianmonitor/templates/${i}
			touch /etc/armbianmonitor/templates/${i}
			chmod 711 /etc/armbianmonitor/templates/${i}
		fi
	done

	# check whether our logo is available
	if [ ! -f /usr/share/rpimonitor/web/img/armbian.png ]; then
		if [ -L /usr/share/rpimonitor/web/img/armbian.png ]; then
			rm /usr/share/rpimonitor/web/img/armbian.png
		fi
		cp -p /etc/armbianmonitor/templates/armbian.png /usr/share/rpimonitor/web/img/
	fi
	
	# create main template
	echo "web.page.icon='img/armbian.png'
web.page.menutitle='RPi-Monitor  <sub>('+data.hostname+')</sub>'
web.page.pagetitle='RPi-Monitor ('+data.hostname+')'
web.status.1.name=$BOARD_NAME
web.statistics.1.name=$BOARD_NAME
web.addons.1.name=Addons
web.addons.1.addons=about
include=/etc/armbianmonitor/templates/version.conf
include=/etc/armbianmonitor/templates/uptime.conf
include=/etc/armbianmonitor/templates/cpu_pmic.conf
include=/etc/rpimonitor/template/memory.conf" >/etc/armbianmonitor/armbian.conf
	
	# remove firmware line in version info:
	grep -v "Firmware" /etc/rpimonitor/template/version.conf | sed 's|line.5|line.4|' >/etc/armbianmonitor/templates/version.conf	
	
	# uptime template with correct machine name:
	sed "s/Raspberry Pi/$ID/" < /etc/rpimonitor/template/uptime.conf >/etc/armbianmonitor/templates/uptime.conf

	# check swap settings. In case we're using swap then add template
	HowManySwapDevices=$(swapon -s | wc -l)
	if [[ ${HowManySwapDevices} -gt 1 ]]; then
		echo "include=/etc/rpimonitor/template/swap.conf" >>/etc/armbianmonitor/armbian.conf
	fi
	
	echo "include=/etc/armbianmonitor/template/filesystems.conf
include=/etc/armbianmonitor/template/disks.conf
include=/etc/rpimonitor/template/network.conf" >>/etc/armbianmonitor/armbian.conf

	UpdateFileSystems
	UpdateDisks
} #

UpdateFileSystems() {
	# Generates /etc/armbianmonitor/template/filesystems.conf dynamically
	# based on the contents of /etc/armbianmonitoring/filesystems.conf
	
	# if not existing, create config file with single entry for /
	if [ ! -f /etc/armbianmonitoring/filesystems.conf ]; then
		echo '/' >/etc/armbianmonitoring/filesystems.conf
		chmod 711 /etc/armbianmonitoring/filesystems.conf
	fi
	
	# Update template:
	
} # UpdateFileSystems

UpdateDisks() {
	# Generates /etc/armbianmonitor/template/disks.conf dynamically
	# based on the contents of /etc/armbianmonitor/disks.conf. The
	# current mapping between GUIDs and /dev/sd* nodes will be stored
	# in /etc/armbianmonitor/datasources/disk-by-guid
	
	# ensure lookup file is empty:
	if [ -L /etc/armbianmonitor/datasources/disk-by-guid ]; then
		rm -f /etc/armbianmonitor/datasources/disk-by-guid
	fi	
	echo -n "" >/etc/armbianmonitor/datasources/disk-by-guid
	chmod 711 /etc/armbianmonitor/datasources/disk-by-guid
	
	OIFS=${IFS}
	IFS=:
	cat /etc/armbianmonitor/disks.conf | while read ; do
		IFS=:
		set ${REPLY}
		GUID="$1"
		DiskName="$2"
		SMARTPrefix="$3"
		TempCommand="$4"
		CRCAttribute="$5"
		LCCAttribute="$6"
		IFS=${OIFS}
		
		# try to resolve device node (when not present, then disk's
		# not mounted -- we then create the entry without device node)
		DeviceNode="$(ResolveGUID ${GUID})"
		echo -e "${GUID}\t${DiskName}\t${DeviceNode}" >>/etc/armbianmonitor/datasources/disk-by-guid

		# create template stuff for every listed disk
		:
	done
	IFS=${OIFS}
} # UpdateDisks

ResolveGUID() {
	# function that will be supplied with a GUID and returns the device node, eg.
	# translating 637B7677-18E7-4C7B-8DF3-CFED96EA55C3 to /dev/sdb

	# check whether disks are existent
	ls /sys/block/sd* >/dev/null 2>&1 || return
	
	for i in /sys/block/sd* ; do
		DeviceNode=/dev/${i##*/}
		GUID=$(gdisk -l ${DeviceNode} | awk -F" " '/^Disk identifier/ {print $4}')
		if [ "X${GUID}" = "X${1}" ]; then
			echo -n ${DeviceNode}
			break
		fi
	done
} # GetGUIDforDisk

PreRequisits() {
	export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
	unset LANG
	LastDiskCheck=0

	# we need the informations gathered from armhwinfo. In case we're not called
	# from there, get the variables on our own
	if [ "X${BOARD_NAME}" = "X" ]; then
		. /etc/init.d/armhwinfo start >/dev/null 2>&1
	fi
	
	# check/create /etc/armbianmonitor and /etc/armbianmonitor/datasources
	if [ ! -d /etc/armbianmonitor ]; then
		mkdir -p -m 755 /etc/armbianmonitor
	else
		chmod 755 /etc/armbianmonitor
	fi
	if [ ! -d /etc/armbianmonitor/datasources ]; then
		mkdir -p -m 755 /etc/armbianmonitor/datasources
	else
		chmod 755 /etc/armbianmonitor/datasources
	fi
	
	# check whether we should do debug monitoring or normal
	read DebugMode </etc/armbianmonitor/start-monitoring

	# set default variables
	unset LANG
	LastDiskCheck=0
	LastTempCheck=0
	LastUserStat=0
	LastNiceStat=0
	LastSystemStat=0
	LastIdleStat=0
	LastIOWaitStat=0
	LastIrqStat=0
	LastSoftIrqStat=0
	LastCpuStatCheck=0
} # PreRequisits

ParseDVFSTable() {
	# extract DRAM and dvfs settings from script.bin
	bin2fex <"${Path2ScriptBin}/script.bin" 2>/dev/null | \
		grep -E "^LV._|^LV_|extrem|boot_clock|_freq|^dram_" | \
		grep -Ev "cpu_freq|dram_freq" | while read ; do
		echo "# ${REPLY}"
	done >/tmp/dvfs-table

	echo -e '\nGetVCore() {' >>/tmp/dvfs-table

	# parse /tmp/dvfs-table to get dvfs entries
	grep "^# LV._freq" /tmp/dvfs-table | sort -r | while read ; do
		set ${REPLY}
		CPUFreq=$4
		# if [ ${CPUFreq} -eq 0 ]; then
		#	echo -e "if [ \$1 -ge $(( ${CPUFreq} / 1000 )) ]; then\n\techo -n ${VCore}\nel\c" >>/tmp/dvfs-table
		#	break
		# else
		# 	VCore=$(grep -A1 "^# $2" /tmp/dvfs-table | tail -n1 | awk -F" " '{print $4}')
		# 	echo -e "if [ \$1 -ge $(( ${CPUFreq} / 1000 )) ]; then\n\techo -n ${VCore}\nel\c" >>/tmp/dvfs-table
		if [ ${CPUFreq} -ne 0 ]; then
			VCore=$(grep -A1 "^# $2" /tmp/dvfs-table | tail -n1 | awk -F" " '{print $4}')
			echo -e "if [ \$1 -le $(( ${CPUFreq} / 1000 )) ]; then\n\techo -n ${VCore}\nel\c" >>/tmp/dvfs-table
		fi
	done
	# VCore=$(grep -A1 "^# LV1_freq" /tmp/dvfs-table | tail -n1 | awk -F" " '{print $4}')
	echo -e "se\n\techo -n ${VCore}\nfi\n}" >>/tmp/dvfs-table
} # ParseDVFSTable

ProcessStats() {
	set $(awk -F" " '/^cpu / {print $2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}' </proc/stat)
	UserStat=$1
	NiceStat=$2
	SystemStat=$3
	IdleStat=$4
	IOWaitStat=$5
	IrqStat=$6
	SoftIrqStat=$7
	
	UserDiff=$(( ${UserStat} - ${LastUserStat} ))
	NiceDiff=$(( ${NiceStat} - ${LastNiceStat} ))
	SystemDiff=$(( ${SystemStat} - ${LastSystemStat} ))
	IdleDiff=$(( ${IdleStat} - ${LastIdleStat} ))
	IOWaitDiff=$(( ${IOWaitStat} - ${LastIOWaitStat} ))
	IrqDiff=$(( ${IrqStat} - ${LastIrqStat} ))
	SoftIrqDiff=$(( ${SoftIrqStat} - ${LastSoftIrqStat} ))
	
	Total=$(( ${UserDiff} + ${NiceDiff} + ${SystemDiff} + ${IdleDiff} + ${IOWaitDiff} + ${IrqDiff} + ${SoftIrqDiff} ))
	CPULoad=$(( ( ${Total} - ${IdleDiff} ) * 100 / ${Total} ))
	UserLoad=$(( ${UserDiff} *100 / ${Total} ))
	SystemLoad=$(( ${SystemDiff} *100 / ${Total} ))
	NiceLoad=$(( ${NiceDiff} *100 / ${Total} ))
	IOWaitLoad=$(( ${IOWaitDiff} *100 / ${Total} ))
	IrqCombinedLoad=$(( ( ${IrqDiff} + ${SoftIrqDiff} ) *100 / ${Total} ))
	
	echo "${CPULoad} ${SystemLoad} ${UserLoad} ${NiceLoad} ${IOWaitLoad} ${IrqCombinedLoad}" >/tmp/cpustat

	LastUserStat=${UserStat}
	LastNiceStat=${NiceStat}
	LastSystemStat=${SystemStat}
	LastIdleStat=${IdleStat}
	LastIOWaitStat=${IOWaitStat}
	LastIrqStat=${IrqStat}
	LastSoftIrqStat=${SoftIrqStat}
} # ProcessStats

GetExternalTemp() {
	# example function that parses meteo.physik.uni-muenchen.de and mingaweda.de
	# temperature values for Munich and compares them. When values are out
	# of bounds then only the other value will be returned otherwise the average
	ExternalTemp1=$(/usr/bin/links -http.fake-user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/600.7.12 (KHTML, like Gecko) Version/8.0.7 Safari/600.7.12' -dump "http://www.meteo.physik.uni-muenchen.de/dokuwiki/doku.php?id=wetter:stadt:messung" | awk -F" " '/Lufttemperatur/ {printf ("%0.0f",$4*1000); }')
	ExternalTemp2=$(/usr/bin/links -http.fake-user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/600.7.12 (KHTML, like Gecko) Version/8.0.7 Safari/600.7.12' -dump "http://www.mingaweda.de/wetterdaten/" | awk -F" " '/Ausfu:hrliche/ {printf ("%0.0f",$2*1000); }')
	
	if [ "X${ExternalTemp2}" = "X" ]; then
		ExternalTemp2=${ExternalTemp1}
	elif [ "X${ExternalTemp1}" = "X" ]; then
		ExternalTemp1=${ExternalTemp2}
    fi

	echo $(( ( ${ExternalTemp1} + ${ExternalTemp2} ) / 2 ))
} # GetExternalTemp

Main
