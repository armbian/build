#!/bin/sh -e

if [ "x$1" = xremove ]; then
	if which update-initramfs >/dev/null 2>&1; then
		update-initramfs -u
	fi
fi
