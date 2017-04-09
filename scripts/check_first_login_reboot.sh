#!/bin/sh

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	printf "\n"
	if [ -f "/var/run/.reboot_required" ]; then
		printf "[\e[0;91m Kernel was updated, please reboot\x1B[0m ]"
	fi
	if [ -f "/usr/bin/armbian-config" ]; then
		printf "[\e[0;31m General system configuration\x1B[0m: \e[1marmbian-config\e[0m ]\n\n"
		elif [ -f "/var/run/.reboot_required" ]; then
		printf "\n\n"
	fi
fi