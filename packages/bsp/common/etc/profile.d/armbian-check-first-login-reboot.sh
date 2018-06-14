#!/bin/sh

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	printf "\n"
	if [ -f "/var/run/.reboot_required" ]; then
		printf "[\e[0;91m Kernel was updated, please reboot\x1B[0m ]\n\n"
	fi
fi