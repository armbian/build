#!/bin/sh

. /etc/armbian-release

if [ -n "$BASH_VERSION" ] && [ "$-" != "${-#*i}" ]; then
    # Display reboot recommendation if necessary
    if [[ -f /var/run/resize2fs-reboot ]]; then
        printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
        printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
    fi
fi
