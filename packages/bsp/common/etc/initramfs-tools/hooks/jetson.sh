#!/bin/sh
# Copy xusb file to initrd
#
mkdir -p "${DESTDIR}"/lib/firmware/nvidia/tegra210
xusbfile=/lib/firmware/nvidia/tegra210/xusb.bin

if [ -f "${xusbfile}" ]; then
	cp "${xusbfile}" "${DESTDIR}"/lib/firmware/nvidia/tegra210
fi

exit 0
