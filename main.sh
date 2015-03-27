#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Main branch
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
# Get your PGP key signing password  								            
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$GPG_PASS" == "" ]; then
GPG_PASS=$(whiptail --passwordbox "\nPlease enter your GPG signing password or leave blank for none. \n\nEnd users - ignore - leave blank. " 14 50 --title "Package signing" 3>&1 1>&2 2>&3)    
exitstatus=$?
if [ $exitstatus != 0 ]; then exit; fi
fi

#--------------------------------------------------------------------------------------------------------------------------------
# Choose for which board you want to compile  								            
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$BOARD" == "" ]; then
	BOARDS="Cubieboard A10 Cubieboard2 A20 Cubietruck A20 Lime A20 Lime2 A20 Micro A20 Bananapi A20 Orangepi A20 Hummingbird A31 Cubox-i imx6 Udoo imx6";
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


#--------------------------------------------------------------------------------------------------------------------------------
# check which distro we are building
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$RELEASE" == "trusty" ]; then
	DISTRIBUTION="Ubuntu"
	else
	DISTRIBUTION="Debian"
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Hostname
#
HOST="$BOARD"


#--------------------------------------------------------------------------------------------------------------------------------
# Load libraries
#--------------------------------------------------------------------------------------------------------------------------------
source $SRC/lib/configuration.sh			# Board configuration
source $SRC/lib/boards.sh 					# Board specific install
source $SRC/lib/common.sh 					# Functions 


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
start=`date +%s`


#--------------------------------------------------------------------------------------------------------------------------------
# display what we are doing 
#--------------------------------------------------------------------------------------------------------------------------------
echo "Building $VERSION."


#--------------------------------------------------------------------------------------------------------------------------------
# download packages for host
#--------------------------------------------------------------------------------------------------------------------------------
download_host_packages
clear
echo "Building $VERSION."


#--------------------------------------------------------------------------------------------------------------------------------
# fetch_from_github [repository, sub directory]
#--------------------------------------------------------------------------------------------------------------------------------
mkdir -p $DEST/output
fetch_from_github "$BOOTLOADER" "$BOOTSOURCE"
fetch_from_github "$LINUXKERNEL" "$LINUXSOURCE"
if [[ -n "$DOCS" ]]; then fetch_from_github "$DOCS" "$DOCSDIR"; fi
if [[ -n "$MISC1" ]]; then fetch_from_github "$MISC1" "$MISC1_DIR"; fi
if [[ -n "$MISC2" ]]; then fetch_from_github "$MISC2" "$MISC2_DIR"; fi
if [[ -n "$MISC3" ]]; then fetch_from_github "$MISC3" "$MISC3_DIR"; fi
if [[ -n "$MISC4" ]]; then fetch_from_github "$MISC4" "$MISC4_DIR"; fi


grab_kernel_version


#--------------------------------------------------------------------------------------------------------------------------------
# Compile source or choose already packed kernel
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$SOURCE_COMPILE" = "yes" ]; then

	# Patching sources
	patching_sources

	# Grab linux kernel version
	grab_kernel_version

	# Compile boot loader
	compile_uboot

	# compile kernel and create archives
	compile_kernel
	if [ "$KERNEL_ONLY" == "yes" ]; then
		echo "Kernel building done."
		echo "Target directory: $DEST/output/kernel"
		echo "File name: $CHOOSEN_KERNEL"
		exit
	fi

else
	
	# Compile u-boot if not exits in cache
	CHOOSEN_UBOOT="$BOARD"_"$BRANCH"_u-boot_"$VER".tgz
	if [ ! -f "$DEST/output/u-boot/$CHOOSEN_UBOOT" ]; then
		compile_uboot
	fi
	
	# choose kernel from ready made
	if [ "$CHOOSEN_KERNEL" == "" ]; then
		choosing_kernel
	fi
fi


#--------------------------------------------------------------------------------------------------------------------------------
# create or use prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
create_debian_template
mount_debian_template


#--------------------------------------------------------------------------------------------------------------------------------
# add kernel to the image

#--------------------------------------------------------------------------------------------------------------------------------
install_kernel


#--------------------------------------------------------------------------------------------------------------------------------
# install board specific applications
#--------------------------------------------------------------------------------------------------------------------------------
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
closing_image

end=`date +%s`
runtime=$(((end-start)/60))
echo "Runtime $runtime min."
