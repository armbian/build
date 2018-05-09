#!/bin/sh

if [ -n "$BASH_VERSION" ] && [ "$-" != "${-#*i}" ]; then
    if [ ! -f "/etc/yunohost/installed" ];
    then
        normal=$(printf '\033[0m')
        bold=$(printf '\033[1m')
        blue=$(printf '\033[34m')

        IPS=$(hostname --all-ip-address | sed 's/ /\n     /g')
        cat << EOF
======================================================================
${bold}${blue}
 Congratulations on setting up your YunoHost server !
${normal}${bold}
 To finish the installation, you should run the postinstallation.
 You can find documentation about it on :${normal}
     https://yunohost.org/postinstall
${normal}${bold}
 You can run it from the command line interface with :${normal}
     $ yunohost tools postinstall
${normal}${bold}
 Or from a browser by accessing one of your local IP :${normal}
     $IPS${normal}
======================================================================
EOF
    fi
fi
