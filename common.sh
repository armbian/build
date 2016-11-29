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
# compile_kernel
# compile_sunxi_tools
# check_toolchain
# find_toolchain
# advanced_patch
# process_patch_file
# install_external_applications
# write_uboot
# customize_image
# userpatch_create
# overlayfs_wrapper

compile_uboot()
{
	if [[ $USE_OVERLAYFS == yes ]]; then
		local ubootdir=$(overlayfs_wrapper "wrap" "$SOURCES/$BOOTSOURCEDIR" "u-boot_${LINUXFAMILY}_${BRANCH}")
	else
		local ubootdir="$SOURCES/$BOOTSOURCEDIR"
	fi
	cd "$ubootdir"

	[[ $FORCE_CHECKOUT == yes ]] && advanced_patch "u-boot" "$BOOTPATCHDIR" "$BOARD" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "u-boot"

	# read uboot version
	local version=$(grab_version "$ubootdir")

	display_alert "Compiling uboot" "$version" "info"
	# if requires specific toolchain, check if default is suitable
	if [[ -n $UBOOT_NEEDS_GCC ]] && ! check_toolchain "UBOOT" "$UBOOT_NEEDS_GCC" ; then
		# try to find suitable in $SRC/toolchains, exit if not found
		find_toolchain "UBOOT" "$UBOOT_NEEDS_GCC" "UBOOT_TOOLCHAIN"
	fi
	display_alert "Compiler version" "${UBOOT_COMPILER}gcc $(eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} ${UBOOT_COMPILER}gcc -dumpversion)" "info"

	eval CCACHE_BASEDIR="$(pwd)" ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} \
		'make $CTHREADS $BOOTCONFIG CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"' 2>&1 \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config
	[[ -f tools/logos/udoo.bmp ]] && cp $SRC/lib/bin/armbian-u-boot.bmp tools/logos/udoo.bmp
	touch .scmversion

	# patch mainline uboot configuration to boot with old kernels
	if [[ $BRANCH == default && $LINUXFAMILY == sun*i ]] && ! grep -q "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" .config ; then
		echo -e "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y\nCONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> .config
	fi

	# $BOOTDELAY can be set in board family config, ensure autoboot can be stopped even if set to 0
	[[ $BOOTDELAY == 0 ]] && echo -e "CONFIG_ZERO_BOOTDELAY_CHECK=y" >> .config
	[[ -n $BOOTDELAY ]] && sed -i "s/^CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=${BOOTDELAY}/" .config || [[ -f .config ]] && echo "CONFIG_BOOTDELAY=${BOOTDELAY}" >> .config

	eval CCACHE_BASEDIR="$(pwd)" ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} \
		'make $UBOOT_TARGET $CTHREADS CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"' 2>&1 \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	# create .deb package
	local uboot_name=${CHOSEN_UBOOT}_${REVISION}_${ARCH}
	rm -rf $uboot_name
	mkdir -p $uboot_name/usr/lib/{u-boot,$uboot_name} $uboot_name/DEBIAN

	# set up postinstall script
	cat <<-EOF > $uboot_name/DEBIAN/postinst
	#!/bin/bash
	source /usr/lib/u-boot/platform_install.sh
	[[ \$DEVICE == /dev/null ]] && exit 0
	[[ -z \$DEVICE ]] && DEVICE="/dev/mmcblk0"
	[[ \$(type -t setup_write_uboot_platform) == function ]] && setup_write_uboot_platform
	echo "Updating u-boot on device \$DEVICE" >&2
	write_uboot_platform \$DIR \$DEVICE
	sync
	exit 0
	EOF
	chmod 755 $uboot_name/DEBIAN/postinst

	# declare -f on non-defined function does not do anything
	cat <<-EOF > $uboot_name/usr/lib/u-boot/platform_install.sh
	DIR=/usr/lib/$uboot_name
	$(declare -f write_uboot_platform)
	$(declare -f setup_write_uboot_platform)
	EOF

	# set up control file
	cat <<-END > $uboot_name/DEBIAN/control
	Package: linux-u-boot-${BOARD}-${BRANCH}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Provides: armbian-u-boot
	Replaces: armbian-u-boot
	Conflicts: armbian-u-boot, u-boot-sunxi
	Description: Uboot loader $version
	END

	# copy files to build directory
	for f in $UBOOT_FILES; do
		[[ ! -f $f ]] && exit_with_error "U-boot file not found" "$(basename $f)"
		cp $f $uboot_name/usr/lib/$uboot_name
	done

	display_alert "Building deb" "${uboot_name}.deb" "info"
	eval 'dpkg -b $uboot_name 2>&1' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/compilation.log'}
	rm -rf $uboot_name

	[[ ! -f ${uboot_name}.deb || $(stat -c '%s' "${uboot_name}.deb") -lt 5000 ]] && exit_with_error "Building u-boot failed"

	mv ${uboot_name}.deb $DEST/debs/
}

