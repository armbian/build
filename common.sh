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

# Functions:
# compile_uboot
# compile_sunxi_tools
# compile_kernel
# check_toolchain
# find_toolchain
# advanced_patch
# process_patch_file
# install_external_applications
# write_uboot
# customize_image

compile_uboot (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile uboot from sources
#---------------------------------------------------------------------------------------------------------------------------------
	if [[ ! -d $SOURCES/$BOOTSOURCEDIR ]]; then
		exit_with_error "Error building u-boot: source directory does not exist" "$BOOTSOURCEDIR"
	fi

	display_alert "Compiling uboot. Please wait." "$VER" "info"
	eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} ${CROSS_COMPILE}gcc --version | head -1 | tee -a $DEST/debug/install.log
	echo
	cd $SOURCES/$BOOTSOURCEDIR

	local cthreads=$CTHREADS
	[[ $LINUXFAMILY == marvell ]] && local MAKEPARA="u-boot.mmc"
	[[ $BOARD == odroidc2 ]] && local MAKEPARA="ARCH=arm" && local cthreads=""

	eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} 'make $CTHREADS $BOOTCONFIG CROSS_COMPILE="$CROSS_COMPILE"' 2>&1 \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
	[[ -f $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp ]] && cp $SRC/lib/bin/armbian-u-boot.bmp $SOURCES/$BOOTSOURCEDIR/tools/logos/udoo.bmp
	touch .scmversion
	
	# patch mainline uboot configuration to boot with old kernels
	if [[ $BRANCH == default && $LINUXFAMILY == sun*i ]] ; then
		if ! grep -q "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" .config ; then
			echo -e "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y\nCONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> .config
		fi
	fi

	eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} 'make $MAKEPARA $cthreads CROSS_COMPILE="$CROSS_COMPILE"' 2>&1 \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	# create .deb package

	local uboot_name=${CHOSEN_UBOOT}_${REVISION}_${ARCH}

	mkdir -p $DEST/debs/$uboot_name/usr/lib/$uboot_name $DEST/debs/$uboot_name/DEBIAN

# set up post install script
cat <<END > $DEST/debs/$uboot_name/DEBIAN/postinst
#!/bin/bash
set -e
if [[ \$DEVICE == "/dev/null" ]]; then exit 0; fi
if [[ \$DEVICE == "" ]]; then DEVICE="/dev/mmcblk0"; fi
if [[ \$DPKG_MAINTSCRIPT_PACKAGE == *cubox* ]] ; then
	( dd if=/usr/lib/$uboot_name/SPL of=\$DEVICE bs=512 seek=2 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.img of=\$DEVICE bs=1K seek=42 status=noxfer ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *guitar* || \$DPKG_MAINTSCRIPT_PACKAGE == roseapple* ]] ; then
	( dd if=/usr/lib/$uboot_name/bootloader.bin of=\$DEVICE bs=512 seek=4097 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot-dtb.bin of=\$DEVICE bs=512 seek=6144 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidxu4* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE seek=1 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/bl2.bin.hardkernel of=\$DEVICE seek=31 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/tzsw.bin.hardkernel of=\$DEVICE seek=719 conv=fsync ) > /dev/null 2>&1
	( dd if=/dev/zero of=\$DEVICE seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidc1* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=1 count=442 conv=fsync ) > /dev/null 2>&1	
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1	
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=64 conv=fsync ) > /dev/null 2>&1	
	( dd if=/dev/zero of=\$DEVICE seek=1024 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *odroidc2* ]] ; then
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=1 count=442 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/bl1.bin.hardkernel of=\$DEVICE bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.bin of=\$DEVICE bs=512 seek=97 conv=fsync ) > /dev/null 2>&1
	( dd if=/dev/zero of=\$DEVICE seek=1249 count=799 bs=512 conv=fsync ) > /dev/null 2>&1 
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *udoo* ]] ; then
	( dd if=/usr/lib/$uboot_name/SPL of=\$DEVICE bs=1k seek=1 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot.img of=\$DEVICE bs=1K seek=69 status=noxfer ) > /dev/null 2>&1
elif [[ \$DPKG_MAINTSCRIPT_PACKAGE == *armada* ]] ; then
	( dd if=/usr/lib/$uboot_name/u-boot.mmc of=\$DEVICE bs=512 seek=1 status=noxfer ) > /dev/null 2>&1
