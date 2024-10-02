#!/bin/sh -e

if [ "x$1" = xremove ]; then
	if which plymouth-set-default-theme >/dev/null 2>&1; then
		# For Debian
		plymouth-set-default-theme -r
	else
		# For Ubuntu
		update-alternatives \
			--remove default.plymouth \
			/usr/share/plymouth/themes/armbian/armbian.plymouth
	fi
fi
