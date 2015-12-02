#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
    if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo -e "\e[0;31mThank you for choosing Armbian. This is your first login and it's time for:\x1B[0m"
        echo ""
        echo -e "\e[0;32mSytem update: \x1B[0mapt-get upgrade \e[0;32mand deployment: \x1B[0mnand-sata-install"     
        echo ""
        rm -f "$HOME/.not_logged_in_yet"
    fi
fi
