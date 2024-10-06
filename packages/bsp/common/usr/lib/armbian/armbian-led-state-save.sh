#!/bin/bash
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

STATE_PATH="$1"
[[ -z "$1" ]] && STATE_PATH="/etc/armbian-leds.conf"

# Regular expression to extract the trigger from the led trigger file
REGEX=$'\[(.*)\]'

CMD_FIND=$(which find)

# Retrieve the trigger for a specific led and stores the entry in a destination state file
# Also retrieve all the writable parameters for a led and stores them in a destination state file
# $1 = base led path
# $2 = path of destination state file
function store_led() {

	PATH="$1"
	TRIGGER_PATH="$1/trigger"
	DESTINATION="$2"

	TRIGGER_CONTENT=$(<$TRIGGER_PATH)

	[[ "$TRIGGER_CONTENT" =~ $REGEX ]]

	TRIGGER_VALUE=${BASH_REMATCH[1]}

	echo "[$LED]" >> $STATE_PATH
	echo "trigger=$TRIGGER_VALUE" >> $DESTINATION

	# In case the trigger is any of the kbd-*, don't store any other parameter
	# This avoids num/scroll/capslock from being restored at startup
	[[ "$TRIGGER_VALUE" =~ kbd-* ]] && return

	COMMAND_PARAMS="$CMD_FIND $PATH/ -maxdepth 1 -type f ! -iname uevent ! -iname trigger -perm /u+w -printf %f\\n"
	PARAMS=$($COMMAND_PARAMS)

	# In case trigger is representing link-state for any network, use
	# bash substitution to remove the brightness parameter and avoid
	# ghost wan/lan/etc (led up while cable unplugged)
	[[ "$TRIGGER_VALUE" == *":link" ]] && PARAMS=${PARAMS//"brightness"/}

	for PARAM in $PARAMS; do

		PARAM_PATH="$PATH/$PARAM"
		VALUE=$(<$PARAM_PATH)

		# If the variable contains non-printable characters
		# suppose it contains binary and skip it
		[[ "$VALUE" =~ [[:cntrl:]] ]] && continue

		echo "$PARAM=$VALUE" >> $DESTINATION

	done

}

# zeroing current state file if existing
[[ -f $STATE_PATH ]] && echo -n > $STATE_PATH

for LED in /sys/class/leds/*; do
	[[ -d "$LED" ]] || continue

	# Skip saving state for directories starting with enP e.g. enP1p1s0-0::lan enP2p1s0-2::lan etc. etc.
	[[ "$(/usr/bin/basename "$LED")" == enP* ]] && continue

	store_led $LED $STATE_PATH
	echo >> $STATE_PATH

done
