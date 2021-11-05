#!/bin/sh
# Copy xusb file to initrd
#
mkdir -p "${DESTDIR}"/lib/firmware/nvidia/tegra210
xusbfile=/lib/firmware/nvidia/tegra210/xusb.bin

if [ -f "${xusbfile}" ]; then
	cp "${xusbfile}" "${DESTDIR}"/lib/firmware/nvidia/tegra210
fi

usbold=/lib/firmware/tegra21x_xusb_firmware

if [ -f "${usbold}" ]; then
	cp "${usbold}" "${DESTDIR}"/lib/firmware
fi

exit 0
