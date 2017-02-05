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
# create_sources_list
# fetch_from_repo
# display_alert
# grab_version
# fingerprint_image
# addtorepo
# prepare_host
# download_toolchain

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
		debs) # delete output/debs for current branch and family
		if [[ -d $DEST/debs ]]; then
			display_alert "Cleaning output/debs for" "$BOARD $BRANCH" "info"
			# easier than dealing with variable expansion and escaping dashes in file names
			find $DEST/debs -name "${CHOSEN_UBOOT}_*.deb" -delete
			find $DEST/debs \( -name "${CHOSEN_KERNEL}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/dtb}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/headers}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/firmware-image}_*.deb" \) -delete
			[[ -n $RELEASE ]] && rm -f $DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_*.deb
		fi
		;;

		extras) # delete output/debs/extra/$RELEASE for all architectures
		if [[ -n $RELEASE && -d $DEST/debs/extra/$RELEASE ]]; then
			display_alert "Cleaning output/debs/extra for" "$RELEASE" "info"
			rm -rf $DEST/debs/extra/$RELEASE
		fi
		;;

		alldebs) # delete output/debs
		[[ -d $DEST/debs ]] && display_alert "Cleaning" "output/debs" "info" && rm -rf $DEST/debs/*
		;;

		cache) # delete output/cache
		[[ -d $CACHEDIR ]] && display_alert "Cleaning" "output/cache/rootfs (all)" "info" && find $CACHEDIR/rootfs/ -type f -delete
		;;

		images) # delete output/images
		[[ -d $DEST/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf $DEST/images/*
		;;

		sources) # delete output/sources and output/buildpkg
		[[ -d $SOURCES ]] && display_alert "Cleaning" "sources" "info" && rm -rf $SOURCES/* $DEST/buildpkg/*
		;;

		oldcache)
		if [[ -d $CACHEDIR/rootfs/ && $(ls -1 $CACHEDIR/rootfs/ | wc -l) -gt 6 ]]; then
			display_alert "Cleaning" "output/cache/rootfs (old)" "info"
			(cd $CACHEDIR/rootfs/; ls -t | sed -e "1,6d" | xargs -d '\n' rm -f)
		fi
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
	# TODO: execute run_after_build here?
	overlayfs_wrapper "cleanup"
	# unlock loop device access in case of starvation
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -u $FD

	exit -1
}

# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version

get_package_list_hash()
{
	( printf '%s\n' $PACKAGE_LIST | sort -u; printf '%s\n' $PACKAGE_LIST_EXCLUDE | sort -u; echo "$ROOTFSCACHE_VERSION" ) \
		| md5sum | cut -d' ' -f 1
}

# create_sources_list <release> <basedir>
#
# <release>: jessie|stretch|xenial
# <basedir>: path to root directory
#
create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
	jessie|stretch)
	cat <<-EOF > $basedir/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

	deb http://security.debian.org/ ${release}/updates main contrib non-free
	#deb-src http://security.debian.org/ ${release}/updates main contrib non-free
	EOF
	;;

	xenial)
	cat <<-EOF > $basedir/etc/apt/sources.list
	deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	EOF
	;;
	esac
}

# fetch_from_repo <url> <directory> <ref> <ref_subdir>
# <url>: remote repository URL
# <directory>: local directory; subdir for branch/tag will be created
# <ref>:
#	branch:name
#	tag:name
#	head(*)
#	commit:hash@depth(**)
#
# *: Implies ref_subdir=no
# **: Not implemented yet
# <ref_subdir>: "yes" to create subdirectory for tag or branch name
#
fetch_from_repo()
{
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4

	[[ -z $ref || ( $ref != tag:* && $ref != branch:* && $ref != head ) ]] && exit_with_error "Error in configuration"
	local ref_type=${ref%%:*}
	if [[ $ref_type == head ]]; then
		local ref_name=HEAD
	else
		local ref_name=${ref##*:}
	fi

	display_alert "Checking git sources" "$dir $ref_name" "info"

	# get default remote branch name without cloning
	# local ref_name=$(git ls-remote --symref $url HEAD | grep -o 'refs/heads/\S*' | sed 's%refs/heads/%%')
	# for git:// protocol comparing hashes of "git ls-remote -h $url" and "git ls-remote --symref $url HEAD" is needed

	if [[ $ref_subdir == yes ]]; then
		local workdir=$dir/$ref_name
	else
		local workdir=$dir
	fi
	mkdir -p $SOURCES/$workdir
	cd $SOURCES/$workdir

	# check if existing remote URL for the repo or branch does not match current one
	# may not be supported by older git versions
	local current_url=$(git remote get-url origin 2>/dev/null)
	if [[ -n $current_url && $(git rev-parse --is-inside-work-tree 2>/dev/null) == true && \
				$(git rev-parse --show-toplevel) == $(pwd) && \
				$current_url != $url ]]; then
		display_alert "Remote URL does not match, removing existing local copy"
		rm -rf .git *
	fi

	if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) != true || \
				$(git rev-parse --show-toplevel) != $(pwd) ]]; then
		display_alert "Creating local copy"
		git init -q .
		git remote add origin $url
	fi

	local changed=false

	local local_hash=$(git rev-parse @ 2>/dev/null)
	case $ref_type in
		branch)
		# TODO: grep refs/heads/$name
		local remote_hash=$(git ls-remote -h $url "$ref_name" | head -1 | cut -f1)
		[[ -z $local_hash || $local_hash != $remote_hash ]] && changed=true
		;;

		tag)
		local remote_hash=$(git ls-remote -t $url "$ref_name" | cut -f1)
		if [[ -z $local_hash || $local_hash != $remote_hash ]]; then
			remote_hash=$(git ls-remote -t $url "$ref_name^{}" | cut -f1)
			[[ -z $remote_hash || $local_hash != $remote_hash ]] && changed=true
		fi
		;;

		head)
		local remote_hash=$(git ls-remote $url HEAD | cut -f1)
		[[ -z $local_hash || $local_hash != $remote_hash ]] && changed=true
		;;
	esac

	if [[ $changed == true ]]; then
		# remote was updated, fetch and check out updates
		display_alert "Fetching updates"
		case $ref_type in
			branch) git fetch --depth 1 origin $ref_name ;;
			tag) git fetch --depth 1 origin tags/$ref_name ;;
			head) git fetch --depth 1 origin HEAD ;;
		esac
		display_alert "Checking out"
		git checkout -f -q FETCH_HEAD
	elif [[ -n $(git status -uno --porcelain --ignore-submodules=all) ]]; then
		# working directory is not clean
		if [[ $FORCE_CHECKOUT == yes ]]; then
			display_alert "Checking out"
			git checkout -f -q HEAD
		else
			display_alert "Skipping checkout"
		fi
	else
		# working directory is clean, nothing to do
		display_alert "Up to date"
	fi
	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"
		# FML: http://stackoverflow.com/a/17692710
		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd $SOURCES/$workdir
			local surl=$(git config -f .gitmodules --get "submodule.$i.url")
			local sref=$(git config -f .gitmodules --get "submodule.$i.branch")
			if [[ -n $sref ]]; then
				sref="branch:$sref"
			else
				sref="head"
			fi
			fetch_from_repo "$surl" "$workdir/$i" "$sref"
		done
	fi
} #############################################################################

display_alert()
#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
{
	# log function parameters to install.log
	[[ -n $DEST ]] && echo "Displaying message: $@" >> $DEST/debug/output.log

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
# grab_version <path>
#
# <path>: Extract kernel or uboot version from $path/Makefile
#---------------------------------------------------------------------------------------------------------------------------------
grab_version()
{
	local ver=""
	for component in VERSION PATCHLEVEL SUBLEVEL EXTRAVERSION; do
		tmp=$(cat $1/Makefile | grep $component | head -1 | awk '{print $(NF)}' | cut -d '=' -f 2)"#"
		[[ $tmp != "#" ]] && ver="$ver$tmp"
	done
	ver=${ver//#/.}; ver=${ver%.}; ver=${ver//.-/-}
	echo $ver
}

fingerprint_image()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
	display_alert "Fingerprinting"
	cat <<-EOF > $1
	--------------------------------------------------------------------------------
	Title:			Armbian $REVISION ${BOARD^} $DISTRIBUTION $RELEASE $BRANCH
	Kernel:			Linux $VER
	Build date:		$(date +'%d.%m.%Y')
	Authors:		http://www.armbian.com/authors
	Sources: 		http://github.com/igorpecovnik/lib
	Support: 		http://forum.armbian.com/
	Changelog: 		http://www.armbian.com/logbook/
	Documantation:		http://docs.armbian.com/
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
	local distributions=("jessie" "xenial")

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

		if [[ $1 == replace ]]; then
			local replace=true
		else
			local replace=false
		fi

		# create local repository if not exist
		if [[ -z $(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $release) ]]; then
			display_alert "Creating section" "$release" "info"
			aptly repo create -config=config/aptly.conf -distribution=$release -component=main -comment="Armbian main repository" $release
		fi
		if [[ -z $(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep "^utils") ]]; then
			aptly repo create -config=config/aptly.conf -distribution=$release -component="utils" -comment="Armbian utilities" utils
		fi
		if [[ -z $(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			aptly repo create -config=config/aptly.conf -distribution=$release -component="${release}-desktop" -comment="Armbian desktop" ${release}-desktop
		fi
		# create local repository if not exist

		# adding main
		if find $POT -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "main" "ext"
			aptly repo add -force-replace=$replace -config=config/aptly.conf $release $POT/*.deb
		else
			display_alert "Not adding $release" "main" "wrn"
		fi

		# adding main distribution packages
		if find ${POT}${release} -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "main" "ext"
			aptly repo add -force-replace=$replace -config=config/aptly.conf $release ${POT}${release}/*.deb
		else
			display_alert "Not adding $release" "main" "wrn"
		fi

		# adding utils
		if find ${POT}extra/utils -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "utils" "ext"
			aptly repo add -config=config/aptly.conf "utils" ${POT}extra/utils/*.deb
		else
			display_alert "Not adding $release" "utils" "wrn"
		fi

		# adding desktop
		if find ${POT}extra/${release}-desktop -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "desktop" "ext"
			aptly repo add -force-replace=$replace -config=config/aptly.conf "${release}-desktop" ${POT}extra/${release}-desktop/*.deb
		else
			display_alert "Not adding $release" "desktop" "wrn"
		fi

		# publish
		aptly publish -passphrase=$GPG_PASS -origin=Armbian -label=Armbian -config=config/aptly.conf -component=main,utils,${release}-desktop \
			--distribution=$release repo $release utils ${release}-desktop

		if [[ $? -ne 0 ]]; then
			display_alert "Publishing failed" "$release" "err"
			exit 0
		fi
	done
	display_alert "List of local repos" "local" "info"
	(aptly repo list -config=config/aptly.conf) | egrep packages
	# serve
	# aptly -config=config/aptly.conf -listen=":8189" serve
}

# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host()
{
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

	# need lsb_release to decide what to install
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' lsb-release 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "lsb-release"
		apt-get install -qq -y --no-install-recommends lsb-release >/dev/null 2>&1
	fi

	# packages list for host
	local hostdeps="wget ca-certificates device-tree-compiler pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate \
	gawk gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev ntpdate \
	parted pkg-config libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev \
	nfs-kernel-server btrfs-tools gcc-aarch64-linux-gnu ncurses-term p7zip-full dos2unix dosfstools libc6-dev-armhf-cross libc6-dev-armel-cross \
	libc6-dev-arm64-cross curl gcc-arm-none-eabi libnewlib-arm-none-eabi patchutils python liblz4-tool"

	local codename=$(lsb_release -sc)
	display_alert "Build host OS release" "${codename:-(unknown)}" "info"
	if [[ -z $codename || "trusty xenial" != *"$codename"* ]]; then
		display_alert "Host system support was not tested" "${codename:-(unknown)}" "wrn"
		display_alert "Please don't ask for support if anything doesn't work"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi

	if [[ $codename == xenial ]]; then
		hostdeps="$hostdeps systemd-container udev distcc libstdc++-arm-none-eabi-newlib gcc-4.9-arm-linux-gnueabihf \
			gcc-4.9-aarch64-linux-gnu g++-4.9-arm-linux-gnueabihf g++-4.9-aarch64-linux-gnu g++-5-aarch64-linux-gnu \
			g++-5-arm-linux-gnueabihf lib32stdc++6 libc6-i386 lib32ncurses5 lib32tinfo5 aptly"
		grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386
		if systemd-detect-virt -q -c; then
			display_alert "Running in container" "$(systemd-detect-virt)" "info"
			# disable apt-cacher unless NO_APT_CACHER=no is not specified explicitly
			if [[ $NO_APT_CACHER != no ]]; then
				display_alert "apt-cacher is disabled, set NO_APT_CACHER=no to override" "" "wrn"
				NO_APT_CACHER=yes
			fi
			CONTAINER_COMPAT=yes
		fi
	fi

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then hostdeps="$hostdeps apt-cacher-ng"; fi

	local deps=()
	local installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)

	for packet in $hostdeps; do
		if ! grep -q -x -e "$packet" <<< "$installed"; then deps+=("$packet"); fi
	done

	if [[ ${#deps[@]} -gt 0 ]]; then
		eval '( apt-get -q update; apt-get -q -y --no-install-recommends install "${deps[@]}" )' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/output.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing ${#deps[@]} host dependencies..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		# this is needed in case new compilers were installed
		update-ccache-symlinks
	fi

	if [[ $codename == xenial && $(dpkg-query -W -f='${db:Status-Abbrev}\n' 'zlib1g:i386' 2>/dev/null) != *ii* ]]; then
		apt-get install -qq -y --no-install-recommends zlib1g:i386 >/dev/null 2>&1
	fi

	# enable arm binary format so that the cross-architecture chroot environment will work
	if [[ $KERNEL_ONLY != yes && ! -d /proc/sys/fs/binfmt_misc ]]; then
		modprobe -q binfmt_misc || exit_with_error "Kernel does not support binfmt_misc"
	fi
	test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64

	# create directory structure
	mkdir -p $SOURCES $DEST/debs/extra $DEST/debug $CACHEDIR/rootfs $SRC/userpatches/overlay $SRC/toolchains $SRC/userpatches/patch
	find $SRC/lib/patch -type d ! -name . | sed "s%lib/patch%userpatches%" | xargs mkdir -p

	# download external Linaro compiler and missing special dependencies since they are needed for certain sources
	if [[ $codename == xenial ]]; then
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/aarch64-linux-gnu/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu.tar.xz"
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabi/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabi.tar.xz"
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabihf/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz"
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/5.2-2015.11-2/arm-linux-gnueabihf/gcc-linaro-5.2-2015.11-2-x86_64_arm-linux-gnueabihf.tar.xz"
		download_toolchain "https://releases.linaro.org/archive/14.04/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/6.2-2016.11/arm-linux-gnueabihf/gcc-linaro-6.2.1-2016.11-x86_64_arm-linux-gnueabihf.tar.xz"
		download_toolchain "https://releases.linaro.org/components/toolchain/binaries/6.2-2016.11/aarch64-linux-gnu/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu.tar.xz"
	fi

	[[ ! -f $SRC/userpatches/customize-image.sh ]] && cp $SRC/lib/scripts/customize-image.sh.template $SRC/userpatches/customize-image.sh

	if [[ ! -f $SRC/userpatches/README ]]; then
		rm $SRC/userpatches/readme.txt
		echo 'Please read documentation about customizing build configuration' > $SRC/userpatches/README
		echo 'http://www.armbian.com/using-armbian-tools/' >> $SRC/userpatches/README
	fi

	# check free space (basic), doesn't work on Trusty
	local freespace=$(findmnt --target $SRC -n -o AVAIL -b 2>/dev/null) # in bytes
	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}

# download_toolchain <url>
#
download_toolchain()
{
	local url=$1
	local filename=${url##*/}
	local dirname=${filename//.tar.xz}

	if [[ -f $SRC/toolchains/$dirname/.download-complete ]]; then
		return
	fi

	cd $SRC/toolchains/

	display_alert "Downloading toolchain" "$dirname" "info"
	curl -Lf --progress-bar $url -o $filename
	curl -Lf --progress-bar ${url}.asc -o ${filename}.asc

	local verified=false

	display_alert "Verifying"
	if grep -q 'BEGIN PGP SIGNATURE' ${filename}.asc; then
		if [[ ! -d $DEST/.gpg ]]; then
			mkdir -p $DEST/.gpg
			chmod 700 $DEST/.gpg
			touch $DEST/.gpg/gpg.conf
			chmod 600 $DEST/.gpg/gpg.conf
		fi
		(gpg --homedir $DEST/.gpg --no-permission-warning --list-keys 8F427EAF || gpg --homedir $DEST/.gpg --no-permission-warning --keyserver keyserver.ubuntu.com --recv-keys 8F427EAF) 2>&1 | tee -a $DEST/debug/output.log
		gpg --homedir $DEST/.gpg --no-permission-warning --verify --trust-model always -q ${filename}.asc 2>&1 | tee -a $DEST/debug/output.log
		[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true
	else
		md5sum -c --status ${filename}.asc && verified=true
	fi
	if [[ $verified == true ]]; then
		display_alert "Extracting"
		tar --overwrite -xf $filename && touch $SRC/toolchains/$dirname/.download-complete
		display_alert "Download complete" "" "info"
	else
		display_alert "Verification failed" "" "wrn"
	fi
}
