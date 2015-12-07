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
# Main program
#
#

	# We'll use this tittle on all menus
	backtitle="Armbian building script, http://www.armbian.com | Author: Igor Pecovnik"
	mkdir -p $DEST/debug $SRC/userpatches/kernel $SRC/userpatches/u-boot
	echo -e "Place your patches and kernel.config / u-boot.config here.\n" > $SRC/userpatches/readme.txt
	echo -e "They'll be automaticly included if placed here!" >> $SRC/userpatches/readme.txt

	# Install some basic support if not here yet
	if [ $(dpkg-query -W -f='${Status}' whiptail 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
		apt-get install -qq -y whiptail bc >/dev/null 2>&1
	fi 

	if [ $(dpkg-query -W -f='${Status}' bc 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
		apt-get install -qq -y bc >/dev/null 2>&1
	fi 

	if [ $(dpkg-query -W -f='${Status}' dialog 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
		apt-get install -qq -y dialog >/dev/null 2>&1
	fi 

	# if language not set, set to english
	[ "$LANGUAGE" == "" ] && export LANGUAGE="en_US:en"
	
	# default console if not set
	[ "$CONSOLE_CHAR" == "" ] && export CONSOLE_CHAR="UTF-8"

	# Add aptly repository for repo handling                    
	if [ ! -f "/etc/apt/sources.list.d/aptly.list" ]; then
		echo "deb http://repo.aptly.info/ squeeze main" > /etc/apt/sources.list.d/aptly.list
		apt-key adv --keyserver keys.gnupg.net --recv-keys E083A3782A194991
		apt-get update
	fi


	# Choose destination - creating board list from file configuration.sh
	if [ "$BOARD" == "" ]; then
		IFS=";"
		MYARRAY=($(cat $SRC/lib/configuration.sh | awk '/\)#enabled/ || /#des/' | sed -e 's/\t\t//' | sed 's/)#enabled//g' \
		| sed 's/#description //g' | sed -e 's/\t//' | sed ':a;N;$!ba;s/\n/;/g'))
		MYPARAMS=( --title "Choose a board" --backtitle $backtitle --menu "\n Supported:" 34 67 24 )
		i=0; j=1
		while [[ $i -lt ${#MYARRAY[@]} ]];	do
			MYPARAMS+=( "${MYARRAY[$i]}" "         ${MYARRAY[$j]}" )
			i=$[$i+2]; j=$[$j+2]
		done
		whiptail "${MYPARAMS[@]}" 2>results  
		BOARD=$(<results)
		rm results
		unset MYARRAY
	fi
		
	if [ "$BOARD" == "" ]; then echo "ERROR: You have to choose one board"; exit; fi

	
	# This section is left out if we only compile kernel
	if [ "$KERNEL_ONLY" != "yes" ]; then
		
		# Choose for which distribution you want to compile
		if [ "$RELEASE" == "" ]; then
			IFS=";"
			declare -a MYARRAY=('wheezy' 'Debian 7 Wheezy | oldstable' 'jessie' 'Debian 8 Jessie | stable' \
			'trusty' 'Ubuntu Trusty Tahr 14.04.x LTS');
			MYPARAMS=( --title "Choose a distribution" --backtitle $backtitle --menu "\n Root file system:" 10 60 3 )
			i=0; j=1	
			while [[ $i -lt ${#MYARRAY[@]} ]]; do
				MYPARAMS+=( "${MYARRAY[$i]}" "         ${MYARRAY[$j]}" )
				i=$[$i+2]; j=$[$j+2]
			done
			whiptail "${MYPARAMS[@]}" 2>results  
			RELEASE=$(<results)
			rm results
			unset MYARRAY
		fi
	
		if [ "$RELEASE" == "" ]; then echo "ERROR: You have to choose one distribution"; exit; fi


		# Choose to build a desktop
		if [ "$BUILD_DESKTOP" == "" ]; then
			IFS=";"
			declare -a MYARRAY=('No' 'Command line interface' 'Yes' 'XFCE graphical interface');
			MYPARAMS=( --title "Install desktop?" --backtitle $backtitle --menu "" 10 60 3 )
			i=0; j=1
			while [[ $i -lt ${#MYARRAY[@]} ]]; do
				MYPARAMS+=( "${MYARRAY[$i]}" "         ${MYARRAY[$j]}" )
				i=$[$i+2]; j=$[$j+2]
			done
			whiptail "${MYPARAMS[@]}" 2>results  
			BUILD_DESKTOP=$(<results)
			BUILD_DESKTOP=${BUILD_DESKTOP,,}
			rm results
			unset MYARRAY
		fi

		if [ "$BUILD_DESKTOP" == "" ]; then echo "ERROR: You need to choose"; exit; fi

	fi

	
	# Choose for which branch you want to compile
	if [ "$BRANCH" == "" ]; then	
		# get info crom configuration which kernel can be build for certain board
		line_number=$(grep -n "$BOARD)" $SRC/lib/configuration.sh | grep -Eo '^[^:]+' | head -1)
		display_para=$(tail -n +$line_number $SRC/lib/configuration.sh | grep -in "#build" | head -1 | awk '{print $NF}')

		if [[ "$display_para" == *wip ]]; then 
			display_para=${display_para//[!0-9]/}
			whiptail --title "Warning Warning Warning" --msgbox "This is a work in progress. \
			Building might not succeed. \n\nYou must hit OK to continue." 9 63
		fi

		IFS=";"
		
		# define all possible combinations
		if [[ $display_para == "1" ]]; then 
			declare -a MYARRAY=('default' '3.4.x - 3.14.x legacy'); 
		fi
		if [[ $display_para == "2" ]]; then 
			declare -a MYARRAY=('next' 'Latest stable @kernel.org'); 
			fi
		if [[ $display_para == "3" ]]; then 
			declare -a MYARRAY=('default' '3.4.x - 3.14.x legacy' 'next' 'Latest stable @kernel.org'); 
			fi
		if [[ $display_para == "4" ]]; then 
			declare -a MYARRAY=('dev' 'Latest dev @kernel.org'); 
			fi
		if [[ $display_para == "5" ]]; then 
			declare -a MYARRAY=('next' 'Latest stable @kernel.org' 'dev' 'Latest dev @kernel.org'); 
			fi
		if [[ $display_para == "6" || $display_para == "0" ]]; then 
			declare -a MYARRAY=('default' '3.4.x - 3.14.x legacy' 'next' 'Latest stable @kernel.org' 'dev' 'Latest dev @kernel.org'); 
			fi
		
		MYPARAMS=( --title "Choose a branch" --backtitle "$backtitle" --menu "\n Kernel:" 10 60 3 )
		i=0; j=1
		while [[ $i -lt ${#MYARRAY[@]} ]]; do
			MYPARAMS+=( "${MYARRAY[$i]}" "         ${MYARRAY[$j]}" )
			i=$[$i+2]; j=$[$j+2]
		done
		whiptail "${MYPARAMS[@]}" 2>results  
		BRANCH=$(<results)
		rm results
		unset MYARRAY
	fi

	if [ "$BRANCH" == "" ]; then echo "ERROR: You have to choose one branch"; exit; fi

	# don't compile external modules on mainline
	if [ "$BRANCH" != "default" ]; then EXTERNAL="no"; fi

	# back to normal
	unset IFS

	# naming to distro 
	if [[ "$RELEASE" == "precise" || "$RELEASE" == "trusty" ]]; then DISTRIBUTION="Ubuntu"; else DISTRIBUTION="Debian"; fi

	# set hostname to the board	
	HOST="$BOARD"

	# The name of the job
	VERSION="Armbian $REVISION ${BOARD^} $DISTRIBUTION $RELEASE $BRANCH"
	echo `date +"%d.%m.%Y %H:%M:%S"` $VERSION > $DEST/debug/install.log 
	
	# Load libraries
	source $SRC/lib/general.sh					# General functions
	source $SRC/lib/configuration.sh			# Board configuration
	source $SRC/lib/deboostrap.sh 				# System specific install
	source $SRC/lib/distributions.sh 			# System specific install
	source $SRC/lib/patching.sh 				# Source patching
	source $SRC/lib/boards.sh 					# Board specific install
	source $SRC/lib/desktop.sh 					# Desktop specific install
	source $SRC/lib/common.sh 					# Functions 
	source $SRC/lib/makeboarddeb.sh 			# Create board support package 

	# needed if process failed in the middle
	umount_image

	# let's start with fresh screen
	clear
	display_alert "Dependencies check" "@host" "info"

	# optimize build time with 100% CPU usage
	CPUS=$(grep -c 'processor' /proc/cpuinfo)
	if [ "$USEALLCORES" = "yes" ]; then
		CTHREADS="-j$(($CPUS + $CPUS/2))";
	else
		CTHREADS="-j${CPUS}";
	fi

	# Use C compiler cache
	if [ "$USE_CCACHE" = "yes" ]; then 
		CCACHE="ccache"; 
	else 
		CCACHE=""; 
	fi

	# display what we do	
	if [ "$KERNEL_ONLY" == "yes" ]; then
		display_alert "Compiling kernel" "$BOARD" "info"
	else
		display_alert "Building" "$VERSION" "info"
	fi

	# download packages for host	
	PAK="aptly device-tree-compiler pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex ntpdate "
	PAK=$PAK"gawk gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev "
	PAK=$PAK"parted pkg-config expect gcc-arm-linux-gnueabi libncurses5-dev whiptail debian-keyring debian-archive-keyring"
	
	if [ "$(LANGUAGE=english apt-get -s install $PAK | grep "0 newly installed")" == "" ]; then
		install_packet "$PAK" "Checking and installing host dependencies" "host"
	fi

	# sync clock
	if [ "$SYNC_CLOCK" != "no" ]; then
		display_alert "Synching clock" "host" "info"
		ntpdate -s time.ijs.si
	fi
	start=`date +%s`

	# fetch_from_github [repository, sub directory]
	mkdir -p $DEST -p $SOURCES

	if [ "$FORCE_CHECKOUT" = "yes" ]; then FORCE="-f"; else FORCE=""; fi
	
	# Some old branches are tagged
	#if [ "$BRANCH" == "default" ]; then	KERNELTAG="$LINUXBRANCH"; fi

	
	display_alert "source downloading" "@host" "info"
	fetch_from_github "$BOOTLOADER" "$BOOTSOURCE" "$UBOOTTAG" "yes"
	fetch_from_github "$LINUXKERNEL" "$LINUXSOURCE" "$KERNELTAG" "yes"
	
	
	
	if [[ -n "$MISC1" ]]; then fetch_from_github "$MISC1" "$MISC1_DIR" "v1.3"; fi
	if [[ -n "$MISC2" ]]; then fetch_from_github "$MISC2" "$MISC2_DIR"; fi
	if [[ -n "$MISC3" ]]; then fetch_from_github "$MISC3" "$MISC3_DIR"; fi
	if [[ -n "$MISC4" ]]; then fetch_from_github "$MISC4" "$MISC4_DIR"; fi
	if [[ -n "$MISC5" ]]; then fetch_from_github "$MISC5" "$MISC5_DIR"; fi
	# compile sunxi tools
	if [[ $LINUXFAMILY == *sun* ]]; then 
		compile_sunxi_tools
	fi

	# define some packages
	if [[ $BRANCH == "next" ]] ; then KERNEL_BRACH="-next"; UBOOT_BRACH="-next"; else KERNEL_BRACH=""; UBOOT_BRACH=""; fi 
	CHOOSEN_UBOOT=linux-u-boot"$UBOOT_BRACH"-"$BOARD"_"$REVISION"_armhf.deb
	CHOOSEN_KERNEL=linux-image"$KERNEL_BRACH"-"$CONFIG_LOCALVERSION$LINUXFAMILY"_"$REVISION"_armhf.deb
	CHOOSEN_ROOTFS=linux-"$RELEASE"-root"$ROOT_BRACH"-"$BOARD"_"$REVISION"_armhf
	HEADERS_CACHE="${CHOOSEN_KERNEL/image/cache}"

	# cleaning level 0,1,2,3
	cleaning "$CLEAN_LEVEL"

	# patching sources
	patching_sources

	# Compile source if packed not exits
	[ ! -f "$DEST/debs/$CHOOSEN_UBOOT" ] && compile_uboot
	[ ! -f "$DEST/debs/$CHOOSEN_KERNEL" ] && compile_kernel


	if [ "$KERNEL_ONLY" == "yes" ]; then
		[[ -n "$RELEASE" ]] && create_board_package
		display_alert "Kernel building done" "@host" "info"
		display_alert "Target directory" "$DEST/debs/" "info"
		display_alert "File name" "$CHOOSEN_KERNEL" "info"
	else
		
		# create or use prepared root file-system
		custom_debootstrap

		# add kernel to the image
		install_kernel

		# install board specific applications
		install_distribution_specific
		create_board_package
		install_board_specific

		# install desktop
		if [ "$BUILD_DESKTOP" = "yes" ]; then
			install_desktop
		fi

		# install external applications
		if [ "$EXTERNAL" = "yes" ]; then
			install_external_applications
		fi

		# closing image
		closing_image
	fi

	end=`date +%s`
	runtime=$(((end-start)/60))	
	display_alert "Runtime" "$runtime min" "info"