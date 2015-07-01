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


#--------------------------------------------------------------------------------------------------------------------------------
# currently there is no option to create an image without root
# you can compile a kernel but you can complete the whole process
# if you find a way, please submit code corrections. Thanks.
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$UID" -ne 0 ]
	then echo "Please run as root"
	exit
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Choose destination
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$BOARD" == "" ]; then
	BOARDS="AW-som-a20 A20 Cubieboard A10 Cubieboard2 A20 Cubietruck A20 Lime A20 Lime2 A20 Micro A20 Bananapi A20 \
	Bananapipro A20 Lamobo-R1 A20 Orangepi A20 Pcduino3nano A20 Hummingbird A31 Cubox-i imx6 Udoo imx6 Udoo-Neo imx6";
	MYLIST=`for x in $BOARDS; do echo $x ""; done`
	whiptail --title "Choose a board" --backtitle "" --menu "\nWhich one?" 18 30 8 $MYLIST 2>results    
	BOARD=$(<results)
	BOARD=${BOARD,,}
	rm results
fi
# exit the script on cancel
if [ "$BOARD" == "" ]; then echo "ERROR: You have to choose one board"; exit; fi


#--------------------------------------------------------------------------------------------------------------------------------
# Choose for which distribution you want to compile
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$RELEASE" == "" ]; then
	RELEASE="wheezy Debian jessie Debian trusty Ubuntu";
	MYLIST=`for x in $RELEASE; do echo $x ""; done`
	whiptail --backtitle "" --title "Select distribution" --menu "" 12 30 4 $MYLIST 2>results    
	RELEASE=$(<results)
	rm results
fi
# exit the script on cancel
if [ "$RELEASE" == "" ]; then echo "ERROR: You have to choose one distribution"; exit; fi


#--------------------------------------------------------------------------------------------------------------------------------
# Choose for which branch you want to compile
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$BRANCH" == "" ]; then
	BRANCH="default 3.4.x-3.14.x next mainline";
	MYLIST=`for x in $BRANCH; do echo $x ""; done`
	whiptail --backtitle "" --title "Select distribution" --menu "" 12 30 4 $MYLIST 2>results    
	BRANCH=$(<results)
	rm results
fi
# exit the script on cancel
if [ "$BRANCH" == "" ]; then echo "ERROR: You have to choose one branch"; exit; fi

# default console if not set
if [ "$CONSOLE_CHAR" == "" ]; then CONSOLE_CHAR="UTF-8"; fi

#--------------------------------------------------------------------------------------------------------------------------------
# check which distro we are building
#--------------------------------------------------------------------------------------------------------------------------------
if [[ "$RELEASE" == "precise" || "$RELEASE" == "trusty" ]]; then
	DISTRIBUTION="Ubuntu"
	else
	DISTRIBUTION="Debian"
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Let's fix hostname to the board
#
HOST="$BOARD"


#--------------------------------------------------------------------------------------------------------------------------------
# Load libraries
#--------------------------------------------------------------------------------------------------------------------------------
source $SRC/lib/configuration.sh			# Board configuration
source $SRC/lib/deboostrap.sh 			# System specific install
source $SRC/lib/distributions.sh 			# System specific install
source $SRC/lib/patching.sh 				# Source patching
source $SRC/lib/boards.sh 					# Board specific install
source $SRC/lib/common.sh 					# Functions 

if [ "$SOURCE_COMPILE" != "yes" ]; then
	choosing_kernel
	if [ "$CHOOSEN_KERNEL" == "" ]; then echo "ERROR: You have to choose one kernel"; exit; fi
fi


#--------------------------------------------------------------------------------------------------------------------------------
# The name of the job
#--------------------------------------------------------------------------------------------------------------------------------
VERSION="${BOARD^} $DISTRIBUTION $REVISION $RELEASE $BRANCH"

 
#--------------------------------------------------------------------------------------------------------------------------------
# let's start with fresh screen
#--------------------------------------------------------------------------------------------------------------------------------
clear


#--------------------------------------------------------------------------------------------------------------------------------
# optimize build time with 100% CPU usage
#--------------------------------------------------------------------------------------------------------------------------------
CPUS=$(grep -c 'processor' /proc/cpuinfo)
if [ "$USEALLCORES" = "yes" ]; then
CTHREADS="-j$(($CPUS + $CPUS/2))";
else
CTHREADS="-j${CPUS}";
fi


