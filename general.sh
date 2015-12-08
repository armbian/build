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


# cleaning <#>
# 0 = make clean + del debs
# 1 = only make clean
# 2 = nothing
# 3 = choosing kernel if present
# 4 = del all output and sources

cleaning()
{
case $1 in
		1)	# Clean u-boot and kernel sources
			if [ -d "$SOURCES/$BOOTSOURCEDIR" ]; then 
				display_alert "Cleaning" "$SOURCES/$BOOTSOURCEDIR" "info"
				cd $SOURCES/$BOOTSOURCEDIR
				make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean
			fi
				
	[ -d "$SOURCES/$LINUXSOURCEDIR" ] && display_alert "Cleaning" "$SOURCES/$LINUXSOURCEDIR" "info" && cd $SOURCES/$LINUXSOURCEDIR && make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean	
	[ -f $DEST/cache/building/$HEADERS_CACHE.tgz ] && display_alert "Cleaning" "$HEADERS_CACHE.tgz" "info" && rm -f $DEST/cache/building/$HEADERS_CACHE.tgz
	
;;
2) display_alert "No cleaning" "sources" "info"
;;
3)	# Choosing kernel if debs are present
	if [[ $BRANCH == "next" ]]; then
		MYARRAY=($(ls -1 $DEST/debs/linux-image* | awk '/next/' | sed ':a;N;$!ba;s/\n/;/g'))
		else
		MYARRAY=($(ls -1 $DEST/debs/linux-image* | awk '!/next/' | sed ':a;N;$!ba;s/\n/;/g'))
	fi
	if [[ ${#MYARRAY[@]} != "0" && $KERNEL_ONLY != "yes" ]]; then choosing_kernel; fi
;;
4)	# Delete all in output except repository
	display_alert "Removing deb packages" "$DEST/debs/" "info"
	rm -rf $DEST/debs
	display_alert "Removing root filesystem cache" "$DEST/cache" "info"
	rm -rf $DEST/cache
	display_alert "Removing SD card images" "$DEST/images" "info"
	rm -rf $DEST/images
	display_alert "Removing sources" "$DEST/images" "info"
	rm -rf $SOURCES
;;
*)	# Clean u-boot and kernel sources and remove debs
	[ -d "$SOURCES/$BOOTSOURCEDIR" ] &&
	display_alert "Cleaning" "$SOURCES/$BOOTSOURCEDIR" "info" && cd $SOURCES/$BOOTSOURCEDIR && make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean
	[ -f "$DEST/debs/$CHOOSEN_UBOOT" ] && 
	display_alert "Removing" "$DEST/debs/$CHOOSEN_UBOOT" "info" && rm $DEST/debs/$CHOOSEN_UBOOT
	[ -d "$SOURCES/$LINUXSOURCEDIR" ] && 
	display_alert "Cleaning" "$SOURCES/$LINUXSOURCEDIR" "info" && cd $SOURCES/$LINUXSOURCEDIR && make -s ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean	
	[ -f "$DEST/debs/$CHOOSEN_KERNEL" ] && 
	display_alert "Removing" "$DEST/debs/$CHOOSEN_KERNEL" "info" && rm $DEST/debs/$CHOOSEN_KERNEL
	[ -f $DEST/cache/building/$HEADERS_CACHE.tgz ] && display_alert "Cleaning" "$HEADERS_CACHE.tgz" "info" && rm -f $DEST/cache/building/$HEADERS_CACHE.tgz
;;
esac
}




# fetch_from_github <URL> <directory> <tag> <tagsintosubdir>
#
# parameters:
# <URL>: Git repository
# <directory>: where to place under SOURCES
# <device>: cubieboard, cubieboard2, cubietruck, ...
# <description>: additional description text
# <tagintosubdir>: boolean