else
	( dd if=/dev/zero of=\$DEVICE bs=1k count=1023 seek=1 status=noxfer ) > /dev/null 2>&1
	( dd if=/usr/lib/$uboot_name/u-boot-sunxi-with-spl.bin of=\$DEVICE bs=1024 seek=8 status=noxfer ) > /dev/null 2>&1
fi
exit 0
END
#

chmod 755 $DEST/debs/$uboot_name/DEBIAN/postinst
# set up control file
cat <<END > $DEST/debs/$uboot_name/DEBIAN/control
Package: linux-u-boot-${BOARD}-${BRANCH}
Version: $REVISION
Architecture: $ARCH
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: kernel
Priority: optional
Description: Uboot loader $VER
END
#

	# copy proper uboot files to place
	if [[ $BOARD == cubox-i* ]] ; then
		[ ! -f "SPL" ] || cp SPL u-boot.img $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == guitar* || $BOARD == roseapple* ]] ; then
		[ ! -f "u-boot-dtb.bin" ] || cp u-boot-dtb.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "$SRC/lib/bin/s500-bootloader.bin" ] || cp $SRC/lib/bin/s500-bootloader.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name/bootloader.bin
	elif [[ $BOARD == odroidxu4 ]] ; then
		[ ! -f "sd_fuse/hardkernel/bl1.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/hardkernel/bl2.bin.hardkernel" ] || cp sd_fuse/hardkernel/bl2.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/hardkernel/tzsw.bin.hardkernel" ] || cp sd_fuse/hardkernel/tzsw.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "u-boot.bin" ] || cp u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name/
	elif [[ $BOARD == odroidc1 ]] ; then
		[ ! -f "sd_fuse/bl1.bin.hardkernel" ] || cp sd_fuse/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/u-boot.bin" ] || cp sd_fuse/u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == odroidc2 ]] ; then
		[ ! -f "sd_fuse/bl1.bin.hardkernel" ] || cp sd_fuse/bl1.bin.hardkernel $DEST/debs/$uboot_name/usr/lib/$uboot_name
		[ ! -f "sd_fuse/u-boot.bin" ] || cp sd_fuse/u-boot.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == udoo* ]] ; then
		[ ! -f "u-boot.img" ] || cp SPL u-boot.img $DEST/debs/$uboot_name/usr/lib/$uboot_name
	elif [[ $BOARD == armada* ]] ; then
		[ ! -f "u-boot.mmc" ] || cp u-boot.mmc $DEST/debs/$uboot_name/usr/lib/$uboot_name
	else
		[ ! -f "u-boot-sunxi-with-spl.bin" ] || cp u-boot-sunxi-with-spl.bin $DEST/debs/$uboot_name/usr/lib/$uboot_name
	fi

	cd $DEST/debs
	display_alert "Target directory" "$DEST/debs/" "info"
	display_alert "Building deb" "$uboot_name.deb" "info"
	dpkg -b $uboot_name > /dev/null
	rm -rf $uboot_name

	FILESIZE=$(wc -c $DEST/debs/$uboot_name.deb | cut -f 1 -d ' ')

	if [[ $FILESIZE -lt 50000 ]]; then
		rm $DEST/debs/$uboot_name.deb
		exit_with_error "Building u-boot failed, check configuration"
	fi
}

compile_sunxi_tools (){
#---------------------------------------------------------------------------------------------------------------------------------
# https://github.com/linux-sunxi/sunxi-tools Tools to help hacking Allwinner devices
#---------------------------------------------------------------------------------------------------------------------------------

	display_alert "Compiling sunxi tools" "@host & target" "info"
	cd $SOURCES/$MISC1_DIR
	make -s clean >/dev/null 2>&1
	rm -f sunxi-fexc sunxi-nand-part
	make -s >/dev/null 2>&1
	cp fex2bin bin2fex /usr/local/bin/
	# make -s clean >/dev/null 2>&1
	# rm -f sunxi-fexc sunxi-nand-part meminfo sunxi-fel sunxi-pio 2>/dev/null
	# NOTE: Fix CC=$CROSS_COMPILE"gcc" before reenabling
	# make $CTHREADS 'sunxi-nand-part' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'sunxi-fexc' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1
	# make $CTHREADS 'meminfo' CC=$CROSS_COMPILE"gcc" >> $DEST/debug/install.log 2>&1

}


