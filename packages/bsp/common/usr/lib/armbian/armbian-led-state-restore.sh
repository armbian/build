#!/bin/bash
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

STATE_PATH="$1"
[[ -z "$1" ]] && STATE_PATH="/etc/armbian-leds.conf"

REGEX_BLANK_LINE=$'^\s*$'
REGEX_COMMENT_LINE=$'^#.*$'
REGEX_EXTRACT=$'\[(.*)\]'
REGEX_PARSE=$'(.*)=(.*)'

LED=""

if [[ ! -f $STATE_PATH ]]; then
	echo "File $STATE_PATH not found, nothing to do"
	exit 0
fi

while read LINE; do
	
	# Blank lines and lines starting with "#" are ignored
	[[ "$LINE" =~ $REGEX_BLANK_LINE ]] && continue
	[[ "$LINE" =~ $REGEX_COMMENT_LINE ]] && continue

	# When line matches the [...] style, assign the content as led base path
	if [[ "$LINE" =~ $REGEX_EXTRACT ]]; then 
		LED=${BASH_REMATCH[1]}
		continue
	fi

	if [[ -z "$LED" ]]; then
		echo "Invalid state file, no led path stanza found"
		exit 1
	fi

	[[ "$LINE" =~ $REGEX_PARSE ]]

	PARAM=${BASH_REMATCH[1]}
	VALUE=${BASH_REMATCH[2]}

	if [[ -z $PARAM || -z $VALUE ]]; then
		echo "Invalid state file, syntax error in configuration file "
		exit 1
	fi

	# Ignore brightness=0 param, this will reset trigger to none
	[[ $PARAM == "brightness" && $VALUE -eq 0 ]] && continue

	# Verify the led parameter exists and is writable, otherwise skip to next param
	if [[ ! -w "$LED/$PARAM" ]]; then
		echo "warning: $LED/$PARAM could not be restored"
		continue
	fi

	# Workaround for trigger=none: led does not clear if trigger is already none.
	# Set it to default-on, then will be reset immediately to none to turn it off
	[[ "$PARAM" == "trigger" && "$VALUE" == "none" ]] && echo "default-on" > "$LED/$PARAM"

	echo "$VALUE" > "$LED/$PARAM"

done < $STATE_PATH

exit 0
