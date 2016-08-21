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

compile_uboot()
{
#---------------------------------------------------------------------------------------------------------------------------------
# Compile uboot from sources
#---------------------------------------------------------------------------------------------------------------------------------
	if [[ ! -d $SOURCES/$BOOTSOURCEDIR ]]; then
		exit_with_error "Error building u-boot: source directory does not exist" "$BOOTSOURCEDIR"
	fi

	# read uboot version to variable $VER
	grab_version "$SOURCES/$BOOTSOURCEDIR" "VER"

	# create patch for manual source changes in debug mode
	[[ $DEBUG_MODE == yes ]] && userpatch_create "u-boot"

	display_alert "Compiling uboot" "$VER" "info"
	display_alert "Compiler version" "${UBOOT_COMPILER}gcc $(eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} ${UBOOT_COMPILER}gcc -dumpversion)" "info"
	cd $SOURCES/$BOOTSOURCEDIR

	eval CCACHE_BASEDIR="$(pwd)" ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} \
		'make $CTHREADS $BOOTCONFIG CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"' 2>&1 \
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

	eval CCACHE_BASEDIR="$(pwd)" ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} \
		'make $UBOOT_TARGET $CTHREADS CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"' 2>&1 \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	# create .deb package
	local uboot_name=${CHOSEN_UBOOT}_${REVISION}_${ARCH}
	mkdir -p $DEST/debs/$uboot_name/usr/lib/$uboot_name $DEST/debs/$uboot_name/DEBIAN

	# set up postinstall script
	cat <<-EOF > $DEST/debs/$uboot_name/DEBIAN/postinst
	#!/bin/bash
	[[ \$DEVICE == /dev/null ]] && exit 0
	[[ -z \$DEVICE ]] && DEVICE="/dev/mmcblk0"
	DIR=/usr/lib/$uboot_name
	$(declare -f write_uboot_platform)
	write_uboot_platform \$DIR \$DEVICE
	exit 0
	EOF
	chmod 755 $DEST/debs/$uboot_name/DEBIAN/postinst

	# set up control file
	cat <<-END > $DEST/debs/$uboot_name/DEBIAN/control
	Package: linux-u-boot-${BOARD}-${BRANCH}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Description: Uboot loader $VER
	END

	# copy files to build directory
	for f in $UBOOT_FILES; do
		[[ ! -f $f ]] && exit_with_error "U-boot file not found" "$(basename $f)"
		cp $f $DEST/debs/$uboot_name/usr/lib/$uboot_name
	done

	cd $DEST/debs
	display_alert "Building deb" "$uboot_name.deb" "info"
	dpkg -b $uboot_name >> $DEST/debug/compilation.log 2>&1
	rm -rf $uboot_name

	FILESIZE=$(wc -c $DEST/debs/$uboot_name.deb | cut -f 1 -d ' ')

	if [[ $FILESIZE -lt 50000 ]]; then
		rm $DEST/debs/$uboot_name.deb
		exit_with_error "Building u-boot failed, check configuration"
	fi
}

compile_sunxi_tools()
{
	fetch_from_repo "https://github.com/linux-sunxi/sunxi-tools.git" "sunxi-tools" "branch:master"
	# Compile and install only if git commit hash changed
	cd $SOURCES/sunxi-tools
	if [[ ! -f .commit_id || $(git rev-parse @ 2>/dev/null) != $(<.commit_id) ]]; then
		display_alert "Compiling" "sunxi-tools" "info"
		make -s clean >/dev/null
		make -s tools >/dev/null
		mkdir -p /usr/local/bin/
		make install-tools >/dev/null 2>&1
		git rev-parse @ 2>/dev/null > .commit_id
	fi
}

