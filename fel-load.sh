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

## NOTES
#
# Set FEL_NET_IFNAME to name of your network interface if you have
# more than one non-loopback interface with assigned IPv4 address
#
# Set FEL_LOCAL_IP to IP address that can be used to reach NFS on your build host
# if it can't be obtained from ifconfig (i.e. port forwarding to VM guest)
#
# It's a good idea to set these settings in userpatches/lib.config if needed


# Set FEL_DTB_FILE to relative path to .dtb or .bin file if it can't be obtained
# from u-boot config (mainline) or boot/script.bin (legacy)
#
# FEL_ROOTFS should be set to path to debootstrapped root filesystem
# unless you want to kill your /etc/fstab and share your rootfs on NFS
# without any access control
#


fel_prepare_host()
{
	# remove and re-add NFS share
	rm -f /etc/exports.d/armbian.exports
	mkdir -p /etc/exports.d
	echo "$FEL_ROOTFS *(rw,async,no_subtree_check,no_root_squash,fsid=root)" > /etc/exports.d/armbian.exports
	exportfs -ra
}

fel_prepare_target()
{
	cp $SRC/lib/scripts/fel-boot.cmd.template $FEL_ROOTFS/boot/boot.cmd
	if [[ -z $FEL_LOCAL_IP ]]; then
		FEL_LOCAL_IP=$(ifconfig $FEL_NET_IFNAME | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
	fi
	sed -i "s#BRANCH#$BRANCH#" $FEL_ROOTFS/boot/boot.cmd
	sed -i "s#FEL_LOCAL_IP#$FEL_LOCAL_IP#" $FEL_ROOTFS/boot/boot.cmd
	sed -i "s#FEL_ROOTFS#$FEL_ROOTFS#" $FEL_ROOTFS/boot/boot.cmd
	mkimage -C none -A arm -T script -d $FEL_ROOTFS/boot/boot.cmd $FEL_ROOTFS/boot/boot.scr > /dev/null

	# kill /etc/fstab on target
	echo > $FEL_ROOTFS/etc/fstab
	if [[ -z $FEL_DTB_FILE ]]; then
		if [[ $BRANCH == default ]]; then
			# script.bin is either regular file or absolute symlink
			if [[ -L $FEL_ROOTFS/boot/script.bin ]]; then
				FEL_DTB_FILE=boot/bin/$(basename $(readlink $FEL_ROOTFS/boot/script.bin))
			else
				FEL_DTB_FILE=boot/script.bin
			fi
		else
			FEL_DTB_FILE=boot/dtb/$(grep CONFIG_DEFAULT_DEVICE_TREE $SOURCES/$BOOTSOURCEDIR/.config | cut -d '"' -f2).dtb
		fi
	fi
}

fel_load()
{
	display_alert "Loading files via" "FEL USB" "info"
	sunxi-fel -v -p uboot $SOURCES/$BOOTSOURCEDIR/u-boot-sunxi-with-spl.bin \
		write 0x42000000 $FEL_ROOTFS/boot/zImage \
		write 0x43000000 $FEL_ROOTFS/$FEL_DTB_FILE \
		write 0x43100000 $FEL_ROOTFS/boot/boot.scr
}

# basic sanity check
if [[ -n $FEL_ROOTFS ]]; then
	fel_prepare_host
	fel_prepare_target
	RES=b
	while [[ $RES == b ]]; do
		display_alert "Connect device in FEL mode and press" "<Enter>" "info"
		read
		fel_load
		display_alert "Press <b> to boot again, <q> to finish" "FEL" "info"
		read -n 1 RES
		echo
	done
	service nfs-kernel-server restart
fi
