#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "/tmp/.reboot_required" ]; then
        echo -e "[\e[0;32m Restart is required \x1B[0m]"
        echo ""
        rm "/tmp/.reboot_required"
    fi
fi