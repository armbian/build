#!/bin/sh
# Copy firmware file to initrd
#

mkdir -p "${DESTDIR}"/lib/firmware
cp -rf /lib/firmware/esos.elf "${DESTDIR}"/lib/firmware

exit 0
