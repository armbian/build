#!/bin/bash

###############################################################################
# Bash script to control the NanoPi M4 SATA hat 12v fan via the sysfs interface
###############################################################################
# Author: cgomesu
# Repo: https://github.com/cgomesu/nanopim4-satahat-fan
# Official pwm sysfs doc: https://www.kernel.org/doc/Documentation/pwm.txt
#
# This is free. There is NO WARRANTY. Use at your own risk.
###############################################################################

cache() {
	if [[ -z "$1" ]]; then
		echo '[pwm-fan] Cache file was not specified. Assuming generic.'
		local FILENAME='generic'
	else
		local FILENAME="$1"
	fi
	# cache to memory
	CACHE_ROOT='/tmp/pwm-fan/'
	if [[ ! -d "$CACHE_ROOT" ]]; then
		mkdir "$CACHE_ROOT"
	fi
	CACHE=$CACHE_ROOT$FILENAME'.cache'
	if [[ ! -f "$CACHE" ]]; then
		touch "$CACHE"
	else
		> "$CACHE"
	fi
}

check_requisites() {
	local REQUISITES=('bc' 'cat' 'echo' 'mkdir' 'touch' 'trap' 'sleep')
	echo '[pwm-fan] Checking requisites: '${REQUISITES[@]}
	for cmd in ${REQUISITES[@]}; do
		if [[ -z $(command -v $cmd) ]]; then
			echo '[pwm-fan] The following program is not installed or cannot be found in this users $PATH: '$cmd
			echo '[pwm-fan] Fix it and try again.'
			end "Missing important packages. Cannot continue." 1
		fi
	done
	echo '[pwm-fan] All commands are accesible.'
}

cleanup() {
	echo '---- cleaning up ----'
	# disable the channel
	unexport_pwmchip_channel
	# clean cache files
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
	echo '--------------------'
}

config() {
	pwmchip
	export_pwmchip_channel
	fan_startup
	fan_initialization
	thermal_monit
}

# takes message and status as argument
end() {
	cleanup
	echo '####################################################'
	echo '# END OF THE PWM-FAN SCRIPT'
	echo '# MESSAGE: '$1
	echo '####################################################'
	exit $2
}

export_pwmchip_channel() {
	if [[ ! -d "$CHANNEL_FOLDER" ]]; then
		local EXPORT=$PWMCHIP_FOLDER'export'
		cache 'export'
		local EXPORT_SET=$(echo 0 2> "$CACHE" > "$EXPORT")
		if [[ ! -z $(cat "$CACHE") ]]; then
			# on error, parse output
			if [[ $(cat "$CACHE") =~ (P|p)ermission\ denied ]]; then
				echo '[pwm-fan] This user does not have permission to use channel '$CHANNEL'.'
				if [[ ! -z $(command -v stat) ]]; then
					echo '[pwm-fan] Export is owned by user: '$(stat -c '%U' "$EXPORT")'.'
					echo '[pwm-fan] Export is owned by group: '$(stat -c '%G' "$EXPORT")'.'
				fi
				local ERR_MSG='User permission error while setting channel.'
			elif [[ $(cat "$CACHE") =~ (D|d)evice\ or\ resource\ busy ]]; then
				echo '[pwm-fan] It seems the pin is already in use. Cannot write to export.'
				local ERR_MSG=$PWMCHIP' was busy while setting channel.'
			else
				echo '[pwm-fan] There was an unknown error while setting the channel '$CHANNEL'.'
				if [[ $(cat "$CACHE") =~ \ ([^\:]+)$ ]]; then
					echo '[pwm-fan] Error: '${BASH_REMATCH[1]}'.'
				fi
				local ERR_MSG='Unknown error while setting channel.'
			fi
			end "$ERR_MSG" 1
		fi
		sleep 1
	elif [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] '$CHANNEL' channel is already accessible.'
	fi
}