compile_kernel()
{
#---------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#---------------------------------------------------------------------------------------------------------------------------------

	if [[ ! -d $SOURCES/$LINUXSOURCEDIR ]]; then
		exit_with_error "Error building kernel: source directory does not exist" "$LINUXSOURCEDIR"
	fi

	# read kernel version to variable $VER
	grab_version "$SOURCES/$LINUXSOURCEDIR" "VER"

	# create patch for manual source changes in debug mode
	[[ $DEBUG_MODE == yes ]] && userpatch_create "kernel"

	display_alert "Compiling $BRANCH kernel" "$VER" "info"
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc $(eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} ${KERNEL_COMPILER}gcc -dumpversion)" "info"
	cd $SOURCES/$LINUXSOURCEDIR/

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

	sed -i 's/EXTRAVERSION = .*/EXTRAVERSION =/' Makefile

	if [[ $KERNEL_CONFIGURE != yes ]]; then
		if [[ $BRANCH == default ]]; then
			eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" silentoldconfig'
		else
			eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" olddefconfig'
		fi
	else
		eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" oldconfig'
		eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} 'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" menuconfig'
	fi

	eval CCACHE_BASEDIR="$(pwd)" ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} \
		'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" $KERNEL_IMAGE_TYPE modules dtbs 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling kernel..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	if [[ ${PIPESTATUS[0]} -ne 0 || ! -f arch/$ARCHITECTURE/boot/$KERNEL_IMAGE_TYPE ]]; then
		exit_with_error "Kernel was not built" "@host"
	fi

	# different packaging for 4.3+
	KERNEL_PACKING="deb-pkg"
	IFS='.' read -a array <<< "$VER"
	if (( "${array[0]}" == "4" )) && (( "${array[1]}" >= "3" )); then
		KERNEL_PACKING="bindeb-pkg"
	fi

	# produce deb packages: image, headers, firmware, dtb
	eval CCACHE_BASEDIR="$(pwd)" ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} \
		'make -j1 $KERNEL_PACKING KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$LINUXFAMILY \
		KBUILD_DEBARCH=$ARCH ARCH=$ARCHITECTURE DEBFULLNAME="$MAINTAINER" DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" 2>&1' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Creating kernel packages..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	cd ..
	mv *.deb $DEST/debs/ || exit_with_error "Failed moving kernel DEBs"
}

# check_toolchain <UBOOT|KERNEL> <expression>
#
# checks if system default toolchain version satisfies <expression>
# <expression>: "< x.y"; "> x.y"; "== x.y"
check_toolchain()
{
	local target=$1
	local expression=$2
	eval local compiler=\$${target}_COMPILER
	# get major.minor gcc version
	local gcc_ver=$(${compiler}gcc -dumpversion | grep -oE "^[[:digit:]].[[:digit:]]")
	awk "BEGIN{exit ! ($gcc_ver $expression)}" && return 0
	return 1
}

