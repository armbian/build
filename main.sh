#!/bin/bash
 
#--------------------------------------------------------------------------------------------------------------------------------
# let's start with fresh screen
clear

#--------------------------------------------------------------------------------------------------------------------------------
# optimize build time with 100% CPU usage
CPUS=$(grep -c 'processor' /proc/cpuinfo)
if [ "$USEALLCORES" = "yes" ]; then
CTHREADS="-j$(($CPUS + $CPUS/2))";
else
CTHREADS="-j${CPUS}";
fi

#--------------------------------------------------------------------------------------------------------------------------------
# to display build time at the end
start=`date +%s`

#--------------------------------------------------------------------------------------------------------------------------------
# display what we are doing 
echo "Building $VERSION."

#--------------------------------------------------------------------------------------------------------------------------------
# Download packages for host
#
download_host_packages

#--------------------------------------------------------------------------------------------------------------------------------
# fetch_from_github [repository, sub directory]
#
mkdir -p $DEST/output
fetch_from_github "$BOOTLOADER" "$BOOTSOURCE"
fetch_from_github "$LINUXKERNEL" "$LINUXSOURCE"
if [[ -n "$DOCS" ]]; then fetch_from_github "$DOCS" "$DOCSDIR"; fi
if [[ -n "$MISC1" ]]; then fetch_from_github "$MISC1" "$MISC1_DIR"; fi
if [[ -n "$MISC2" ]]; then fetch_from_github "$MISC2" "$MISC2_DIR"; fi
if [[ -n "$MISC3" ]]; then fetch_from_github "$MISC3" "$MISC3_DIR"; fi
if [[ -n "$MISC4" ]]; then fetch_from_github "$MISC4" "$MISC4_DIR"; fi

#--------------------------------------------------------------------------------------------------------------------------------
# grab linux kernel version from Makefile
#
VER=$(cat $DEST/$LINUXSOURCE/Makefile | grep VERSION | head -1 | awk '{print $(NF)}')
VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep PATCHLEVEL | head -1 | awk '{print $(NF)}')
VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep SUBLEVEL | head -1 | awk '{print $(NF)}')
EXTRAVERSION=$(cat $DEST/$LINUXSOURCE/Makefile | grep EXTRAVERSION | head -1 | awk '{print $(NF)}')
if [ "$EXTRAVERSION" != "=" ]; then VER=$VER$EXTRAVERSION; fi

# always compile boot loader
compile_uboot

if [ "$SOURCE_COMPILE" = "yes" ]; then
#--------------------------------------------------------------------------------------------------------------------------------
	# Patching sources
	patching_sources

	# compile kernel and create archives
	compile_kernel

	# create tar file
	packing_kernel

else

	# choose kernel from ready made
	choosing_kernel

#--------------------------------------------------------------------------------------------------------------------------------
fi


#--------------------------------------------------------------------------------------------------------------------------------
# create or use prepared root file-system
create_debian_template

#--------------------------------------------------------------------------------------------------------------------------------
# add kernel to the image
install_kernel

#--------------------------------------------------------------------------------------------------------------------------------
# install board specific applications
install_board_specific 

#--------------------------------------------------------------------------------------------------------------------------------
# install external applications
if [ "$EXTERNAL" = "yes" ]; then
install_external_applications
fi

#--------------------------------------------------------------------------------------------------------------------------------
# add some summary to the image
fingerprint_image "$DEST/output/sdcard/root/readme.txt"

#--------------------------------------------------------------------------------------------------------------------------------
# closing image
closing_image

end=`date +%s`
runtime=$(((end-start)/60))
echo "Runtime $runtime min."
