#!/bin/bash


echo "|Configuration|branch|Actual hardware|armbianmonitor -u|||"
echo "|--|--|--|--|--|--|"
#ls -1 *.conf | cut -d . -f 1 | awk '{ print "|" $0"| | | | | |" $2 }'


for board in *.conf; do
	# read board config
	source $board

	for i in $(echo $KERNEL_TARGET | sed "s/,/ /g")
	do
#	    echo "$i"

echo $BOARD_NAME | awk '{ print "|" $0"|'$i'| | | | |"}'

	done

#echo $BOARD_NAME | awk '{ print "|" $0"|'$KERNEL_TARGET'| | | | |"}'
done


