#!/bin/bash

if [[ $BRANCH != default ]]; then
	# Enable bluetooth
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable olinuxino-bluetooth.service >/dev/null 2>&1"
	else
	# Install touchscreen calibrator
	[[ $BUILD_DESKTOP == yes ]] && chroot $SDCARD /bin/bash -c "apt-get -y -qq install xinput-calibrator >/dev/null 2>&1"
fi
