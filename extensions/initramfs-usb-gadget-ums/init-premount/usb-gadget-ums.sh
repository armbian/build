#!/bin/sh

# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

echo ""
echo "Armbian initramfs USB Gadget UMS: ums-initramfs.sh starting..."

# First, check if /proc/cmdline contains "ums=yes", otherwise exit
if ! grep -q "ums=yes" /proc/cmdline; then
	echo "Armbian initramfs USB Gadget UMS: ums=yes not found in /proc/cmdline, exiting normally."
	exit 0
fi

echo "Armbian initramfs USB Gadget UMS: ums=yes found in /proc/cmdline, continuing..."
sleep 1

deviceinfo_name="Armbian on %%BOARD%%"
deviceinfo_manufacturer="Armbian on %%BOARD%%"
usb_idVendor="0x1d6b" # Linux Foundation
usb_idProduct="0x104" # Multifunction Composite Gadget.
usb_serialnumber="Armbian %%BOARD%%"

echo "Armbian initramfs USB Gadget UMS: found UDC: $(ls /sys/class/udc) for %%BOARD%%"

modprobe g_ffs || echo "Armbian initramfs USB Gadget UMS: Failed to modprobe g_ffs"

mkdir -p /config
mount -t configfs -o nodev,noexec,nosuid configfs /config

CONFIGFS=/config/usb_gadget
GADGET=${CONFIGFS}/g1
CONFIG=${GADGET}/configs/c.1
FUNCTIONS=${GADGET}/functions

if [ -d "${GADGET}" ]; then
	echo "Armbian initramfs USB Gadget UMS: Found existing gadget, removing"
	echo "" > ${GADGET}/UDC

	rm -v ${CONFIG}/mass_storage.usb*

	rmdir -v ${CONFIG}/strings/0x409
	rmdir -v ${CONFIG}

	rmdir -v ${FUNCTIONS}/mass_storage.usb*

	rmdir -v ${GADGET}/strings/0x409

	rmdir -v "${GADGET}"

	echo "Done removing gadget"

	if [ -d "${GADGET}" ]; then
		echo "Gadget still exists... ${GADGET}"
	fi
	exit 0
fi

echo "  Setting up an USB gadget through configfs"
mkdir ${GADGET} || echo "  Couldn't create ${GADGET}"
echo "$usb_idVendor" > "${GADGET}/idVendor"
echo "$usb_idProduct" > "${GADGET}/idProduct"

# Create english (0x409) strings
mkdir ${GADGET}/strings/0x409 || echo "  Couldn't create ${GADGET}/strings/0x409"

echo "$deviceinfo_manufacturer" > "${GADGET}/strings/0x409/manufacturer"
echo "$usb_serialnumber" > "${GADGET}/strings/0x409/serialnumber"
echo "$deviceinfo_name" > "${GADGET}/strings/0x409/product"

# Create configuration instance
mkdir ${CONFIG} || echo "  Couldn't create ${CONFIG}"

counter=0
all_devices=""

for one_block in /sys/class/block/*; do
	partition="${one_block}/partition"
	if [ -f "$partition" ]; then
		continue # we don't wanna expose partitions
	fi
	size_file="${one_block}/size"
	if [ ! -f "$size_file" ]; then
		continue # we don't wanna expose non-block devices
	fi
	size=$(cat "$size_file")
	if [ "$size" -eq 0 ]; then
		continue # we don't wanna expose zero-sized devices
	fi
	# we don't wanna expose devices that smaller than 1Gb (avoids mmcblk0boot0 etc)
	if [ "$size" -lt 1953125 ]; then
		continue
	fi

	ro_file="${one_block}/ro"
	if [ ! -f "$ro_file" ]; then
		continue # we don't wanna expose devices that can't tell if they're read-only
	fi
	ro=$(cat -v "$ro_file")
	if [ "$ro" -ne 0 ]; then
		continue # we don't wanna expose read-only devices
	fi
	phys_block_size_file="${one_block}/queue/physical_block_size"
	if [ ! -f "$phys_block_size_file" ]; then
		continue # we don't wanna expose devices that can't tell us their physical block size
	fi
	phys_block_size=$(cat "$phys_block_size_file")
	if [ "$phys_block_size" -ne 512 ]; then
		continue # we don't wanna expose devices that don't have a 512-byte physical block size
	fi

	# lets guess the real device name...
	basename_device=$(basename "$one_block")
	device_in_dash_dev="/dev/${basename_device}"
	if [ ! -b "$device_in_dash_dev" ]; then
		continue # we don't wanna expose devices that don't have a /dev/ entry
	fi

	description="Armbian${counter} ${basename_device}"

	model_file="${one_block}/device/model"
	if [ -f "$model_file" ]; then
		model=$(cat "$model_file")
		model=$(echo "$model" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		description="${description} ${model}"
	fi

	# hack, skip this
	#if [ "$basename_device" = "mmcblk0" ]; then
	#	continue
	#fi

	echo "one block [${counter}]: $one_block one_block: $one_block size: ${size} ro: ${ro} phys_block_size: ${phys_block_size} basename_device: ${basename_device} device_in_dash_dev: ${device_in_dash_dev} model: '${model}' description: '${description}'"

	# add to all_devices
	all_devices="${all_devices} '${counter}:${description}' "

	# increment counter
	counter=$((counter + 1))

	echo "Create Mass Storage device ${counter} for ${device_in_dash_dev} desc '${description}'"
	MASS_STORAGE_FUNCTION="${FUNCTIONS}/mass_storage.usb${counter}"
	mkdir -p "${MASS_STORAGE_FUNCTION}" || echo "  Couldn't create ${MASS_STORAGE_FUNCTION}"
	echo 1 > "${MASS_STORAGE_FUNCTION}"/stall       # allow bulk EPs
	echo 0 > "${MASS_STORAGE_FUNCTION}"/lun.0/cdrom # don't emulate CD-ROm
	#echo 0 > "${MASS_STORAGE_FUNCTION}"/ro          # write access - disabled for now
	echo 0 > "${MASS_STORAGE_FUNCTION}"/lun.0/nofua # enable Force Unit Access (FUA)
	echo 0 > "${MASS_STORAGE_FUNCTION}"/lun.0/removable
	echo "${description}" > "${MASS_STORAGE_FUNCTION}"/lun.0/inquiry_string
	echo "${device_in_dash_dev}" > "${MASS_STORAGE_FUNCTION}"/lun.0/file

	# Link the function to the config
	ln -s "${MASS_STORAGE_FUNCTION}" "${CONFIG}" || echo "  Couldn't symlink mass_storage.usb${counter}"

done

echo "Done creating functions and configs, enabling UDC.."

echo "$(ls /sys/class/udc)" > ${GADGET}/UDC || echo "  Couldn't write UDC"

#umount /config

echo "Armbian initramfs USB Gadget UMS: done USB Gadget mode."

while true; do
	echo "Armbian initramfs USB Gadget UMS: Board: %%BOARD%%"
	echo "Armbian initramfs USB Gadget UMS: Machine will hang here forever; connect your USB OTG cable and write to disks!"
	echo "Armbian initramfs USB Gadget UMS: UMS devices: ${all_devices}"
	echo "Armbian initramfs USB Gadget UMS: UMS UDC: $(ls /sys/class/udc)"
	echo "Armbian initramfs USB Gadget UMS: Now: $(date)"
	sleep 30
done