fetch_from_github (){
GITHUBSUBDIR=$3
[[ -z "$3" ]] && GITHUBSUBDIR="branchless"
[[ -z "$4" ]] && GITHUBSUBDIR="" # only kernel and u-boot have subdirs for tags
if [ -d "$SOURCES/$2/$GITHUBSUBDIR" ]; then	
	cd $SOURCES/$2/$GITHUBSUBDIR
	git checkout -q $FORCE $3
	display_alert "... updating" "$2" "info"
	PULL=$(git pull -q)
else	
	if [[ -n $3 && -n "$(git ls-remote $1 | grep "$tag")" ]]; then	
		display_alert "... creating a shallow clone" "$2 $3" "info"
		git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3 --depth 1
		cd $SOURCES/$2/$GITHUBSUBDIR		
		git checkout -q $3
	else
		display_alert "... creating a shallow clone" "$2" "info"	
		git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR --depth 1
		cd $SOURCES/$2/$GITHUBSUBDIR
		git checkout -q
	fi
	
fi
cd $SRC
if [ $? -ne 0 ]; then display_alert "Github download failed" "$1" "err"; exit 1; fi
}


display_alert()
#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
{
if [[ $2 != "" ]]; then TMPARA="[\e[0;33m $2 \x1B[0m]"; else unset TMPARA; fi
if [ $3 == "err" ]; then
	echo -e "[\e[0;31m error \x1B[0m] $1 $TMPARA"
elif [ $3 == "wrn" ]; then
	echo -e "[\e[0;35m warn \x1B[0m] $1 $TMPARA"
else
	echo -e "[\e[0;32m o.k. \x1B[0m] $1 $TMPARA"
fi
}


check_error ()
# check last command and display warning only
{
if [ $? -ne 0 ]; then 
		# display warning if patching fails
		display_alert "... failed. More info: debug/install.log" "$1" "wrn"; 
fi
}


install_packet ()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Install packets inside chroot
#--------------------------------------------------------------------------------------------------------------------------------
i=0
j=1
declare -a PACKETS=($1)
skupaj=${#PACKETS[@]}
while [[ $i -lt $skupaj ]]; do
procent=$(echo "scale=2;($j/$skupaj)*100"|bc)
procent=${procent%.*}
		x=${PACKETS[$i]}
		if [[ $3 == "host" ]]; then
			DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $x >> $DEST/debug/install.log  2>&1
		else
			chroot $DEST/cache/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $x" >> $DEST/debug/install.log 2>&1
		fi
		
		if [ $? -ne 0 ]; then display_alert "Installation of package failed" "$INSTALL" "err"; exit 1; fi
		
		if [[ $4 != "quiet" ]]; then
			printf '%.0f\n' $procent | dialog --backtitle "$backtitle" --title "$2" --gauge "\n\n$x" 9 70
		fi
		i=$[$i+1]
		j=$[$j+1]
done
}


