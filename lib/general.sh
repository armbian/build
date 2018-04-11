# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# cleaning
# exit_with_error
# get_package_list_hash
# create_sources_list
# fetch_from_repo
# display_alert
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
				-name "armbian-*.deb" -o \
				-name "${CHOSEN_KERNEL/image/dtb}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/headers}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/source}_*.deb" -o \
				-name "${CHOSEN_KERNEL/image/firmware-image}_*.deb" \) -delete
			[[ -n $RELEASE ]] && rm -f $DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_*.deb
			[[ -n $RELEASE ]] && rm -f $DEST/debs/$RELEASE/armbian-desktop-${RELEASE}_*.deb
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
		[[ -d $SRC/cache/rootfs ]] && display_alert "Cleaning" "rootfs cache (all)" "info" && find $SRC/cache/rootfs -type f -delete
		;;

		images) # delete output/images
		[[ -d $DEST/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf $DEST/images/*
		;;

		sources) # delete output/sources and output/buildpkg
		[[ -d $SRC/cache/sources ]] && display_alert "Cleaning" "sources" "info" && rm -rf $SRC/cache/sources/* $DEST/buildpkg/*
		;;

		oldcache)
		if [[ -d $SRC/cache/rootfs && $(ls -1 $SRC/cache/rootfs | wc -l) -gt 6 ]]; then
			display_alert "Cleaning" "rootfs cache (old)" "info"
			(cd $SRC/cache/rootfs; ls -t | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
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

	xenial|bionic)
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
	mkdir -p $SRC/cache/sources/$workdir
	cd $SRC/cache/sources/$workdir

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
			cd $SRC/cache/sources/$workdir
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
	Authors:		https://www.armbian.com/authors
	Sources: 		https://github.com/armbian/
	Support: 		https://forum.armbian.com/
	Changelog: 		https://www.armbian.com/logbook/
	Documantation:		https://docs.armbian.com/
	--------------------------------------------------------------------------------
	$(cat $SRC/LICENSE)
	--------------------------------------------------------------------------------
	EOF
}

addtorepo()
{
# add all deb files to repository
# parameter "remove" dumps all and creates new
# parameter "delete" remove incoming directory if publishing is succesful
# function: cycle trough distributions

	local distributions=("jessie" "xenial" "stretch" "bionic")
	local errors=0

	for release in "${distributions[@]}"; do

		local forceoverwrite=""

		# let's drop from publish if exits
		if [[ -n $(aptly publish list -config=../config/aptly.conf -raw | awk '{print $(NF)}' | grep $release) ]]; then
			aptly publish drop -config=../config/aptly.conf $release > /dev/null 2>&1
		fi

		# create local repository if not exist
		if [[ -z $(aptly repo list -config=../config/aptly.conf -raw | awk '{print $(NF)}' | grep $release) ]]; then
			display_alert "Creating section" "$release" "info"
			aptly repo create -config=../config/aptly.conf -distribution=$release -component="main" \
			-comment="Armbian main repository" ${release}
		fi
		if [[ -z $(aptly repo list -config=../config/aptly.conf -raw | awk '{print $(NF)}' | grep "^utils") ]]; then
			aptly repo create -config=../config/aptly.conf -distribution=$release -component="utils" \
			-comment="Armbian utilities (backwards compatibility)" utils
		fi
		if [[ -z $(aptly repo list -config=../config/aptly.conf -raw | awk '{print $(NF)}' | grep "${release}-utils") ]]; then
			aptly repo create -config=../config/aptly.conf -distribution=$release -component="${release}-utils" \
			-comment="Armbian ${release} utilities" ${release}-utils
		fi
		if [[ -z $(aptly repo list -config=../config/aptly.conf -raw | awk '{print $(NF)}' | grep "${release}-desktop") ]]; then
			aptly repo create -config=../config/aptly.conf -distribution=$release -component="${release}-desktop" \
			-comment="Armbian ${release} desktop" ${release}-desktop
		fi


		# adding main
		if find $POT -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "main" "ext"
			aptly repo add -config=../config/aptly.conf $release ${POT}*.deb
			if [[ $? -ne 0 ]]; then
				# try again with
				display_alert "Adding by force to repository $release" "main" "ext"
				aptly repo add -force-replace=true -config=../config/aptly.conf $release ${POT}*.deb
				if [[ $? -eq 0 ]]; then forceoverwrite="-force-overwrite"; else errors=$((errors+1)); fi
			fi
		else
			display_alert "Not adding $release" "main" "wrn"
		fi

		local COMPONENTS="main"

		# adding main distribution packages
		if find ${POT}${release} -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "root" "ext"
			aptly repo add -config=../config/aptly.conf $release ${POT}${release}/*.deb
			if [[ $? -ne 0 ]]; then
				# try again with
				display_alert "Adding by force to repository $release" "root" "ext"
				aptly repo add -force-replace=true -config=../config/aptly.conf $release ${POT}${release}/*.deb
				if [[ $? -eq 0 ]]; then forceoverwrite="-force-overwrite"; else errors=$((errors+1));fi
			fi
		else
			display_alert "Not adding $release" "root" "wrn"
		fi

		# adding old utils and new jessie-utils for backwards compatibility with older images
		if find ${POT}extra/jessie-utils -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "utils" "ext"
			aptly repo add -config=../config/aptly.conf "utils" ${POT}extra/jessie-utils/*.deb
			if [[ $? -ne 0 ]]; then
				# try again with
				display_alert "Adding by force to repository $release" "utils" "ext"
				aptly repo add -force-replace=true -config=../config/aptly.conf "utils" ${POT}extra/jessie-utils/*.deb
				if [[ $? -eq 0 ]]; then forceoverwrite="-force-overwrite"; else errors=$((errors+1));fi
			fi
		else
			display_alert "Not adding $release" "utils" "wrn"
		fi
		COMPONENTS="${COMPONENTS} utils"

		# adding release-specific utils
		if find ${POT}extra/${release}-utils -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "${release}-utils" "ext"
			aptly repo add -config=../config/aptly.conf "${release}-utils" ${POT}extra/${release}-utils/*.deb
			if [[ $? -ne 0 ]]; then
				# try again with
				display_alert "Adding by force to repository $release" "${release}-utils" "ext"
				aptly repo add -force-replace=true -config=../config/aptly.conf "${release}-utils" ${POT}extra/${release}-utils/*.deb
				if [[ $? -eq 0 ]]; then forceoverwrite="-force-overwrite"; else errors=$((errors+1));fi
			fi
		else
			display_alert "Not adding $release" "${release}-utils" "wrn"
		fi
		COMPONENTS="${COMPONENTS} ${release}-utils"

		# adding desktop
		if find ${POT}extra/${release}-desktop -maxdepth 1 -type f -name "*.deb" 2>/dev/null | grep -q .; then
			display_alert "Adding to repository $release" "desktop" "ext"
			aptly repo add -config=../config/aptly.conf "${release}-desktop" ${POT}extra/${release}-desktop/*.deb
			if [[ $? -ne 0 ]]; then
				# try again with
				display_alert "Adding by force to repository $release" "desktop" "ext"
				aptly repo add -force-replace=true -config=../config/aptly.conf "${release}-desktop" ${POT}extra/${release}-desktop/*.deb
				if [[ $? -eq 0 ]]; then forceoverwrite="-force-overwrite"; else errors=$((errors+1));fi
			fi
		else
			display_alert "Not adding $release" "desktop" "wrn"
		fi
		COMPONENTS="${COMPONENTS} ${release}-desktop"

		local mainnum=$(aptly repo show -with-packages -config=../config/aptly.conf $release | grep "Number of packages" | awk '{print $NF}')
		local utilnum=$(aptly repo show -with-packages -config=../config/aptly.conf ${release}-desktop | grep "Number of packages" | awk '{print $NF}')
		local desknum=$(aptly repo show -with-packages -config=../config/aptly.conf ${release}-utils | grep "Number of packages" | awk '{print $NF}')

		if [ $mainnum -gt 0 ] && [ $utilnum -gt 0 ] && [ $desknum -gt 0 ]; then
			# publish
			aptly publish $forceoverwrite -passphrase=$GPG_PASS -origin=Armbian -label=Armbian -config=../config/aptly.conf -component=${COMPONENTS// /,} \
				--distribution=$release repo $release ${COMPONENTS//main/}
			if [[ $? -ne 0 ]]; then
				display_alert "Publishing failed" "$release" "err"
				errors=$((errors+1))
				exit 0
			fi
		else
			errors=$((errors+1))
			local err_txt=": All components must be present: main, utils and desktop for first build"
		fi

	done

	# display what we have
	display_alert "List of local repos" "local" "info"
	(aptly repo list -config=../config/aptly.conf) | egrep packages

	# remove debs if no errors found
	if [[ $errors -eq 0 ]]; then
		if [[ "$2" == "delete" ]]; then
			display_alert "Purging incoming debs" "all" "ext"
			find ${POT} -name "*.deb" -type f -delete
		fi
	else
		display_alert "There were some problems $err_txt" "leaving incoming directory intact" "err"
	fi

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

	if [[ $(dpkg --print-architecture) != amd64 ]]; then
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "http://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on non x86-x64 build host in not supported"
	fi

	# exit if package manager is running in the back
	fuser -s /var/lib/dpkg/lock
	if [[ $? = 0 ]]; then
		exit_with_error "Package manager is running in the background. Please try later."
	fi

	# need lsb_release to decide what to install
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' lsb-release 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "lsb-release"
		apt -q update && apt install -q -y --no-install-recommends lsb-release
	fi

	# packages list for host
	# NOTE: please sync any changes here with the Dockerfile and Vagrantfile
	local hostdeps="wget ca-certificates device-tree-compiler pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate \
	gawk gcc-arm-linux-gnueabihf qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev fakeroot \
	parted pkg-config libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev \
	nfs-kernel-server btrfs-tools ncurses-term p7zip-full kmod dosfstools libc6-dev-armhf-cross \
	curl patchutils python liblz4-tool libpython2.7-dev linux-base swig libpython-dev aptly acl \
	locales ncurses-base pixz dialog systemd-container udev distcc lib32stdc++6 libc6-i386 lib32ncurses5 lib32tinfo5 \
	bison libbison-dev flex libfl-dev"

	local codename=$(lsb_release -sc)
	display_alert "Build host OS release" "${codename:-(unknown)}" "info"

	# Ubuntu Xenial x86_64 is the only supported host OS release
	# Using Docker/VirtualBox/Vagrant is the only supported way to run the build script on other Linux distributions
	# NO_HOST_RELEASE_CHECK overrides the check for a supported host system
	# Disable host OS check at your own risk, any issues reported with unsupported releases will be closed without a discussion
	if [[ -z $codename || "xenial" != *"$codename"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${codename:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "It seems you ignore documentation and run an unsupported build system: ${codename:-(unknown)}"
		fi
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		exit_with_error "Windows subsystem for Linux is not a supported build environment"
	fi

	grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386
	if systemd-detect-virt -q -c; then
		display_alert "Running in container" "$(systemd-detect-virt)" "info"
		# disable apt-cacher unless NO_APT_CACHER=no is not specified explicitly
		if [[ $NO_APT_CACHER != no ]]; then
			display_alert "apt-cacher is disabled in containers, set NO_APT_CACHER=no to override" "" "wrn"
			NO_APT_CACHER=yes
		fi
		CONTAINER_COMPAT=yes
		# trying to use nested containers is not a good idea, so don't permit EXTERNAL_NEW=compile
		if [[ $EXTERNAL_NEW == compile ]]; then
			display_alert "EXTERNAL_NEW=compile is not available when running in container, setting to prebuilt" "" "wrn"
			EXTERNAL_NEW=prebuilt
		fi
		SYNC_CLOCK=no
	fi

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then hostdeps="$hostdeps apt-cacher-ng"; fi

	local deps=()
	local installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)

	for packet in $hostdeps; do
		if ! grep -q -x -e "$packet" <<< "$installed"; then deps+=("$packet"); fi
	done

	# distribution packages are buggy, download from author
	if [[ ! -f /etc/apt/sources.list.d/aptly.list ]]; then
		display_alert "Updating from external repository" "aptly" "info"
		wget -qO - https://www.aptly.info/pubkey.txt | apt-key add - >/dev/null 2>&1
		echo "deb http://repo.aptly.info/ squeeze main" > /etc/apt/sources.list.d/aptly.list
	fi

	if [[ ${#deps[@]} -gt 0 ]]; then
		display_alert "Installing build dependencies"
		apt -q update
		apt -y upgrade
		apt -q -y --no-install-recommends install "${deps[@]}" | tee -a $DEST/debug/hostdeps.log
		update-ccache-symlinks
	fi

	# add bionic repository and install more recent qemu and debootstrap
	if [[ ! -f /etc/apt/sources.list.d/bionic.list && $codename == "xenial" ]]; then
		echo "deb http://us.archive.ubuntu.com/ubuntu/ bionic main restricted universe" > /etc/apt/sources.list.d/bionic.list
		echo "Package: *" > /etc/apt/preferences.d/bionic.pref
		echo "Pin: release n=bionic" >> /etc/apt/preferences.d/bionic.pref
		echo "Pin-Priority: -10" >> /etc/apt/preferences.d/bionic.pref
		apt -q update
		apt -y upgrade
		apt -t bionic -y --no-install-recommends install qemu-user-static debootstrap binfmt-support
	fi

	# sync clock
	if [[ $SYNC_CLOCK != no ]]; then
		display_alert "Syncing clock" "host" "info"
		ntpdate -s ${NTP_SERVER:- time.ijs.si}
	fi

	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' 'zlib1g:i386' 2>/dev/null) != *ii* ]]; then
		apt install -qq -y --no-install-recommends zlib1g:i386 >/dev/null 2>&1
	fi

	# enable arm binary format so that the cross-architecture chroot environment will work
	if [[ $KERNEL_ONLY != yes ]]; then
		modprobe -q binfmt_misc
		mountpoint -q /proc/sys/fs/binfmt_misc/ || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
		test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
	fi

	# create directory structure
	mkdir -p $SRC/{cache,output,userpatches}
	if [[ -n $SUDO_USER ]]; then
		chgrp --quiet sudo cache output userpatches
		# SGID bit on cache/sources breaks kernel dpkg packaging
		chmod --quiet g+w,g+s output userpatches
		# fix existing permissions
		find $SRC/output $SRC/userpatches -type d ! -group sudo -exec chgrp --quiet sudo {} \;
		find $SRC/output $SRC/userpatches -type d ! -perm -g+w,g+s -exec chmod --quiet g+w,g+s {} \;
	fi
	mkdir -p $DEST/debs/extra $DEST/{config,debug,patch} $SRC/userpatches/overlay $SRC/cache/{sources,toolchains,rootfs} $SRC/.tmp

	find $SRC/patch -type d ! -name . | sed "s%/patch%/userpatches%" | xargs mkdir -p

	# download external Linaro compiler and missing special dependencies since they are needed for certain sources
	local toolchains=(
		"https://dl.armbian.com/_toolchains/gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-4.9.4-2017.01-x86_64_aarch64-linux-gnu.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabi.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-5.5.0-2017.10-x86_64_aarch64-linux-gnu.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-5.5.0-2017.10-x86_64_arm-linux-gnueabi.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-5.5.0-2017.10-x86_64_arm-linux-gnueabihf.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-6.4.1-2017.11-x86_64_arm-linux-gnueabihf.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-6.4.1-2017.11-x86_64_aarch64-linux-gnu.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-7.2.1-2017.11-x86_64_aarch64-linux-gnu.tar.xz"
		"https://dl.armbian.com/_toolchains/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf.tar.xz"
		)

	for toolchain in ${toolchains[@]}; do
		download_toolchain "$toolchain"
	done

	rm -rf $SRC/cache/toolchains/*.tar.xz $SRC/cache/toolchains/*.tar.xz.asc
	local existing_dirs=( $(ls -1 $SRC/cache/toolchains) )
	for dir in ${existing_dirs[@]}; do
		local found=no
		for toolchain in ${toolchains[@]}; do
			local filename=${toolchain##*/}
			local dirname=${filename//.tar.xz}
			[[ $dir == $dirname ]] && found=yes
		done
		if [[ $found == no ]]; then
			display_alert "Removing obsolete toolchain" "$dir"
			rm -rf $SRC/cache/toolchains/$dir
		fi
	done

	[[ ! -f $SRC/userpatches/customize-image.sh ]] && cp $SRC/config/templates/customize-image.sh.template $SRC/userpatches/customize-image.sh

	if [[ ! -f $SRC/userpatches/README ]]; then
		rm -f $SRC/userpatches/readme.txt
		echo 'Please read documentation about customizing build configuration' > $SRC/userpatches/README
		echo 'http://www.armbian.com/using-armbian-tools/' >> $SRC/userpatches/README
	fi

	# check free space (basic)
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

	if [[ -f $SRC/cache/toolchains/$dirname/.download-complete ]]; then
		return
	fi

	cd $SRC/cache/toolchains/

	display_alert "Downloading" "$dirname"
	curl -Lf --progress-bar $url -o $filename
	curl -Lf --progress-bar ${url}.asc -o ${filename}.asc

	local verified=false

	display_alert "Verifying"
	if grep -q 'BEGIN PGP SIGNATURE' ${filename}.asc; then
		if [[ ! -d $SRC/cache/.gpg ]]; then
			mkdir -p $SRC/cache/.gpg
			chmod 700 $SRC/cache/.gpg
			touch $SRC/cache/.gpg/gpg.conf
			chmod 600 $SRC/cache/.gpg/gpg.conf
		fi
		(gpg --homedir $SRC/cache/.gpg --no-permission-warning --list-keys 8F427EAF || gpg --homedir $SRC/cache/.gpg --no-permission-warning --keyserver keyserver.ubuntu.com --recv-keys 8F427EAF) 2>&1 | tee -a $DEST/debug/output.log
		gpg --homedir $SRC/cache/.gpg --no-permission-warning --verify --trust-model always -q ${filename}.asc 2>&1 | tee -a $DEST/debug/output.log
		[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true
	else
		md5sum -c --status ${filename}.asc && verified=true
	fi
	if [[ $verified == true ]]; then
		display_alert "Extracting"
		tar --no-same-owner --overwrite -xf $filename && touch $SRC/cache/toolchains/$dirname/.download-complete
		display_alert "Download complete" "" "info"
	else
		display_alert "Verification failed" "" "wrn"
	fi
}

show_developer_warning()
{
	local temp_rc=$(mktemp)
	cat <<-'EOF' > $temp_rc
	screen_color = (WHITE,RED,ON)
	EOF
	local warn_text="You are switching to the \Z1EXPERT MODE\Zn

	This allows building experimental configurations that are provided
	\Z1AS IS\Zn to developers and expert users,
	\Z1WITHOUT ANY RESPONSIBILITIES\Zn from the Armbian team:

	- You are using these configurations \Z1AT YOUR OWN RISK\Zn
	- Bug reports related to the dev kernel, CSC, WIP and EOS boards
	\Z1will be closed without a discussion\Zn
	- Forum posts related to dev kernel, CSC, WIP and EOS boards
	should be created in the \Z2\"Community forums\"\Zn section
	"
	DIALOGRC=$temp_rc dialog --title "Expert mode warning" --backtitle "$backtitle" --colors --defaultno --no-label "I do not agree" \
		--yes-label "I understand and agree" --yesno "$warn_text" $TTY_Y $TTY_X
	[[ $? -ne 0 ]] && exit_with_error "Error switching to the expert mode"
	SHOW_WARNING=no
}
