#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

fel_prepare_host()
{
	# install necessary packages; assume that sunxi-tools is installed manually by user
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' nfs-kernel-server 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "nfs-kernel-server" "info"
		apt-get install -q -y --no-install-recommends nfs-kernel-server
	fi
	if [[ ! -f /etc/exports.d/armbian.exports ]]; then
		display_alert "Creating NFS share for" "rootfs" "info"
		mkdir -p /etc/exports.d
		echo "$FEL_ROOTFS *(rw,async,no_subtree_check,no_root_squash,fsid=root)" > /etc/exports.d/armbian.exports
		exportfs -ra
	fi
}

fel_prepare_script()
{
	cp $SRC/lib/scripts/fel-boot.cmd.template $FEL_ROOTFS/boot/boot.cmd
	if [[ -z $FEL_LOCAL_IP ]]; then
		FEL_LOCAL_IP=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
	fi
	sed -i "s#FEL_LOCAL_IP#$FEL_LOCAL_IP#" $FEL_ROOTFS/boot/boot.cmd
	sed -i "s#FEL_ROOTFS#$FEL_ROOTFS#" $FEL_ROOTFS/boot/boot.cmd
	mkimage -C none -A arm -T script -d $FEL_ROOTFS/boot/boot.cmd $FEL_ROOTFS/boot/boot.scr > /dev/null
}

fel_load()
{
	echo > $FEL_ROOTFS/etc/fstab
	if [[ -z $FEL_DTB_FILE ]]; then
		FEL_DTB_FILE=$(grep CONFIG_DEFAULT_DEVICE_TREE $SOURCES/$BOOTSOURCEDIR/.config | cut -d '"' -f2).dtb
	fi
	display_alert "Loading files via" "FEL USB" "info"
	sunxi-fel -v uboot $SOURCES/$BOOTSOURCEDIR/u-boot-sunxi-with-spl.bin \
             write 0x42000000 $FEL_ROOTFS/boot/zImage \
             write 0x43000000 $FEL_ROOTFS/boot/dtb/$FEL_DTB_FILE \
             write 0x43100000 $FEL_ROOTFS/boot/boot.scr
}

fel_prepare_host
fel_prepare_script
fel_load
display_alert "Press <Enter> to finish" "FEL load" "info"
read
service nfs-kernel-server restart