compile_kernel (){
#---------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#---------------------------------------------------------------------------------------------------------------------------------

	if [[ ! -d $SOURCES/$LINUXSOURCEDIR ]]; then
		exit_with_error "Error building kernel: source directory does not exist" "$LINUXSOURCEDIR"
	fi

	# read kernel version to variable $VER
	grab_version "$SOURCES/$LINUXSOURCEDIR" "VER"

	display_alert "Compiling $BRANCH kernel" "@host" "info"
	eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} ${CROSS_COMPILE}gcc --version | head -1 | tee -a $DEST/debug/install.log
	echo
	cd $SOURCES/$LINUXSOURCEDIR/

	# adding custom firmware to kernel source
	if [[ -n $FIRMWARE ]]; then unzip -o $SRC/lib/$FIRMWARE -d $SOURCES/$LINUXSOURCEDIR/firmware; fi

	# use proven config
	if [[ $KERNEL_KEEP_CONFIG != yes || ! -f $SOURCES/$LINUXSOURCEDIR/.config ]]; then
		if [[ -f $SRC/userpatches/$LINUXCONFIG.config ]]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			cp $SRC/userpatches/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		else
			display_alert "Using kernel config file" "lib/config/kernel/$LINUXCONFIG.config" "info"
			cp $SRC/lib/config/kernel/$LINUXCONFIG.config $SOURCES/$LINUXSOURCEDIR/.config
		fi
	fi

	# hack for deb builder. To pack what's missing in headers pack.
	cp $SRC/lib/patch/misc/headers-debian-byteshift.patch /tmp

	export LOCALVERSION="-$LINUXFAMILY"

	# We can use multi threading here but not later since it's not working. This way of compilation is much faster.
	if [[ $KERNEL_CONFIGURE != yes ]]; then
		if [[ $BRANCH == default ]]; then
			eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CROSS_COMPILE" silentoldconfig'
		else
			eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CROSS_COMPILE" olddefconfig'
		fi
	else
		eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CROSS_COMPILE" oldconfig'
		eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CROSS_COMPILE" menuconfig'
	fi

	eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CROSS_COMPILE" $KERNEL_IMAGE_TYPE modules dtbs 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling kernel..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	if [[ ${PIPESTATUS[0]} -ne 0 || ! -f arch/$ARCHITECTURE/boot/$KERNEL_IMAGE_TYPE ]]; then
		exit_with_error "Kernel was not built" "@host"
	fi

	# different packaging for 4.3+ // probably temporaly soution
	KERNEL_PACKING="deb-pkg"
	IFS='.' read -a array <<< "$VER"
	if (( "${array[0]}" == "4" )) && (( "${array[1]}" >= "3" )); then
		KERNEL_PACKING="bindeb-pkg"
	fi

	# produce deb packages: image, headers, firmware, dtb
	eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make -j1 $KERNEL_PACKING KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$LINUXFAMILY \
		KBUILD_DEBARCH=$ARCH ARCH=$ARCHITECTURE DEBFULLNAME="$MAINTAINER" DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 ' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Creating kernel packages..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	cd ..
	mv *.deb $DEST/debs/ || exit_with_error "Failed moving kernel DEBs"
}

# check_toolchain <expression> <path>
#
# checks if system default toolchain version satisfies <expression>
# <expression>: "< x.y"; "> x.y"; "== x.y"
check_toolchain()
{
	local expression=$1
	local path=$2
	# get major.minor gcc version
	local gcc_ver=$(${COMPILER}gcc -dumpversion | grep -oE "^[[:digit:]].[[:digit:]]")
	awk "BEGIN{exit ! ($gcc_ver $expression)}" && return 0
	return 1
}

