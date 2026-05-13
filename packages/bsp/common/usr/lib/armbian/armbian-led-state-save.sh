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

	TRIGGER_CONTENT=$(< $TRIGGER_PATH)

	[[ "$TRIGGER_CONTENT" =~ $REGEX ]]

	TRIGGER_VALUE=${BASH_REMATCH[1]}

	echo "[$LED]" >> $STATE_PATH
	echo "trigger=$TRIGGER_VALUE" >> $DESTINATION

	# In case the trigger is any of the kbd-*, don't store any other parameter
	# This avoids num/scroll/capslock from being restored at startup.
	# Use shell glob (anchored at start of string) rather than bash regex —
	# `=~ kbd-*` is regex where `*` is "0+ of preceding `-`" and the match
	# is not anchored, so any trigger containing `kbd` could match. The
	# `case kbd-*)` form is anchored and matches only triggers that
	# literally start with `kbd-`.
	case "$TRIGGER_VALUE" in
		kbd-*) return ;;
	esac

	COMMAND_PARAMS="$CMD_FIND $PATH/ -maxdepth 1 -type f ! -iname uevent ! -iname trigger -perm /u+w -printf %f\\n"
	PARAMS=$($COMMAND_PARAMS)

	# brightness semantics depend on the trigger:
	#   trigger=none           → brightness is plain config (static value).
	#   trigger=netdev/pattern → brightness is a "ceiling" the trigger may
	#                            scale to (kernel LED ABI: writing non-zero
	#                            brightness while a trigger is active sets
	#                            the top brightness for the trigger's
	#                            output). Board configs use this on purpose
	#                            (e.g. radxa-e52c.conf has brightness=1
	#                            under trigger=netdev to dim the blink).
	#   noisy triggers below   → brightness is the trigger's instantaneous
	#                            output (link-up/down boolean, tpt blink
	#                            state). Capturing it on shutdown produces
	#                            ghost-LED bugs on restore (":link" showed
	#                            cable-up while unplugged) and constant
	#                            churn in /etc/armbian-leds.conf (rtw88
	#                            phy0tpt flapped 0/1 every shutdown).
	# Strip brightness only for the noisy set; keep it for everything else
	# so legitimate dim ceilings survive the save/restore cycle.
	# Pattern history: ":link"-only strip was the original workaround in
	# commit 2960ffaff; "phy*tpt" extends it to the rtw88 forum case.
	# Forum thread: https://forum.armbian.com/topic/57284-regular-changes-in-file-etcarmbian-ledsconf-on-odroid-n2/
	#
	# Token-safe whole-word filter: the simpler ${PARAMS//brightness/}
	# substring substitution would also corrupt sibling files like
	# `max_brightness` → `max_`, breaking the read loop below under set -e.
	# Bash-only (no `awk` etc.) because store_led() reassigns PATH to the
	# sysfs led path, so external commands aren't on PATH here.
	case "$TRIGGER_VALUE" in
		*:link | phy*tpt)
			declare _filtered=""
			for _p in $PARAMS; do
				[[ "$_p" == "brightness" ]] && continue
				_filtered+="$_p"$'\n'
			done
			PARAMS="$_filtered"
			;;
	esac

	for PARAM in $PARAMS; do

		PARAM_PATH="$PATH/$PARAM"
		VALUE=$(< $PARAM_PATH)

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
