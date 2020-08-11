#!/bin/sh
# Copy splash file to initrd
#
mkdir -p "${DESTDIR}"/lib/firmware
splashfile=/lib/firmware/bootsplash.armbian

if [ -f "${splashfile}" ]; then
	cp "${splashfile}" "${DESTDIR}"/lib/firmware
fi

exit 0