# find_toolchain <expression> <var_name>
#
# writes path to toolchain that satisfies <expression> to <var_name>
#
find_toolchain()
{
	local expression=$1
	local var_name=$2
	local dist=10
	local toolchain=""
	for dir in $SRC/toolchains/*/; do
		# check if is a toolchain for current $ARCH
		[[ ! -f ${dir}bin/${COMPILER}gcc ]] && continue
		# get toolchain major.minor version
		local gcc_ver=$(${dir}bin/${COMPILER}gcc -dumpversion | grep -oE "^[[:digit:]].[[:digit:]]")
		# check if toolchain version satisfies requirement
		awk "BEGIN{exit ! ($gcc_ver $expression)}" || continue
		# extract target major.minor version from expression
		local target_ver=$(grep -oE "[[:digit:]].[[:digit:]]" <<< "$expression")
		# check if found version is the closest to target
		local d=$(awk '{x = $1 - $2}{printf "%.1f\n", (x > 0) ? x : -x}' <<< "$target_ver $gcc_ver")
		if awk "BEGIN{exit ! ($d < $dist)}" ; then
			dist=$d
			toolchain=${dir}bin
		fi
	done
	eval $"$var_name"="$toolchain"
}

# advanced_patch <dest> <family> <device> <description>
#
# parameters:
# <dest>: u-boot, kernel
# <family>: u-boot: u-boot, u-boot-neo; kernel: sun4i-default, sunxi-next, ...
# <device>: cubieboard, cubieboard2, cubietruck, ...
# <description>: additional description text
#
# priority:
# $SRC/userpatches/<dest>/<family>/<device>
# $SRC/userpatches/<dest>/<family>
# $SRC/lib/patch/<dest>/<family>/<device>
# $SRC/lib/patch/<dest>/<family>
#
advanced_patch () {

	local dest=$1
	local family=$2
	local device=$3
	local description=$4

	display_alert "Started patching process for" "$dest $description" "info"
	display_alert "Looking for user patches in" "userpatches/$dest/$family" "info"

	local names=()
	local dirs=("$SRC/userpatches/$dest/$family/$device" "$SRC/userpatches/$dest/$family" "$SRC/lib/patch/$dest/$family/$device" "$SRC/lib/patch/$dest/$family")

	# required for "for" command
	shopt -s nullglob dotglob
	# get patch file names
	for dir in "${dirs[@]}"; do
		for patch in $dir/*.patch; do
			names+=($(basename $patch))
		done
	done
	# remove duplicates
	local names_s=($(echo "${names[@]}" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' '))
	# apply patches
	for name in "${names_s[@]}"; do
		for dir in "${dirs[@]}"; do
			if [[ -f $dir/$name || -L $dir/$name ]]; then
				if [[ -s $dir/$name ]]; then
					process_patch_file "$dir/$name" "$description"
				else
					display_alert "... $name" "skipped" "info"
				fi
				break # next name
			fi
		done
	done
}

# process_patch_file <file> <description>
#
# parameters:
# <file>: path to patch file
# <description>: additional description text
#
process_patch_file() {

	local patch=$1
	local description=$2

	# detect and remove files which patch will create
	LANGUAGE=english patch --batch --dry-run -p1 -N < $patch | grep create \
		| awk '{print $NF}' | sed -n 's/,//p' | xargs -I % sh -c 'rm %'

	# main patch command
	echo "$patch $description" >> $DEST/debug/install.log
	patch --batch --silent -p1 -N < $patch >> $DEST/debug/install.log 2>&1

	if [ $? -ne 0 ]; then
		display_alert "... $(basename $patch)" "failed" "wrn";
		if [[ $EXIT_PATCHING_ERROR == "yes" ]]; then exit_with_error "Aborting due to" "EXIT_PATCHING_ERROR"; fi
	else
		display_alert "... $(basename $patch)" "succeeded" "info"
	fi
}

install_external_applications ()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Install external applications example
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing extra applications and drivers" "" "info"

# cleanup for install_kernel and install_board_specific
umount $CACHEDIR/sdcard/tmp >/dev/null 2>&1

for plugin in $SRC/lib/extras/*.sh; do
	source $plugin
done

# MISC5 = sunxi display control
if [[ -n $MISC5_DIR && $BRANCH != next && $LINUXSOURCEDIR == *sunxi* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	cp "$SOURCES/$LINUXSOURCEDIR/include/video/sunxi_disp_ioctl.h" .
	make clean >/dev/null
	make ARCH=$ARCHITECTURE CC="${CROSS_COMPILE}gcc" KSRC="$SOURCES/$LINUXSOURCEDIR/" >> $DEST/debug/compilation.log 2>&1
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi

# MISC5 = sunxi display control / compile it for sun8i just in case sun7i stuff gets ported to sun8i and we're able to use it
if [[ -n $MISC5_DIR && $BRANCH != next && $LINUXSOURCEDIR == *sun8i* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	wget -q "https://raw.githubusercontent.com/linux-sunxi/linux-sunxi/sunxi-3.4/include/video/sunxi_disp_ioctl.h"
	make clean >/dev/null 2>&1
	make ARCH=$ARCHITECTURE CC="${CROSS_COMPILE}gcc" KSRC="$SOURCES/$LINUXSOURCEDIR/" >> $DEST/debug/compilation.log 2>&1
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi

# h3disp/sun8i-corekeeper.sh for sun8i/3.4.x
if [[ $LINUXFAMILY == sun8i && $BRANCH == default ]]; then
	install -m 755 "$SRC/lib/scripts/h3disp" "$CACHEDIR/sdcard/usr/local/bin"
	install -m 755 "$SRC/lib/scripts/sun8i-corekeeper.sh" "$CACHEDIR/sdcard/usr/local/bin"
	sed -i 's|^exit\ 0$|/usr/local/bin/sun8i-corekeeper.sh \&\n\n&|' "$CACHEDIR/sdcard/etc/rc.local"
fi
}

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
write_uboot()
{
	LOOP=$1
	display_alert "Writing bootloader" "$LOOP" "info"
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/

	if [[ $BOARD == *cubox* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/SPL of=$LOOP bs=512 seek=2 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.img of=$LOOP bs=1K seek=42 status=noxfer >/dev/null 2>&1)
	elif [[ $BOARD == *armada* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.mmc of=$LOOP bs=512 seek=1 status=noxfer >/dev/null 2>&1)
	elif [[ $BOARD == *udoo* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/SPL of=$LOOP bs=1k seek=1 status=noxfer >/dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.img of=$LOOP bs=1k seek=69 conv=fsync >/dev/null 2>&1)
	elif [[ $BOARD == *guitar* || $BOARD == *roseapple* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bootloader.bin of=$LOOP bs=512 seek=4097 conv=fsync > /dev/null 2>&1)
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot-dtb.bin of=$LOOP bs=512 seek=6144 conv=fsync > /dev/null 2>&1)
	elif [[ $BOARD == *odroidxu4* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP seek=1 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl2.bin.hardkernel of=$LOOP seek=31 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=63 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/tzsw.bin.hardkernel of=$LOOP seek=719 conv=fsync ) > /dev/null 2>&1
		( dd if=/dev/zero of=$LOOP seek=1231 count=32 bs=512 conv=fsync ) > /dev/null 2>&1		
	elif [[ $BOARD == *odroidc1* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=1 count=442 conv=fsync ) > /dev/null 2>&1	
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1	
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=64 conv=fsync ) > /dev/null 2>&1	
		( dd if=/dev/zero of=$LOOP seek=1024 count=32 bs=512 conv=fsync ) > /dev/null 2>&1
	elif [[ $BOARD == *odroidc2* ]] ; then
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=1 count=442 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/bl1.bin.hardkernel of=$LOOP bs=512 skip=1 seek=1 conv=fsync ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot.bin of=$LOOP bs=512 seek=97 conv=fsync ) > /dev/null 2>&1
		( dd if=/dev/zero of=$LOOP seek=1249 count=799 bs=512 conv=fsync ) > /dev/null 2>&1
	else
		( dd if=/dev/zero of=$LOOP bs=1k count=1023 seek=1 status=noxfer ) > /dev/null 2>&1
		( dd if=/tmp/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}/u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer >/dev/null 2>&1)
	fi
	[[ $? -ne 0 ]] && exit_with_error "U-boot failed to install" "@host"
	rm -r /tmp/usr
	sync
}

customize_image()
{
	cp $SRC/userpatches/customize-image.sh $CACHEDIR/sdcard/tmp/customize-image.sh
	chmod +x $CACHEDIR/sdcard/tmp/customize-image.sh
	mkdir -p $CACHEDIR/sdcard/tmp/overlay
	mount --bind $SRC/userpatches/overlay $CACHEDIR/sdcard/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"
	umount $CACHEDIR/sdcard/tmp/overlay
}
