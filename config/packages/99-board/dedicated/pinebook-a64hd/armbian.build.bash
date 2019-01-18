#!/bin/bash

# install power manager
display_alert "Installing" "xfce4-power-manager" "info"
[[ $BUILD_DESKTOP == yes ]] && chroot $SDCARD /bin/bash -c "apt-get -qq -y install xfce4-power-manager >/dev/null 2>&1"