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

# FEL_ROOTFS should be set to path to debootstrapped root filesystem
# unless you want to kill your /etc/fstab and share your rootfs on NFS
# without any access control

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
	if [[ -f $SRC/userpatches/fel-boot.cmd ]]; then
		display_alert "Using custom boot script" "userpatches/fel-boot.cmd" "info"
		cp $SRC/userpatches/fel-boot.cmd $FEL_ROOTFS/boot/boot.cmd
	else
		cp $SRC/lib/scripts/fel-boot.cmd.template $FEL_ROOTFS/boot/boot.cmd
	fi
	if [[ -z $FEL_LOCAL_IP ]]; then
		FEL_LOCAL_IP=$(ifconfig $FEL_NET_IFNAME | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
	fi
	sed -i "s#BRANCH#$BRANCH#" $FEL_ROOTFS/boot/boot.cmd
	sed -i "s#FEL_LOCAL_IP#$FEL_LOCAL_IP#" $FEL_ROOTFS/boot/boot.cmd
	sed -i "s#FEL_ROOTFS#$FEL_ROOTFS#" $FEL_ROOTFS/boot/boot.cmd
	mkimage -C none -A arm -T script -d $FEL_ROOTFS/boot/boot.cmd $FEL_ROOTFS/boot/boot.scr > /dev/null

	# kill /etc/fstab on target
	echo > $FEL_ROOTFS/etc/fstab
	echo "/dev/nfs / nfs defaults 0 0" >> $FEL_ROOTFS/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $FEL_ROOTFS/etc/fstab
}

fel_load()
{
	# update each time in case boot/script.bin link was changed in multi-board images
	if [[ -n $FEL_DTB_FILE ]]; then
		local dtb_file=$FEL_DTB_FILE
	else
		if [[ $BRANCH == default ]]; then
			# script.bin is either regular file or absolute symlink
			if [[ -L $FEL_ROOTFS/boot/script.bin ]]; then
				local dtb_file=boot/bin/$(basename $(readlink $FEL_ROOTFS/boot/script.bin))
			else
				local dtb_file=boot/script.bin
			fi
		else
			if [[ -f $SOURCES/$BOOTSOURCEDIR/.config ]]; then
				local dtb_file=boot/dtb/$(grep CONFIG_DEFAULT_DEVICE_TREE $SOURCES/$BOOTSOURCEDIR/.config | cut -d '"' -f2).dtb
			else
				local dtb_file=boot/dtb/$(grep CONFIG_DEFAULT_DEVICE_TREE $SOURCES/$BOOTSOURCEDIR/configs/$BOOTCONFIG | cut -d '"' -f2).dtb
			fi
		fi
	fi
	[[ $(type -t fel_pre_load) == function ]] && fel_pre_load

	display_alert "Loading files via" "FEL USB" "info"
	sunxi-fel $FEL_EXTRA_ARGS -p uboot $FEL_ROOTFS/usr/lib/${CHOSEN_UBOOT}_${REVISION}_armhf/u-boot-sunxi-with-spl.bin \
		write 0x42000000 $FEL_ROOTFS/boot/zImage \
		write 0x43000000 $FEL_ROOTFS/$dtb_file \
		write 0x43300000 $FEL_ROOTFS/boot/uInitrd \
		write 0x43100000 $FEL_ROOTFS/boot/boot.scr
}

if [[ -f $SRC/userpatches/fel-hooks.sh ]]; then
	display_alert "Using additional FEL hooks in" "userpatches/fel-hooks.sh" "info"
	source $SRC/userpatches/fel-hooks.sh
fi

# basic sanity check
if [[ -n $FEL_ROOTFS ]]; then
	fel_prepare_host
	fel_prepare_target
	[[ $(type -t fel_post_prepare) == function ]] && fel_post_prepare
	RES=b
	while [[ $RES != q ]]; do
		if [[ $FEL_AUTO != yes ]]; then
			display_alert "Connect device in FEL mode and press" "<Enter>" "info"
			read
		fi
		fel_load
		display_alert "Press any key to boot again, <q> to finish" "FEL" "info"
		read -n 1 RES
		echo
	done
	service nfs-kernel-server restart
fi
