#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "/tmp/.reboot_required" ]; then
        echo -e "[\e[0;91m Kernel was updated, please reboot!\x1B[0m ]"
		echo ""
        rm "/tmp/.reboot_required"
    fi
fi