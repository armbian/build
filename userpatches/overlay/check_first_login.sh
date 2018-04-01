#!/bin/sh

. /etc/armbian-release

if [ -n "$BASH_VERSION" ] && [ "$-" != "${-#*i}" ]; then
	while [ -f "/root/.not_logged_in_yet" ]; do
		rm "/root/.not_logged_in_yet"
        printf ""
        printf "Congratulation on setting up your YunoHost server !\n"
        printf "\n"
        printf "To finish the installation, you should run :\n"
        printf "   yunohost tools postinstall \n"
        printf ""
	done
    # Display reboot recommendation if necessary
    if [[ -f /var/run/resize2fs-reboot ]]; then
        printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
        printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
    fi
fi
