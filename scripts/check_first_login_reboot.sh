#!/bin/sh

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "/var/run/.reboot_required" ]; then
        printf "\n[\e[0;91m Kernel was updated, please reboot\x1B[0m ]\n"
    fi
fi