fan_initialization() {
	if [[ -z "$TIME_STARTUP" ]]; then
		TIME_STARTUP=10
	fi
	cache 'test_fan'
	local READ_MAX_DUTY_CYCLE=$(cat $CHANNEL_FOLDER'period')
	echo $READ_MAX_DUTY_CYCLE 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
	# on error, try setting duty_cycle to a lower value
	if [[ ! -z $(cat $CACHE) ]]; then
		local READ_MAX_DUTY_CYCLE=$(($(cat $CHANNEL_FOLDER'period') - 100))
		> $CACHE
		echo $READ_MAX_DUTY_CYCLE 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
		if [[ ! -z $(cat $CACHE) ]]; then
			end 'Unable to set max duty_cycle.' 1
		fi
	fi
	MAX_DUTY_CYCLE=$READ_MAX_DUTY_CYCLE
	echo '[pwm-fan] Running fan at full speed for the next '$TIME_STARTUP' seconds...'
	echo 1 > $CHANNEL_FOLDER'enable'
	sleep $TIME_STARTUP
	echo $((MAX_DUTY_CYCLE / 2)) > $CHANNEL_FOLDER'duty_cycle'
	echo '[pwm-fan] Initialization done. Duty cycle at 50% now: '$((MAX_DUTY_CYCLE / 2))' ns.'
	sleep 1
}

fan_run() {
	if [[ $THERMAL_STATUS -eq 0 ]]; then
		fan_run_max
	else
		fan_run_thermal
	fi
}

fan_run_max() {
	echo '[pwm-fan] Running fan at full speed until stopped (Ctrl+C or kill '$$')...'
	while true; do
		echo $MAX_DUTY_CYCLE > $CHANNEL_FOLDER'duty_cycle'
		# run every so often to make sure it is maxed
		sleep 120
	done
}

