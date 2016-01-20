#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo -e "\e[0;31mThank you for choosing Armbian. Support: www.armbian.com\x1B[0m"
		echo "" 
        rm -f "$HOME/.not_logged_in_yet"
    fi
fi