#---------------------------------------------------------------------------------------------------------------------------------
# grab_version <PATH>
#
# <PATH>: Extract kernel or uboot version from Makefile
#---------------------------------------------------------------------------------------------------------------------------------
grab_version ()
{
	local var=("VERSION" "PATCHLEVEL" "SUBLEVEL" "EXTRAVERSION")
	unset VER
	for dir in "${var[@]}"; do
		tmp=$(cat $1/Makefile | grep $dir | head -1 | awk '{print $(NF)}' | cut -d '=' -f 2)"#"
		[[ $tmp != "#" ]] && VER=$VER"$tmp"
	done
	VER=${VER//#/.}; VER=${VER%.}; VER="v"${VER//.-/-}
}


choosing_kernel (){
#--------------------------------------------------------------------------------------------------------------------------------
# Choose which kernel to use
#--------------------------------------------------------------------------------------------------------------------------------
IFS=";"	
cd $DEST"/debs/"
if [[ $BRANCH == "next" ]]; then
MYARRAY=($(ls -1 linux-image* | awk '/next/' | sed ':a;N;$!ba;s/\n/;/g'))
else
MYARRAY=($(ls -1 linux-image* | awk '!/next/' | sed ':a;N;$!ba;s/\n/;/g'))
fi
# if there are no precompiled kernels proceed with compilation
if [[ ${#MYARRAY[@]} == "0" ]]; then
SOURCE_COMPILE="yes"
fi

MYPARAMS=( --title "Choose a kernel" --backtitle $backtitle --menu "\n Prebuild packages:" 25 60 16 )
i=0
while [[ $i -lt ${#MYARRAY[@]} ]]
	do
        MYPARAMS+=( "${MYARRAY[$i]}" " -" )
        i=$[$i+1]
	done
whiptail "${MYPARAMS[@]}" 2>results  
CHOOSEN_KERNEL=$(<results)
rm results
unset MYARRAY
}


fingerprint_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image 							            
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Fingerprinting." "$VERSION Linux $VER" "info"
#echo -e "[\e[0;32m ok \x1B[0m] Fingerprinting"

echo "--------------------------------------------------------------------------------" > $1
echo "" >> $1
echo "" >> $1
echo "" >> $1
echo "Title:			$VERSION (unofficial)" >> $1
echo "Kernel:			Linux $VER" >> $1
now="$(date +'%d.%m.%Y')" >> $1
printf "Build date:		%s\n" "$now" >> $1
echo "Author:			Igor Pecovnik, www.igorpecovnik.com" >> $1
echo "Sources: 		http://github.com/igorpecovnik" >> $1
echo "" >> $1
echo "Support: 		http://www.armbian.com" >> $1
echo "" >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1
echo "" >> $1
cat $SRC/lib/LICENSE >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1 
}


umount_image (){
FBTFTMOUNT=$(mount | grep fbtft | awk '{ print $3 }')
umount $FBTFTMOUNT >/dev/null 2>&1
umount -l $DEST/cache/sdcard/dev/pts >/dev/null 2>&1
umount -l $DEST/cache/sdcard/dev >/dev/null 2>&1
umount -l $DEST/cache/sdcard/proc >/dev/null 2>&1
umount -l $DEST/cache/sdcard/sys >/dev/null 2>&1
umount -l $DEST/cache/sdcard/tmp >/dev/null 2>&1
umount -l $DEST/cache/sdcard >/dev/null 2>&1
IFS=" "
x=$(losetup -a |awk '{ print $1 }' | rev | cut -c 2- | rev | tac);
for x in $x; do
	losetup -d $x 
done
}


addtorepo ()
{
# add all deb files to repository
# parameter "remove" dumps all and creates new
# function: cycle trough distributions
DISTROS=("wheezy" "jessie" "trusty")
IFS=" "
j=0
while [[ $j -lt ${#DISTROS[@]} ]]
        do
        # add each packet to distribution
		DIS=${DISTROS[$j]}
		
		# let's drop from publish if exits
		if [ "$(aptly publish list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $DIS)" != "" ]; then 
		aptly publish drop -config=config/aptly.conf $DIS > /dev/null 2>&1
		fi
		#aptly db cleanup -config=config/aptly.conf

		if [ "$1" == "remove" ]; then 
		# remove repository
			aptly repo drop -config=config/aptly.conf $DIS > /dev/null 2>&1
			aptly db cleanup -config=config/aptly.conf > /dev/null 2>&1
		fi
		
		# create repository if not exist
		OUT=$(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $DIS)
		if [[ "$OUT" != "$DIS" ]]; then
			display_alert "Creating section" "$DIS" "info"
			aptly repo create -config=config/aptly.conf -distribution=$DIS -component=main -comment="Armbian stable" $DIS > /dev/null 2>&1
		fi
		
		# add all packages
		aptly repo add -force-replace=true -config=config/aptly.conf $DIS $POT/*.deb
		
		# add all distribution packages
		if [ -d "$POT/$DIS" ]; then
			aptly repo add -force-replace=true -config=config/aptly.conf $DIS $POT/$DIS/*.deb
		fi
		
		aptly publish -passphrase=$GPG_PASS -force-overwrite=true -config=config/aptly.conf -component="main" --distribution=$DIS repo $DIS > /dev/null 2>&1
		
		#aptly repo show -config=config/aptly.conf $DIS
		
        j=$[$j+1]
done
}