compile_kernel()
{
	if [[ $USE_OVERLAYFS == yes ]]; then
		local kerneldir=$(overlayfs_wrapper "wrap" "$SOURCES/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	else
		local kerneldir="$SOURCES/$LINUXSOURCEDIR"
	fi
	cd "$kerneldir"

	# this is a patch that Ubuntu Trusty compiler works
	# TODO: Check if still required
	if [[ $(patch --dry-run -t -p1 < $SRC/lib/patch/kernel/compiler.patch | grep Reversed) != "" ]]; then
		display_alert "Patching kernel for compiler support"
		[[ $FORCE_CHECKOUT == yes ]] && patch --batch --silent -t -p1 < $SRC/lib/patch/kernel/compiler.patch >> $DEST/debug/output.log 2>&1
	fi

	[[ $FORCE_CHECKOUT == yes ]] && advanced_patch "kernel" "$LINUXFAMILY-$BRANCH" "$BOARD" "$LINUXFAMILY-$BRANCH"

	# create patch for manual source changes in debug mode
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel"

	# read kernel version
	local version=$(grab_version "$kerneldir")

	display_alert "Compiling $BRANCH kernel" "$version" "info"
	# if requires specific toolchain, check if default is suitable
	if [[ -n $KERNEL_NEEDS_GCC ]] && ! check_toolchain "$KERNEL" "$KERNEL_NEEDS_GCC" ; then
		# try to find suitable in $SRC/toolchains, exit if not found
		find_toolchain "KERNEL" "$KERNEL_NEEDS_GCC" "KERNEL_TOOLCHAIN"
	fi
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc $(eval ${KERNEL_TOOLCHAIN:+env PATH=$KERNEL_TOOLCHAIN:$PATH} ${KERNEL_COMPILER}gcc -dumpversion)" "info"

	# use proven config
	if [[ $KERNEL_KEEP_CONFIG != yes || ! -f .config ]]; then
		if [[ -f $SRC/userpatches/$LINUXCONFIG.config ]]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			cp $SRC/userpatches/$LINUXCONFIG.config .config
		else
			display_alert "Using kernel config file" "lib/config/kernel/$LINUXCONFIG.config" "info"
			cp $SRC/lib/config/kernel/$LINUXCONFIG.config .config
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
		# store kernel config in easily reachable place
		cp .config $DEST/kernel.config
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
	IFS='.' read -a array <<< "$version"
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

# check_toolchain <UBOOT|KERNEL> <expression>
#
# checks if system default toolchain version satisfies <expression>
# <expression>: "< x.y"; "> x.y"; "== x.y"
check_toolchain()
{
	local target=$1
	local expression=$2
	local compiler_type="${target}_COMPILER"
	local compiler="${!compiler_type}"
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
	local compiler_type="${target}_COMPILER"
	local compiler="${!compiler_type}"
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
advanced_patch()
{
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
process_patch_file()
{
	local patch=$1
	local description=$2

	# detect and remove files which patch will create
	lsdiff -s --strip=1 $patch | grep '^+' | awk '{print $2}' | xargs -I % sh -c 'rm -f %'

	# main patch command
	echo "Processing file $patch" >> $DEST/debug/patching.log
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
}

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
write_uboot()
{
	local loop=$1
	display_alert "Writing U-boot bootloader" "$loop" "info"
	mkdir -p /tmp/u-boot/
	dpkg -x ${DEST}/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb /tmp/u-boot/
	write_uboot_platform "/tmp/u-boot/usr/lib/${CHOSEN_UBOOT}_${REVISION}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -r /tmp/u-boot/
	sync
}

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $SRC/userpatches/customize-image-host.sh ]] && source $SRC/userpatches/customize-image-host.sh
	cp $SRC/userpatches/customize-image.sh $CACHEDIR/$SDCARD/tmp/customize-image.sh
	chmod +x $CACHEDIR/$SDCARD/tmp/customize-image.sh
	mkdir -p $CACHEDIR/$SDCARD/tmp/overlay
	if [[ $(lsb_release -sc) == xenial ]]; then
		# util-linux >= 2.27 required
		mount -o bind,ro $SRC/userpatches/overlay $CACHEDIR/$SDCARD/tmp/overlay
	else
		mount -o bind $SRC/userpatches/overlay $CACHEDIR/$SDCARD/tmp/overlay
	fi
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $CACHEDIR/$SDCARD /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"
	umount $CACHEDIR/$SDCARD/tmp/overlay
	mountpoint -q $CACHEDIR/$SDCARD/tmp/overlay || rm -r $CACHEDIR/$SDCARD/tmp/overlay
}

userpatch_create()
{
	# create commit to start from clean source
	git add .
	git -c user.name='Armbian User' -c user.email='user@example.org' commit -q -m "Cleaning working copy"

	local patch="$SRC/userpatches/patch/$1-$LINUXFAMILY-$BRANCH.patch"

	# apply previous user debug mode created patches
	[[ -f $patch ]] && display_alert "Applying existing $1 patch" "$patch" "wrn" && patch --batch --silent -p1 -N < $patch

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
	for i in {3..1..1}; do echo -n "$i." && sleep 1; done
}

# overlayfs_wrapper <operation> <workdir> <description>
#
# <operation>: wrap|cleanup
# <workdir>: path to source directory
# <description>: suffix for merged directory to help locating it in /tmp
# return value: new directory
#
# Assumptions/notes:
# - Ubuntu Xenial host
# - /tmp is mounted as tmpfs
# - there is enough space on /tmp
# - UB if running multiple compilation tasks in parallel
# - should not be used with CREATE_PATCHES=yes
#
overlayfs_wrapper()
{
	local operation="$1"
	if [[ $operation == wrap ]]; then
		local srcdir="$2"
		local description="$3"
		mkdir -p /tmp/overlay_components/ /tmp/armbian_build/
		local tempdir=$(mktemp -d --tmpdir="/tmp/overlay_components/")
		local workdir=$(mktemp -d --tmpdir="/tmp/overlay_components/")
		local mergeddir=$(mktemp -d --suffix="_$description" --tmpdir="/tmp/armbian_build/")
		mount -t overlay overlay -o lowerdir="$srcdir",upperdir="$tempdir",workdir="$workdir" "$mergeddir"
		# this is executed in a subshell, so use temp files to pass extra data outside
		echo "$tempdir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_umount
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir"
		return
	fi
	if [[ $operation == cleanup ]]; then
		if [[ -f /tmp/.overlayfs_wrapper_umount ]]; then
			for dir in $(</tmp/.overlayfs_wrapper_umount); do
				[[ $dir == /tmp/* ]] && umount -l "$dir" > /dev/null 2>&1
			done
		fi
		if [[ -f /tmp/.overlayfs_wrapper_cleanup ]]; then
			for dir in $(</tmp/.overlayfs_wrapper_cleanup); do
				[[ $dir == /tmp/* ]] && rm -rf "$dir"
			done
		fi
		rm -f /tmp/.overlayfs_wrapper_umount /tmp/.overlayfs_wrapper_cleanup
	fi
}
