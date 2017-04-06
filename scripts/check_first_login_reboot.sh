#!/bin/sh

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	printf "\n"
	if [ -f "/var/run/.reboot_required" ]; then
		printf "[\e[0;91m Kernel was updated, please reboot\x1B[0m ]"
	fi
	if [ -f "/usr/bin/armbian-config" ]; then
		printf "[ Execute \e[0;91marmbian-config\x1B[0m to change some system settings ]\n\n"
		elif [ -f "/var/run/.reboot_required" ]; then
		printf "\n\n"
	fi
fi