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
#
# Source patching functions
#
#


advanced_patch () {
#---------------------------------------------------------------------------------------------------------------------------------
# Patching from certain subdirectory
#---------------------------------------------------------------------------------------------------------------------------------

	# count files
	shopt -s nullglob dotglob # To include hidden files
	local files=($1/*.patch)
	if [ ${#files[@]} -gt 0 ]; then 
		display_alert "Patching $2" "$3" "info"; 
	fi
	
	# go through all patch files
	for patch in $1*.patch; do	
	
		# check if directory exits
		if [[ ! -d $1 ]]; then 
			display_alert "... directory not exists" "$1" "wrn"; 
			break; 
		fi	
		
		# check if files exits
		test -f "$patch" || continue 	
		
		# detect and remove files which patch will create
		LANGUAGE=english patch --batch --dry-run -p1 -N < $patch | grep create \
		| awk '{print $NF}' | sed -n 's/,//p' | xargs -I % sh -c 'rm %'
	
		# main patch command
		echo "$patch" >> $DEST/debug/install.log
		patch --batch --silent -p1 -N < $patch >> $DEST/debug/install.log 2>&1
		
		if [ $? -ne 0 ]; then 			
			# display warning if patching fails
			display_alert "... "${patch#*$1} "failed" "wrn"; 
		else	
			# display patching information
			display_alert "... "${patch#*$1} "succeeded" "info"
		fi
	done

}


patching_sources(){
#--------------------------------------------------------------------------------------------------------------------------------
# Patching kernel
#--------------------------------------------------------------------------------------------------------------------------------

	cd $SOURCES/$LINUXSOURCE

	# fix kernel tag
	if [[ $KERNELTAG == "" ]] ; then 
		KERNELTAG="$LINUXDEFAULT"; 
	fi
	
	if [[ $BRANCH == "next" ]] ; then 
		git checkout $FORCE -q $KERNELTAG; 
	else 
		git checkout $FORCE -q $LINUXDEFAULT; 
	fi

	# what are we building
	grab_kernel_version

	# this is a patch that Ubuntu Trusty compiler works
	if [ "$(patch --dry-run -t -p1 < $SRC/lib/patch/kernel/compiler.patch | grep Reversed)" != "" ]; then 
		patch --batch --silent -t -p1 < $SRC/lib/patch/kernel/compiler.patch > /dev/null 2>&1
	fi

	# this exception is needed if we switch to legacy sunxi sources in configuration.sh to https://github.com/dan-and/linux-sunxi
	if [[ $LINUXKERNEL == *dan-and* && ($BOARD == bana* || $BOARD == orangepi* || $BOARD == lamobo*) ]]; then 
		LINUXFAMILY="banana";
	fi

	# system patches
	advanced_patch "$SRC/lib/patch/kernel/$LINUXFAMILY-$BRANCH/" "kernel" "$LINUXFAMILY-$BRANCH $VER"

	# user patches
	advanced_patch "$SRC/userpatches/kernel/" "kernel with user patches" "$LINUXFAMILY-$BRANCH $VER"

	# it can be changed in this process
	grab_kernel_version


#---------------------------------------------------------------------------------------------------------------------------------
# Patching u-boot
#---------------------------------------------------------------------------------------------------------------------------------
	
	cd $SOURCES/$BOOTSOURCE

	# fix u-boot tag
	if [ -z $UBOOTTAG ] ; then 
		git checkout $FORCE -q $BOOTDEFAULT; 
	else 
		git checkout $FORCE -q $UBOOTTAG;
	fi

	# system patches
	advanced_patch "$SRC/lib/patch/u-boot/$BOOTSOURCE/" "u-boot" "$UBOOTTAG"
	
	# user patches
	advanced_patch "$SRC/userpatches/u-boot/" "u-boot with user patches" "$UBOOTTAG"


#---------------------------------------------------------------------------------------------------------------------------------
# Patching others: FBTFT drivers, ...
#---------------------------------------------------------------------------------------------------------------------------------

	cd $SOURCES/$MISC4_DIR
	display_alert "Patching" "other sources $VER" "info"

	# add small TFT display support  
	if [[ "$FBTFT" = "yes" && $BRANCH != "next" ]]; then
		IFS='.' read -a array <<< "$VER"		
		if (( "${array[0]}" == "3" )) && (( "${array[1]}" < "14" )); then
			git checkout $FORCE -q 06f0bba152c036455ae76d26e612ff0e70a83a82
		else
			git checkout $FORCE -q master
		fi
		
		# DMA disable on FBTFT drivers
		patch --batch -p1 -N -r - < $SRC/lib/patch/misc/bananafbtft.patch >> \
		$DEST/debug/install.log 2>&1 || check_error "fbtft"
		
		# mount bind fbtft sources to kernel sources
		mkdir -p $SOURCES/$LINUXSOURCE/drivers/video/fbtft
		mount --bind $SOURCES/$MISC4_DIR $SOURCES/$LINUXSOURCE/drivers/video/fbtft

		cd $SOURCES/$LINUXSOURCE
		# patch / add fbtft drivers to kernel
		patch --batch -p1 -N -r - < $SRC/lib/patch/kernel/small_lcd_drivers.patch >> \
		$DEST/debug/install.log 2>&1 || check_error "fbtft"
	fi

}