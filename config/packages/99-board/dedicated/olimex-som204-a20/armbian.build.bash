#!/bin/bash

if [[ $BRANCH == default && $BUILD_DESKTOP == yes ]]; then
	chroot $SDCARD /bin/bash -c "apt-get -y -qq install xinput-calibrator >/dev/null 2>&1"
fi
