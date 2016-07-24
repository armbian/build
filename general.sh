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
# cleaning
# exit_with_error
# get_package_list_hash
# fetch_from_github
# display_alert
# grab_version
# fingerprint_image
# addtorepo
# prepare_host

# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs
# "cache" - delete output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#
cleaning()
{
	case $1 in
		make)	# clean u-boot and kernel sources
		[[ -d $SOURCES/$BOOTSOURCEDIR ]] && display_alert "Cleaning" "$BOOTSOURCEDIR" "info" && cd $SOURCES/$BOOTSOURCEDIR && eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} 'make clean CROSS_COMPILE="$CCACHE $UBOOT_COMPILER" >/dev/null 2>/dev/null'
		[[ -d $SOURCES/$LINUXSOURCEDIR ]] && display_alert "Cleaning" "$LINUXSOURCEDIR" "info" && cd $SOURCES/$LINUXSOURCEDIR && eval ${UBOOT_TOOLCHAIN:+env PATH=$UBOOT_TOOLCHAIN:$PATH} 'make clean CROSS_COMPILE="$CCACHE $UBOOT_COMPILER" >/dev/null 2>/dev/null'
		;;

		debs) # delete output/debs for current branch and family
		if [[ -d $DEST/debs ]]; then
			display_alert "Cleaning $DEST/debs for" "$BOARD $BRANCH" "info"
			# easier than dealing with variable expansion and escaping dashes in file names
			find $DEST/debs -name '*.deb' | grep -E "${CHOSEN_KERNEL/image/.*}|$CHOSEN_UBOOT" | xargs rm -f
			[[ -n $RELEASE ]] && rm -f $DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_*_${ARCH}.deb
		fi
		;;

		alldebs) # delete output/debs
		[[ -d $DEST/debs ]] && display_alert "Cleaning" "$DEST/debs" "info" && rm -rf $DEST/debs/*
		;;

		cache) # delete output/cache
		[[ -d $CACHEDIR ]] && display_alert "Cleaning" "$CACHEDIR" "info" && find $CACHEDIR/ -type f -delete
		;;

		images) # delete output/images
		[[ -d $DEST/images ]] && display_alert "Cleaning" "$DEST/images" "info" && rm -rf $DEST/images/*
		;;

		sources) # delete output/sources
		[[ -d $SOURCES ]] && display_alert "Cleaning" "$SOURCES" "info" && rm -rf $SOURCES/*
		;;

		*) # unknown
		display_alert "Cleaning: unrecognized option" "$1" "wrn"
		;;
	esac
}

# exit_with_error <message> <highlight>
#
# a way to terminate build process
# with verbose error message
#

exit_with_error()
{
	local _file=$(basename ${BASH_SOURCE[1]})
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2

	display_alert "ERROR in function $_function" "$_file:$_line" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"
	exit -1
}

# get_package_list_hash <package_list>
#
# outputs md5hash for space-separated <package_list>
# for rootfs cache

get_package_list_hash()
{
	echo $(printf '%s\n' $PACKAGE_LIST | sort -u | md5sum | cut -d' ' -f 1)
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
local githuburl=$1
[[ -z "$3" ]] && GITHUBSUBDIR="branchless"
[[ -z "$4" ]] && GITHUBSUBDIR="" # only kernel and u-boot have subdirs for tags
if [ -d "$SOURCES/$2/$GITHUBSUBDIR" ]; then
	cd $SOURCES/$2/$GITHUBSUBDIR
	git checkout -q $FORCE $3 2> /dev/null	
	local bar_1=$(git ls-remote $githuburl --tags $GITHUBSUBDIR* | sed -n '1p' | cut -f1 | cut -c1-7)
	local bar_2=$(git ls-remote $githuburl --tags $GITHUBSUBDIR* | sed -n '2p' | cut -f1 | cut -c1-7)
	local bar_3=$(git ls-remote $githuburl --tags HEAD * | sed -n '1p' | cut -f1 | cut -c1-7)
	local localbar="$(git rev-parse HEAD | cut -c1-7)"
	
	# debug
	# echo "git ls-remote $githuburl --tags $GITHUBSUBDIR* | sed -n '1p' | cut -f1"
	# echo "git ls-remote $githuburl --tags $GITHUBSUBDIR* | sed -n '2p' | cut -f1"	
	# echo "git ls-remote $githuburl --tags HEAD * | sed -n '1p' | cut -f1"		
	# echo "$3 - $bar_1 || $bar_2 = $localbar"
	# echo "$3 - $bar_3 = $localbar"
	
	# ===>> workaround >> [[ $bar_1 == "" && $bar_2 == "" ]]
	
	if [[ "$3" != "" ]] && [[ "$bar_1" == "$localbar" || "$bar_2" == "$localbar" ]] || [[ "$3" == "" && "$bar_3" == "$localbar" ]] || [[ $bar_1 == "" && $bar_2 == "" ]]; then
		display_alert "... you have latest sources" "$2 $3" "info"
	else		
		if [ "$DEBUG_MODE" != yes ]; then
			display_alert "... your sources are outdated - creating new shallow clone" "$2 $3" "info"
			if [[ -z "$GITHUBSUBDIR" ]]; then 
				rm -rf $SOURCES/$2".old"
				mv $SOURCES/$2 $SOURCES/$2".old" 
			else
				rm -rf $SOURCES/$2/$GITHUBSUBDIR".old"
				mv $SOURCES/$2/$GITHUBSUBDIR $SOURCES/$2/$GITHUBSUBDIR".old" 
			fi
			
			if [[ -n $3 && -n "$(git ls-remote $1 | grep "$tag")" ]]; then
				git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3 --depth 1 || git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3
			else
				git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR --depth 1
			fi
		fi
		cd $SOURCES/$2/$GITHUBSUBDIR
		git checkout -q
	fi
else
	if [[ -n $3 && -n "$(git ls-remote $1 | grep "$tag")" ]]; then
		display_alert "... creating a shallow clone" "$2 $3" "info"
		# Toradex git's doesn't support shallow clone. Need different solution than this.
		git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3 --depth 1 || git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3
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
if [ $? -ne 0 ]; then
	exit_with_error "Github download failed" "$1"
fi
}


display_alert()
#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
{
	# log function parameters to install.log
	echo "Displaying message: $@" >> $DEST/debug/output.log

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

#---------------------------------------------------------------------------------------------------------------------------------
# grab_version <path> <var_name>
#
# <PATH>: Extract kernel or uboot version from Makefile
# <var_name>: write version to this variable
#---------------------------------------------------------------------------------------------------------------------------------
grab_version ()
{
	local var=("VERSION" "PATCHLEVEL" "SUBLEVEL" "EXTRAVERSION")
	local ver=""
	for dir in "${var[@]}"; do
		tmp=$(cat $1/Makefile | grep $dir | head -1 | awk '{print $(NF)}' | cut -d '=' -f 2)"#"
		[[ $tmp != "#" ]] && ver=$ver$tmp
	done
	ver=${ver//#/.}; ver=${ver%.}; ver=${ver//.-/-}
	eval $"$2"="$ver"
}

fingerprint_image()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
	display_alert "Fingerprinting" "$VERSION" "info"
	cat <<-EOF > $1
	--------------------------------------------------------------------------------
	Title:			$VERSION
	Kernel:			Linux $VER
	Build date:		$(date +'%d.%m.%Y')
	Author:			Igor Pecovnik, www.igorpecovnik.com
	Sources: 		http://github.com/igorpecovnik/lib
	Support: 		http://www.armbian.com, http://forum.armbian.com/
	Changelog: 		http://www.armbian.com/logbook/
	--------------------------------------------------------------------------------
	$(cat $SRC/lib/LICENSE)
	--------------------------------------------------------------------------------
	EOF
}

addtorepo()
{
# add all deb files to repository
# parameter "remove" dumps all and creates new
# function: cycle trough distributions
	local distributions=("wheezy" "jessie" "trusty" "xenial")

	for release in "${distributions[@]}"; do
		# let's drop from publish if exits
		if [[ -n $(aptly publish list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $release) ]]; then
			aptly publish drop -config=config/aptly.conf $release > /dev/null 2>&1
		fi
		#aptly db cleanup -config=config/aptly.conf

		if [[ $1 == remove ]]; then
		# remove repository
			aptly repo drop -config=config/aptly.conf $release > /dev/null 2>&1
			aptly db cleanup -config=config/aptly.conf > /dev/null 2>&1
		fi

		# create repository if not exist
		if [[ -z $(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $release) ]]; then
			display_alert "Creating section" "$release" "info"
			aptly repo create -config=config/aptly.conf -distribution=$release -component=main -comment="Armbian stable" $release > /dev/null 2>&1
		fi

		# add all packages
		aptly repo add -force-replace=true -config=config/aptly.conf $release $POT/*.deb

		# add all distribution packages
		if [[ -d $POT/$release ]]; then
			aptly repo add -force-replace=true -config=config/aptly.conf $release $POT/*.deb
		fi

		aptly publish -passphrase=$GPG_PASS -origin=Armbian -label=Armbian -force-overwrite=true -config=config/aptly.conf -component=main --distribution=$release repo $release > /dev/null 2>&1

		#aptly repo show -config=config/aptly.conf $release
	done
}

# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host() {

	display_alert "Preparing" "host" "info"

	if [[ $(dpkg --print-architecture) == arm* ]]; then
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "http://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on board itself is not supported"
	fi

	if [[ $(dpkg --print-architecture) == i386 ]]; then
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "http://www.armbian.com/using-armbian-tools/"
		display_alert "Running this tool on non-x64 build host in not supported officially" "" "wrn"
	fi

	# dialog may be used to display progress
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' dialog 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "dialog"
		apt-get install -qq -y --no-install-recommends dialog >/dev/null 2>&1
	fi

	# wget is needed
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' wget 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "wget"
		apt-get install -qq -y --no-install-recommends wget >/dev/null 2>&1
	fi

	# need lsb_release to decide what to install
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' lsb-release 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "lsb-release"
		apt-get install -qq -y --no-install-recommends lsb-release >/dev/null 2>&1
	fi

	# packages list for host
	local hostdeps="ca-certificates device-tree-compiler pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate pigz \
	gawk gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev ntpdate \
	parted pkg-config libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev \
	nfs-kernel-server btrfs-tools gcc-aarch64-linux-gnu ncurses-term p7zip-full dos2unix dosfstools libc6-dev-armhf-cross libc6-dev-armel-cross\
	libc6-dev-arm64-cross curl pdftk"

	local codename=$(lsb_release -sc)
	display_alert "Build host OS release" "${codename:-(unknown)}" "info"
	if [[ -z $codename || "trusty wily xenial" != *"$codename"* ]]; then
		display_alert "Host system support was not tested" "${codename:-(unknown)}" "wrn"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi

	if [[ $codename == trusty && ! -f /etc/apt/sources.list.d/aptly.list ]]; then
		display_alert "Adding repository for trusty" "aptly" "info"
		echo 'deb http://repo.aptly.info/ squeeze main' > /etc/apt/sources.list.d/aptly.list
		apt-key adv --keyserver keys.gnupg.net --recv-keys 9E3E53F19C7DE460
	fi

	if [[ $codename == xenial ]]; then
		hostdeps="$hostdeps systemd-container udev"
		if systemd-detect-virt -q -c; then
			display_alert "Running in container" "$(systemd-detect-virt)" "info"
			# disable apt-cacher unless NO_APT_CACHER=no is not specified explicitly
			if [[ $NO_APT_CACHER != no ]]; then
				display_alert "apt-cacher is disabled, set NO_APT_CACHER=no to override" "" "wrn"
				NO_APT_CACHER=yes
			fi
			# create device nodes for loop devices
			for i in {0..6}; do
				mknod -m0660 /dev/loop$i b 7 $i > /dev/null 2>&1
			done
		fi
	fi

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then hostdeps="$hostdeps apt-cacher-ng"; fi

	# Deboostrap in trusty breaks due too old debootstrap. We are installing Xenial package
	local debootstrap_version=$(dpkg-query -W -f='${Version}\n' debootstrap | cut -f1 -d'+')
	local debootstrap_minimal="1.0.78"

	if [[ "$debootstrap_version" < "$debootstrap_minimal" ]]; then 
		display_alert "Upgrading" "debootstrap" "info"
		dpkg -i $SRC/lib/bin/debootstrap_1.0.78+nmu1ubuntu1.1_all.deb
	fi

	local deps=()
	local installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)

	for packet in $hostdeps; do
		if ! grep -q -x -e "$packet" <<< "$installed"; then deps+=("$packet"); fi
	done

	if [[ ${#deps[@]} -gt 0 ]]; then
		eval '( apt-get update; apt-get -y --no-install-recommends install "${deps[@]}" )' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/output.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing ${#deps[@]} host dependencies..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi

	# install aptly separately
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' aptly 2>/dev/null) != *ii* ]]; then
		apt-get install -qq -y --no-install-recommends aptly >/dev/null 2>&1
	fi

	# TODO: Check for failed installation process
	# test exit code propagation for commands in parentheses

	# enable arm binary format so that the cross-architecture chroot environment will work
	test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64

	# create directory structure
	mkdir -p $SOURCES $DEST/debs/extra $DEST/debug $CACHEDIR/rootfs $SRC/userpatches/overlay $SRC/toolchains $SRC/userpatches/patch
	find $SRC/lib/patch -type d ! -name . | sed "s%lib/patch%userpatches%" | xargs mkdir -p

	# download external Linaro compiler and missing special dependencies since they are needed for certain sources
	cd $SRC/toolchains
	[[ ! -d $SRC/toolchains/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu ]] && display_alert "Updating external compiler" "aarch64-linux-gnu 4.9" "info" \
		&& curl -LS --progress-bar "http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/aarch64-linux-gnu/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu.tar.xz" | tar xJf -
	#[[ ! -d $SRC/toolchains/gcc-linaro-4.9-2016.02-x86_64_arm-eabi ]] && display_alert "Updating external compiler" "arm-eabi 4.9" "info" \
	#	&& curl -LS --progress-bar "http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-eabi/gcc-linaro-4.9-2016.02-x86_64_arm-eabi.tar.xz" | tar xJf -
	[[ ! -d $SRC/toolchains/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabi ]] && display_alert "Updating external compilers" "arm-linux-gnueabi 4.9" "info" \
		&& curl -LS --progress-bar "http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabi/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabi.tar.xz" | tar xJf -
	[[ ! -d $SRC/toolchains/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf ]] && display_alert "Updating external compilers" "arm-linux-gnueabihf 4.9" "info" \
		&& curl -LS --progress-bar "http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabihf/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz" | tar xJf -
	[[ ! -d $SRC/toolchains/gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux ]] && display_alert "Updating external compilers" "arm-linux-gnueabihf 4.8" "info" \
		&& curl -LS --progress-bar "http://releases.linaro.org/14.04/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz" | tar xJf -
	[[ ! -d $SRC/toolchains/gcc-linaro-5.3-2016.02-x86_64_arm-linux-gnueabihf ]] && display_alert "Updating external compilers" "arm-linux-gnueabihf 5.3" "info" \
		&& curl -LS --progress-bar "https://releases.linaro.org/components/toolchain/binaries/5.3-2016.02/arm-linux-gnueabihf/gcc-linaro-5.3-2016.02-x86_64_arm-linux-gnueabihf.tar.xz" | tar xJf -

	dpkg --add-architecture i386
	apt-get install -qq -y --no-install-recommends lib32stdc++6 libc6-i386 lib32ncurses5 lib32tinfo5 zlib1g:i386 >/dev/null 2>&1

	[[ ! -f $SRC/userpatches/customize-image.sh ]] && cp $SRC/lib/scripts/customize-image.sh.template $SRC/userpatches/customize-image.sh

	if [[ ! -f $SRC/userpatches/README ]]; then
		rm $SRC/userpatches/readme.txt
		echo 'Please read documentation about customizing build configuration' > $SRC/userpatches/README
		echo 'http://www.armbian.com/using-armbian-tools/' >> $SRC/userpatches/README
	fi

	# check free space (basic), doesn't work on Trusty
	local freespace=$(findmnt --target $SRC -n -o AVAIL -b 2>/dev/null) # in bytes
	[[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]] && display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
}