fan_run_thermal() {
	echo '[pwm-fan] Running fan in temp monitor mode until stopped (Ctrl+C or kill '$$')...'
	if [[ -z $THERMAL_ABS_THRESH_LOW ]]; then
		THERMAL_ABS_THRESH_LOW=25
	fi
	if [[ -z $THERMAL_ABS_THRESH_HIGH ]]; then
		THERMAL_ABS_THRESH_HIGH=75
	fi
	THERMAL_ABS_THRESH=($THERMAL_ABS_THRESH_LOW $THERMAL_ABS_THRESH_HIGH)
	if [[ -z $DC_PERCENT_MIN ]]; then
		DC_PERCENT_MIN=25
	fi
	if [[ -z $DC_PERCENT_MAX ]]; then
		DC_PERCENT_MAX=100
	fi
	DC_ABS_THRESH=($(((DC_PERCENT_MIN * MAX_DUTY_CYCLE) / 100)) $(((DC_PERCENT_MAX * MAX_DUTY_CYCLE) / 100)))
	if [[ -z $TEMPS_SIZE ]]; then
		TEMPS_SIZE=6
	fi
	if [[ -z $TIME_LOOP ]]; then
		TIME_LOOP=10
	fi
	TEMPS=()
	while [[ true ]]; do
		TEMPS+=($(thermal_meter))
		if [[ ${#TEMPS[@]} -gt $TEMPS_SIZE ]]; then
			TEMPS=(${TEMPS[@]:1})
		fi
		if [[ ${TEMPS[-1]} -le ${THERMAL_ABS_THRESH[0]} ]]; then
			echo ${DC_ABS_THRESH[0]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
		elif [[ ${TEMPS[-1]} -ge ${THERMAL_ABS_THRESH[-1]} ]]; then
			echo ${DC_ABS_THRESH[-1]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
		elif [[ ${#TEMPS[@]} -gt 1 ]]; then
			TEMPS_SUM=0
			for TEMP in ${TEMPS[@]}; do
				let TEMPS_SUM+=$TEMP
			done
			# moving mid-point
			MEAN_TEMP=$((TEMPS_SUM / ${#TEMPS[@]}))
			DEV_MEAN_CRITICAL=$((MEAN_TEMP - 100))
			X0=${DEV_MEAN_CRITICAL#-}
			# args: x, x0, L, a, b (k=a/b)
			MODEL=$(function_logistic ${TEMPS[-1]} $X0 ${DC_ABS_THRESH[-1]} 1 10)
			if [[ $MODEL -lt ${DC_ABS_THRESH[0]} ]]; then
				echo ${DC_ABS_THRESH[0]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			elif [[ $MODEL -gt ${DC_ABS_THRESH[-1]} ]]; then
				echo ${DC_ABS_THRESH[-1]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			else
				echo $MODEL 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			fi
		fi
		sleep $TIME_LOOP
	done
}

fan_startup() {
	if [[ -z $PERIOD ]]; then
		PERIOD=25000000
	fi
	while [[ -d "$CHANNEL_FOLDER" ]]; do
		if [[ $(cat $CHANNEL_FOLDER'enable') -eq 0 ]]; then
			set_default
			break
		elif [[ $(cat $CHANNEL_FOLDER'enable') -eq 1 ]]; then
			echo '[pwm-fan] The fan is already enabled. Will disable it.'
			echo 0 > $CHANNEL_FOLDER'enable'
			sleep 1
			set_default
			break
		else
			echo '[pwm-fan] Unable to read the fan enable status.'
			end 'Bad fan status' 1
		fi
	done
}

function_logistic() {
	# https://en.wikipedia.org/wiki/Logistic_function
	local x=$1
	local x0=$2
	local L=$3
	# k=a/b
	local a=$4
	local b=$5
	local equation="output=$L/(1+e(-($a/$b)*($x-$x0)));scale=0;output/1"
	local result=$(echo $equation | bc -lq)
	echo $result
}

interrupt() {
	echo '!! ATTENTION !!'
	end 'Received a signal to stop the script.' 0
}

pwmchip() {
	if [[ -z $PWMCHIP ]]; then
		PWMCHIP='pwmchip1'
	fi
	PWMCHIP_FOLDER='/sys/class/pwm/'$PWMCHIP'/'
	if [[ ! -d "$PWMCHIP_FOLDER" ]]; then
		echo '[pwm-fan] The sysfs interface for the '$PWMCHIP' is not accessible.'
		end 'Cannot access '$PWMCHIP' sysfs interface.' 1
	fi
	echo '[pwm-fan] Working with the sysfs interface for the '$PWMCHIP'.'
	echo '[pwm-fan] For reference, your '$PWMCHIP' supports '$(cat $PWMCHIP_FOLDER'npwm')' channel(s).'
	if [[ -z $CHANNEL ]]; then
		CHANNEL='pwm0'
	fi
	CHANNEL_FOLDER="$PWMCHIP_FOLDER""$CHANNEL"'/'
}

set_default() {
	cache 'set_default_duty_cycle'
	echo 0 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
	if [[ ! -z $(cat $CACHE) ]]; then
		# set higher than 0 values to avoid negative ones
		echo 100 > $CHANNEL_FOLDER'period'
		echo 10 > $CHANNEL_FOLDER'duty_cycle'
	fi
	cache 'set_default_period'
	echo $PERIOD 2> $CACHE > $CHANNEL_FOLDER'period'
	if [[ ! -z $(cat $CACHE) ]]; then
		echo '[pwm-fan] The period provided ('$PERIOD') is not acceptable.'
		echo '[pwm-fan] Trying to lower it by 100ns decrements. This may take a while...'
		local decrement=100
		local rate=$decrement
		until [[ $PERIOD_NEW -le 200 ]]; do
			local PERIOD_NEW=$((PERIOD - rate))
			> $CACHE
			echo $PERIOD_NEW 2> $CACHE > $CHANNEL_FOLDER'period'
			if [[ -z $(cat $CACHE) ]]; then
				break
			fi
			local rate=$((rate + decrement))
		done
		PERIOD=$PERIOD_NEW
		if [[ $PERIOD -le 100 ]]; then
			end 'Unable to set an appropriate value for the period.' 1
		fi
	fi
	echo 'normal' > $CHANNEL_FOLDER'polarity'
	echo '[pwm-fan] Default polarity: '$(cat $CHANNEL_FOLDER'polarity')
	echo '[pwm-fan] Default period: '$(cat $CHANNEL_FOLDER'period')' ns'
	echo '[pwm-fan] Default duty cycle: '$(cat $CHANNEL_FOLDER'duty_cycle')' ns'
}

start() {
	echo '####################################################'
	echo '# STARTING PWM-FAN SCRIPT'
	echo '# Date and time: '$(date)
	echo '####################################################'
	check_requisites
}

thermal_meter() {
	if [[ -f $TEMP_FILE ]]; then
		local TEMP=$(cat $TEMP_FILE 2> /dev/null)
		# TEMP is in millidegrees, so convert to degrees
		echo $((TEMP / 1000))
	fi
}

thermal_monit() {
	if [[ -z $MONIT_DEVICE ]]; then
		# soc for legacy Kernel or cpu for latest Kernel
		MONIT_DEVICE='(soc|cpu)'
	fi
	local THERMAL_FOLDER='/sys/class/thermal/'
	if [[ -d $THERMAL_FOLDER && -z $SKIP_THERMAL ]]; then
		for dir in $THERMAL_FOLDER'thermal_zone'*; do
			if [[ $(cat $dir'/type') =~ $MONIT_DEVICE && -f $dir'/temp' ]]; then
				TEMP_FILE=$dir'/temp'
				echo '[pwm-fan] Found the '$MONIT_DEVICE' temperature at '$TEMP_FILE
				echo '[pwm-fan] Current '$MONIT_DEVICE' temp is: '$(($(thermal_meter)))' Celsius'
				echo '[pwm-fan] Setting fan to monitor the '$MONIT_DEVICE' temperature.'
				THERMAL_STATUS=1
				return
			fi
		done
		echo '[pwm-fan] Did not find the temperature for the device type: '$MONIT_DEVICE
	else
		echo '[pwm-fan] -f mode enabled or the the thermal zone cannot be found at '$THERMAL_FOLDER
	fi
	echo '[pwm-fan] Setting fan to operate independent of the '$MONIT_DEVICE' temperature.'
	THERMAL_STATUS=0
}

unexport_pwmchip_channel() {
	if [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] Freeing up the channel '$CHANNEL' controlled by the '$PWMCHIP'.'
		echo 0 > $CHANNEL_FOLDER'enable'
		sleep 1
		echo 0 > $PWMCHIP_FOLDER'unexport'
		sleep 1
		if [[ ! -d "$CHANNEL_FOLDER" ]]; then
			echo '[pwm-fan] Channel '$CHANNEL' was disabled.'
		else
			echo '[pwm-fan] Channel '$CHANNEL' is still enabled. Please check '$CHANNEL_FOLDER'.'
		fi
	else
		echo '[pwm-fan] There is no channel to disable.'
	fi
}

usage() {
	echo ''
	echo 'Usage:'
	echo ''
	echo "$0" '[OPTIONS]'
	echo ''
	echo '  Options:'
	echo '    -c  str  Name of the PWM CHANNEL (e.g., pwm0, pwm1). Default: pwm0'
	echo '    -C  str  Name of the PWM CONTROLLER (e.g., pwmchip0, pwmchip1). Default: pwmchip1'
	echo '    -d  int  Lowest DUTY CYCLE threshold (in percentage of the period). Default: 25'
	echo '    -D  int  Highest DUTY CYCLE threshold (in percentage of the period). Default: 100'
	echo '    -f       Fan runs at FULL SPEED all the time. If omitted (default), speed depends on temperature.'
	echo '    -F  int  TIME (in seconds) to run the fan at full speed during STARTUP. Default: 60'
	echo '    -h       Show this HELP message.'
	echo '    -l  int  TIME (in seconds) to LOOP thermal reads. Lower means higher resolution but uses ever more resources. Default: 10'
	echo '    -m  str  Name of the DEVICE to MONITOR the temperature in the thermal sysfs interface. Default: (soc|cpu)'
	echo '    -p  int  The fan PERIOD (in nanoseconds). Default (25kHz): 25000000.'
	echo '    -s  int  The MAX SIZE of the TEMPERATURE ARRAY. Interval between data points is set by -l. Default (store last 1min data): 6.'
	echo '    -t  int  Lowest TEMPERATURE threshold (in Celsius). Lower temps set the fan speed to min. Default: 25'
	echo '    -T  int  Highest TEMPERATURE threshold (in Celsius). Higher temps set the fan speed to max. Default: 75'
	echo ''
	echo '  If no options are provided, the script will run with default values.'
	echo '  Defaults have been tested and optimized for the following hardware:'
	echo '    -  NanoPi-M4 v2'
	echo '    -  M4 SATA hat'
	echo '    -  Fan 12V (.08A and .2A)'
	echo '  And software:'
	echo '    -  Kernel: Linux 4.4.231-rk3399'
	echo '    -  OS: Armbian Buster (20.08.9) stable'
	echo '    -  GNU bash v5.0.3'
	echo '    -  bc v1.07.1'
	echo ''
	echo 'Author: cgomesu'
	echo 'Repo: https://github.com/cgomesu/nanopim4-satahat-fan'
	echo ''
	echo 'This is free. There is NO WARRANTY. Use at your own risk.'
	echo ''
}

while getopts 'c:C:d:D:fF:hl:m:p:s:t:T:' OPT; do
	case ${OPT} in
		c)
			CHANNEL="$OPTARG"
			if [[ ! $CHANNEL =~ ^pwm[0-9]+$ ]]; then
				echo 'The name of the pwm channel must contain pwm and at least a number (pwm0).'
				exit 1
			fi
			;;
		C)
			PWMCHIP="$OPTARG"
			if [[ ! $PWMCHIP =~ ^pwmchip[0-9]+$ ]]; then
				echo 'The name of the pwm controller must contain pwmchip and at least a number (pwmchip1).'
				exit 1
			fi
			;;
		d)
			DC_PERCENT_MIN="$OPTARG"
			if [[ ! $DC_PERCENT_MIN =~ ^([0-6][0-9]?|70)$ ]]; then
				echo 'The lowest duty cycle threshold must be an integer between 0 and 70.'
				exit 1
			fi
			;;
		D)
			DC_PERCENT_MAX="$OPTARG"
			if [[ ! $DC_PERCENT_MAX =~ ^([8-9][0-9]?|100)$ ]]; then
				echo 'The highest duty cycle threshold must be an integer between 80 and 100.'
				exit 1
			fi
			;;
		f)
			SKIP_THERMAL=1
			;;
		F)
			TIME_STARTUP="$OPTARG"
			if [[ ! $TIME_STARTUP =~ ^[0-9]+$ ]]; then
				echo 'The time to run the fan at full speed during startup must be an integer.'
				exit 1
			fi
			;;
		h)
			usage
			exit 0
			;;
		l)
			TIME_LOOP="$OPTARG"
			if [[ ! $TIME_LOOP =~ ^[0-9]+$ ]]; then
				echo 'The time to loop thermal reads must be an integer.'
				exit 1
			fi
			;;
		m)
			MONIT_DEVICE="$OPTARG"
			;;
		p)
			PERIOD="$OPTARG"
			if [[ ! $PERIOD =~ ^[0-9]+$ ]]; then
				echo 'The period must be an integer.'
				exit 1
			fi
			;;
		s)
			TEMPS_SIZE="$OPTARG"
			if [[ ! $TEMPS_SIZE =~ ^[0-9]+$ ]]; then
				echo 'The max size of the temperature array must be an integer.'
				exit 1
			fi
			;;
		t)
			THERMAL_ABS_THRESH_LOW="$OPTARG"
			if [[ ! $THERMAL_ABS_THRESH_LOW =~ ^[0-4][0-9]?$ ]]; then
				echo 'The lowest temperature threshold must be an integer between 0 and 49.'
				exit 1
			fi
			;;
		T)
			THERMAL_ABS_THRESH_HIGH="$OPTARG"
			if [[ ! $THERMAL_ABS_THRESH_HIGH =~ ^([5-9][0-9]?|1[0-1][0-9]?|120)$ ]]; then
				echo 'The highest temperature threshold must be an integer between 50 and 120.'
				exit 1
			fi
			;;
		\?)
			echo '!! ATTENTION !!'
			echo '................................'
			echo 'Detected an invalid option.'
			echo 'Try: '"$0"' -h'
			echo '................................'
			exit 1
			;;
	esac
done

start
trap 'interrupt' SIGINT SIGHUP SIGTERM SIGKILL
config
fan_run