#--------------------------------------------------------------------------------------------------------------------------------
# to display build time at the end
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$KERNEL_ONLY" == "yes" ]; then
	echo -e "[\e[0;32m ok \x1B[0m] Compiling kernel"
	else
	echo -e "[\e[0;32m ok \x1B[0m] Building $VERSION"
fi
echo -e "[\e[0;32m ok \x1B[0m] Syncing clock"
ntpdate -s time.ijs.si
start=`date +%s`


#--------------------------------------------------------------------------------------------------------------------------------
# download packages for host
#--------------------------------------------------------------------------------------------------------------------------------
download_host_packages


#--------------------------------------------------------------------------------------------------------------------------------
# fetch_from_github [repository, sub directory]
#--------------------------------------------------------------------------------------------------------------------------------
mkdir -p $DEST/output

if [ "$FORCE" = "yes" ]; then
	FORCE="-f"
	else
	FORCE=""
fi

fetch_from_github "$BOOTLOADER" "$BOOTSOURCE"
fetch_from_github "$LINUXKERNEL" "$LINUXSOURCE"
if [[ -n "$DOCS" ]]; then fetch_from_github "$DOCS" "$DOCSDIR"; fi
if [[ -n "$MISC1" ]]; then fetch_from_github "$MISC1" "$MISC1_DIR"; fi
if [[ -n "$MISC2" ]]; then fetch_from_github "$MISC2" "$MISC2_DIR"; fi
if [[ -n "$MISC3" ]]; then fetch_from_github "$MISC3" "$MISC3_DIR"; fi
if [[ -n "$MISC4" ]]; then fetch_from_github "$MISC4" "$MISC4_DIR"; fi
if [[ -n "$MISC5" ]]; then fetch_from_github "$MISC5" "$MISC5_DIR"; fi

# compile sunxi tools
compile_sunxi_tools

# Patching sources
patching_sources

# What are we building
grab_kernel_version

#--------------------------------------------------------------------------------------------------------------------------------
# Compile source or choose already packed kernel
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$SOURCE_COMPILE" = "yes" ]; then

	# Compile boot loader
	compile_uboot

	# compile kernel and create archives
	compile_kernel
	if [ "$KERNEL_ONLY" == "yes" ]; then
		echo -e "[\e[0;32m ok \x1B[0m] Kernel building done"
		echo -e "[\e[0;32m ok \x1B[0m] Target directory: $DEST/output/kernel"
		echo -e "[\e[0;32m ok \x1B[0m] File name: $CHOOSEN_KERNEL"
		exit
	fi

else
	
	# Compile u-boot if not exits in cache
	CHOOSEN_UBOOT="linux-u-boot-$VER-"$BOARD"_"$REVISION"_armhf"
	UBOOT_PCK="linux-u-boot-$VER-"$BOARD
	if [ ! -f "$DEST/output/u-boot/$CHOOSEN_UBOOT".deb ]; then
		compile_uboot
	fi
	
	# choose kernel from ready made
	#if [ "$CHOOSEN_KERNEL" == "" ]; then
	#	sleep 2
	#	choosing_kernel
	#fi

fi



#--------------------------------------------------------------------------------------------------------------------------------
# create or use prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
#create_system_template
#mount_system_template
custom_debootstrap

#--------------------------------------------------------------------------------------------------------------------------------
# add kernel to the image
#--------------------------------------------------------------------------------------------------------------------------------
install_kernel


#--------------------------------------------------------------------------------------------------------------------------------
# install board specific applications
#--------------------------------------------------------------------------------------------------------------------------------
install_system_specific
install_board_specific


#--------------------------------------------------------------------------------------------------------------------------------
# install desktop
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$BUILD_DESKTOP" = "yes" ]; then
install_desktop
fi


#--------------------------------------------------------------------------------------------------------------------------------
# install external applications
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$EXTERNAL" = "yes" ]; then
install_external_applications
fi


#--------------------------------------------------------------------------------------------------------------------------------
# add some summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
fingerprint_image "$DEST/output/sdcard/root/readme.txt"


#--------------------------------------------------------------------------------------------------------------------------------
# closing image
#--------------------------------------------------------------------------------------------------------------------------------
#read
closing_image

end=`date +%s`
runtime=$(((end-start)/60))
echo -e "[\e[0;32m ok \x1B[0m] Runtime $runtime min"