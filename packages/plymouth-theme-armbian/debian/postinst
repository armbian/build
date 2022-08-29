#!/bin/sh -e

if [ "x$1" = xconfigure ]; then
	if which plymouth-set-default-theme >/dev/null 2>&1; then
		# For Debian
		plymouth-set-default-theme armbian
	else
		# For Ubuntu
		update-alternatives \
			--install /usr/share/plymouth/themes/default.plymouth default.plymouth \
			/usr/share/plymouth/themes/armbian/armbian.plymouth 150
	fi

	if which update-initramfs >/dev/null 2>&1; then
		update-initramfs -u
	fi
fi
