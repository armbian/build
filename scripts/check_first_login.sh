#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo "" 
		echo -e "\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m"
		echo "" 
        rm -f "$HOME/.not_logged_in_yet"
    fi
fi