# find_toolchain <UBOOT|KERNEL> <expression> <var_name>
#
# writes path to toolchain that satisfies <expression> to <var_name>
#
find_toolchain()
{
	local target=$1
	local expression=$2
	local var_name=$3
	local dist=10
	eval local compiler=\$${target}_COMPILER
	local toolchain=""
	# extract target major.minor version from expression
	local target_ver=$(grep -oE "[[:digit:]].[[:digit:]]" <<< "$expression")
	for dir in $SRC/toolchains/*/; do
		# check if is a toolchain for current $ARCH
		[[ ! -f ${dir}bin/${compiler}gcc ]] && continue
		# get toolchain major.minor version
		local gcc_ver=$(${dir}bin/${compiler}gcc -dumpversion | grep -oE "^[[:digit:]].[[:digit:]]")
		# check if toolchain version satisfies requirement
		awk "BEGIN{exit ! ($gcc_ver $expression)}" || continue
		# check if found version is the closest to target
		local d=$(awk '{x = $1 - $2}{printf "%.1f\n", (x > 0) ? x : -x}' <<< "$target_ver $gcc_ver")
		if awk "BEGIN{exit ! ($d < $dist)}" ; then
			dist=$d
			toolchain=${dir}bin
		fi
	done
	[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${compiler}gcc $expression"
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
			if [[ -f $dir/$name ]]; then
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
	echo "Processing file $(basename $patch)" >> $DEST/debug/patching.log
	patch --batch --silent -p1 -N < $patch >> $DEST/debug/patching.log 2>&1

	if [[ $? -ne 0 ]]; then
		display_alert "... $(basename $patch)" "failed" "wrn";
		[[ $EXIT_PATCHING_ERROR == yes ]] && exit_with_error "Aborting due to" "EXIT_PATCHING_ERROR"
	else
		display_alert "... $(basename $patch)" "succeeded" "info"
	fi
	echo >> $DEST/debug/patching.log
}

install_external_applications()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Install external applications example
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Installing extra applications and drivers" "" "info"

for plugin in $SRC/lib/extras/*.sh; do
	source $plugin
done

# MISC5 = sunxi display control
if [[ -n $MISC5_DIR && $BRANCH != next && $LINUXSOURCEDIR == *sunxi* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	cp "$SOURCES/$LINUXSOURCEDIR/include/video/sunxi_disp_ioctl.h" .
	make clean >/dev/null
	make ARCH=$ARCHITECTURE CC="${KERNEL_COMPILER}gcc" KSRC="$SOURCES/$LINUXSOURCEDIR/" >> $DEST/debug/compilation.log 2>&1
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi

# MISC5 = sunxi display control / compile it for sun8i just in case sun7i stuff gets ported to sun8i and we're able to use it
if [[ -n $MISC5_DIR && $BRANCH != next && $LINUXSOURCEDIR == *sun8i* ]]; then
	cd "$SOURCES/$MISC5_DIR"
	wget -q "https://raw.githubusercontent.com/linux-sunxi/linux-sunxi/sunxi-3.4/include/video/sunxi_disp_ioctl.h"
	make clean >/dev/null 2>&1
	make ARCH=$ARCHITECTURE CC="${KERNEL_COMPILER}gcc" KSRC="$SOURCES/$LINUXSOURCEDIR/" >> $DEST/debug/compilation.log 2>&1
	install -m 755 a10disp "$CACHEDIR/sdcard/usr/local/bin"
fi

# h3disp for sun8i/3.4.x
if [[ $LINUXFAMILY == sun8i && $BRANCH == default ]]; then
	install -m 755 "$SRC/lib/scripts/h3disp" "$CACHEDIR/sdcard/usr/local/bin"
	install -m 755 "$SRC/lib/scripts/h3consumption" "$CACHEDIR/sdcard/usr/local/bin"
fi
}

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
write_uboot()
{
	local loop=$1
	display_alert "Writing bootloader" "$loop" "info"
	mkdir -p /tmp/u-boot/
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/u-boot/
	write_uboot_platform "/tmp/u-boot/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot failed to install" "@host"
	rm -r /tmp/u-boot/
	sync
}

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $SRC/userpatches/customize-image-host.sh ]] && source $SRC/userpatches/customize-image-host.sh
	cp $SRC/userpatches/customize-image.sh $CACHEDIR/sdcard/tmp/customize-image.sh
	chmod +x $CACHEDIR/sdcard/tmp/customize-image.sh
	mkdir -p $CACHEDIR/sdcard/tmp/overlay
	if [[ $(lsb_release -sc) == xenial ]]; then
		# util-linux >= 2.27 required
		mount -o bind,ro $SRC/userpatches/overlay $CACHEDIR/sdcard/tmp/overlay
	else
		mount -o bind $SRC/userpatches/overlay $CACHEDIR/sdcard/tmp/overlay
	fi
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $CACHEDIR/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"
	umount $CACHEDIR/sdcard/tmp/overlay
	mountpoint -q $CACHEDIR/sdcard/tmp/overlay || rm -r $CACHEDIR/sdcard/tmp/overlay
}

userpatch_create()
{
	# create commit to start from clean source
	git add .
	git -c user.name='Armbian User' -c user.email='user@example.org' commit -q -m "Cleaning working copy"

	local patch="$SRC/userpatches/patch/$1-$LINUXFAMILY-$BRANCH.patch"

	# apply previous user debug mode created patches
	[[ -f "$patch" && $1 == "u-boot" ]] && display_alert "Applying existing u-boot patch" "$patch" "wrn" && patch --batch --silent -p1 -N < $patch
	[[ -f "$patch" && $1 == "kernel" ]] && display_alert "Applying existing kernel patch" "$patch" "wrn" && patch --batch --silent -p1 -N < $patch

	# prompt to alter source
	display_alert "Make your changes in this directory:" "$(pwd)" "wrn"
	display_alert "Press <Enter> after you are done" "waiting" "wrn"
	read
	tput cuu1
	git add .
	# create patch out of changes
	if ! git diff-index --quiet --cached HEAD; then
		git diff --staged > $patch
		display_alert "You will find your patch here:" "$patch" "info"
	else
		display_alert "No changes found, skipping patch creation" "" "wrn"
	fi
	git reset --soft HEAD~
	for i in {3..1..1};do echo -n "$i." && sleep 1; done
}
