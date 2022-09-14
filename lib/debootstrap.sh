#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:

# debootstrap_ng
# get_rootfs_cache_list
# create_rootfs_cache
# prepare_partitions
# update_initramfs
# create_image




# debootstrap_ng
#
debootstrap_ng()
{
	display_alert "Checking for rootfs cache" "$(echo "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" | tr -s " ")" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	# bind mount rootfs if defined
	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/toolchain
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}"/cache/rootfs
	fi

	# stage: verify tmpfs configuration and mount
	# CLI needs ~1.5GiB, desktop - ~3.5GiB
	# calculate and set tmpfs mount to use 9/10 of available RAM+SWAP
	local phymem=$(( (($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then	local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" << 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
*give config a chance to act before install_distribution_specific*
Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
PRE_INSTALL_DISTRIBUTION_SPECIFIC

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	install_distribution_specific
	install_common

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local

	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	customize_image

	# remove packages that are no longer needed. Since we have intrudoced uninstall feature, we might want to clean things that are no longer needed
	display_alert "No longer needed packages" "purge" "info"
	chroot $SDCARD /bin/bash -c "apt-get autoremove -y"  >/dev/null 2>&1

	# create list of all installed packages for debug purposes
	chroot $SDCARD /bin/bash -c "dpkg -l | grep ^ii | awk '{ print \$2\",\"\$3 }'" > $DEST/${LOG_SUBPATH}/installed-packages-${RELEASE}$([[ ${BUILD_MINIMAL} == yes ]] \
	&& echo "-minimal")$([[ ${BUILD_DESKTOP} == yes  ]] && echo "-desktop").list 2>&1

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"
	post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	# stage: unmount tmpfs
	umount $SDCARD 2>&1
	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts
		do
			umount $SDCARD
			sleep 5
		done
	fi
	rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
} #############################################################################

# get_rootfs_cache_list <cache_type> <packages_hash>
#
# return a list of versions of all avaiable cache from remote and local.
get_rootfs_cache_list()
{
	local cache_type=$1
	local packages_hash=$2

	{
		# Temportally disable Github API because we don't support to download from it
		# curl --silent --fail -L "https://api.github.com/repos/armbian/cache/releases?per_page=3" | jq -r '.[].tag_name' \
		# || curl --silent --fail -L https://cache.armbian.com/rootfs/list
		curl --silent --fail -L https://cache.armbian.com/rootfs/list

		find ${SRC}/cache/rootfs/ -mtime -7 -name "${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-*.tar.zst" \
			| sed -e 's#^.*/##' \
			| sed -e 's#\..*$##' \
			| awk -F'-' '{print $5}'
	} | sort | uniq
}

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache()
{
	local packages_hash=$(get_package_list_hash)
	local packages_hash=${packages_hash:0:8}

	local cache_type="cli"
	[[ ${BUILD_DESKTOP} == yes ]] && local cache_type="xfce-desktop"
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"
	[[ ${BUILD_MINIMAL} == yes ]] && local cache_type="minimal"

	# seek last cache, proceed to previous otherwise build it
	local cache_list
	readarray -t cache_list <<<"$(get_rootfs_cache_list "$cache_type" "$packages_hash" | sort -r)"
	for ROOTFSCACHE_VERSION in "${cache_list[@]}"; do

		local cache_name=${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-${ROOTFSCACHE_VERSION}.tar.zst
		local cache_fname=${SRC}/cache/rootfs/${cache_name}

		[[ "$ROOT_FS_CREATE_ONLY" == yes ]] && break

		display_alert "Checking cache" "$cache_name" "info"

		if [[ -f ${cache_fname}.aria2 ]]; then
			display_alert "Removing partially downloaded file."
			rm ${cache_fname}*
		fi

		if [[ ! -f $cache_fname ]]; then
			display_alert "Downloading from servers"
			download_and_verify "_rootfs" "$cache_name"
		fi

		if [[ ! -f ${cache_fname} ]]; then
			display_alert "not found"
			continue
		fi

		break
	done

	# if aria2 file exists download didn't succeeded
	if [[ "$ROOT_FS_CREATE_ONLY" != "yes" && -f $cache_fname && ! -f $cache_fname.aria2 ]]; then

		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $cache_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "[ .... ] $cache_name" "$cache_fname" | zstdmt -dc | tar xp --xattrs -C $SDCARD/
		[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Restart."
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf
		create_sources_list "$RELEASE" "$SDCARD/"
	else

		local ROOT_FS_CREATE_VERSION=${ROOT_FS_CREATE_VERSION:-$(date --utc +"%Y%m%d")}
		local cache_name=${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-${ROOT_FS_CREATE_VERSION}.tar.zst
		local cache_fname=${SRC}/cache/rootfs/${cache_name}

		display_alert "Creating new rootfs cache for" "$RELEASE" "info"

		# stage: debootstrap base system
		if [[ $NO_APT_CACHER != yes ]]; then
			# apt-cacher-ng apt-get proxy parameter
			local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$APT_MIRROR"
		else
			local apt_mirror="http://$APT_MIRROR"
		fi

		# fancy progress bars
		[[ -z $OUTPUT_DIALOG ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		# Ok so for eval+PIPESTATUS.
		# Try this on your bash shell:
		# ONEVAR="testing" eval 'bash -c "echo value once $ONEVAR && false && echo value twice $ONEVAR"' '| grep value'  '| grep value' ; echo ${PIPESTATUS[*]}
		# Notice how PIPESTATUS has only one element. and it is always true, although we failed explicitly with false in the middle of the bash.
		# That is because eval itself is considered a single command, no matter how many pipes you put in there, you'll get a single value, the return code of the LAST pipe.
		# Lets export the value of the pipe inside eval so we know outside what happened:
		# ONEVAR="testing" eval 'bash -e -c "echo value once $ONEVAR && false && echo value twice $ONEVAR"' '| grep value'  '| grep value' ';EVALPIPE=(${PIPESTATUS[@]})' ; echo ${EVALPIPE[*]}

		display_alert "Installing base system" "Stage 1/2" "info"
		cd $SDCARD # this will prevent error sh: 0: getcwd() failed
		eval 'debootstrap --variant=minbase --include=${DEBOOTSTRAP_LIST// /,} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --components=${DEBOOTSTRAP_COMPONENTS} $DEBOOTSTRAP_OPTION --foreign $RELEASE $SDCARD/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 || ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} first stage failed"

		cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/

		mkdir -p $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/*-archive-keyring.gpg $SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 || ! -f $SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} second stage failed"

		mount_chroot "$SDCARD"

		display_alert "Diverting" "initctl/start-stop-daemon" "info"
		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
		LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl" &> /dev/null
		LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon" &> /dev/null
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl
		chmod 755 $SDCARD/usr/sbin/policy-rc.d
		chmod 755 $SDCARD/sbin/initctl
		chmod 755 $SDCARD/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Generatining default locale" "info"
		if [[ -f $SDCARD/etc/locale.gen ]]; then
			sed -i '/ C.UTF-8/s/^# //g' $SDCARD/etc/locale.gen
			sed -i '/en_US.UTF-8/s/^# //g' $SDCARD/etc/locale.gen
		fi
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>&1'}
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale --reset LANG=en_US.UTF-8"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>&1'}

		if [[ -f $SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save --force"'
		fi

		# stage: create apt-get sources list
		create_sources_list "$RELEASE" "$SDCARD/"

		# add armhf arhitecture to arm64, unless configured not to do so.
		if [[ "a${ARMHF_ARCH}" != "askip" ]]; then
			[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'
		fi

		# this should fix resolvconf installation failure in some cases
		chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

		# TODO change name of the function from "desktop" and move to appropriate location
		add_desktop_package_sources

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && display_alert "Updating package lists" "failed" "wrn"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Upgrading base packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && display_alert "Upgrading base packages" "failed" "wrn"

		# stage: install additional packages
		display_alert "Installing the main packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_MAIN_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian main packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Installation of Armbian main packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"

		if [[ $BUILD_DESKTOP == "yes" ]]; then

			local apt_desktop_install_flags=""
			if [[ ! -z ${DESKTOP_APT_FLAGS_SELECTED+x} ]]; then
				for flag in ${DESKTOP_APT_FLAGS_SELECTED}; do
					apt_desktop_install_flags+=" --install-${flag}"
				done
			else
				# Myy : Using the previous default option, if the variable isn't defined
				# And ONLY if it's not defined !
				apt_desktop_install_flags+=" --no-install-recommends"
			fi

			display_alert "Installing the desktop packages for" "Armbian" "info"
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
				$apt_extra $apt_extra_progress install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP"' \
				${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
				${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian desktop packages..." $TTY_Y $TTY_X'} \
				${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

			[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Installation of Armbian desktop packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
		fi

		# stage: check md5 sum of installed packages. Just in case.
		display_alert "Checking MD5 sum of installed packages" "debsums" "info"
		eval 'LC_ALL=C LANG=C sudo chroot $SDCARD /bin/bash -e -c "dpkg-query -f ${binary:Package} -W | xargs debsums"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} '>/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'
		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "MD5 sums check of installed packages failed"

		# Remove packages from packages.uninstall

		display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
			$apt_extra $apt_extra_progress purge $PACKAGE_LIST_UNINSTALL"' \
			${PROGRESS_LOG_TO_FILE:+' >> $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Removing packages.uninstall packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# stage: purge residual packages
		display_alert "Purging residual packages for" "Armbian" "info"
		PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress remove --purge $PURGINGPACKAGES"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Purging residual Armbian packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Purging of residual Armbian packages failed"

		# stage: remove downloaded packages
		chroot $SDCARD /bin/bash -c "apt-get -y autoremove; apt-get clean"

		# DEBUG: print free space
		local freespace=$(LC_ALL=C df -h)
		echo -e "$freespace" >> $DEST/${LOG_SUBPATH}/debootstrap.log
		display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
		display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

		# create list of installed packages for debug purposes
		chroot $SDCARD /bin/bash -c "dpkg -l | grep ^ii | awk '{ print \$2\",\"\$3 }'" > ${cache_fname}.list 2>&1

		# creating xapian index that synaptic runs faster
		if [[ $BUILD_DESKTOP == yes ]]; then
			display_alert "Recreating Synaptic search index" "Please wait" "info"
			chroot $SDCARD /bin/bash -c "[[ -f /usr/sbin/update-apt-xapian-index ]] && /usr/sbin/update-apt-xapian-index -u"
		fi

		# this is needed for the build process later since resolvconf generated file in /run is not saved
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$SDCARD"

		tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$cache_name" | zstdmt -5 -c > $cache_fname

		# sign rootfs cache archive that it can be used for web cache once. Internal purposes
		if [[ -n "${GPG_PASS}" && "${SUDO_USER}" ]]; then
			[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/
			echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
		fi

	fi

	# used for internal purposes. Faster rootfs cache rebuilding
	if [[ "$ROOT_FS_CREATE_ONLY" == "yes" ]]; then
		umount --lazy "$SDCARD"
		rm -rf $SDCARD
		# remove exit trap
		trap - INT TERM EXIT
        exit
	fi

	mount_chroot "$SDCARD"
} #############################################################################

# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# possible partition combinations
	# /boot: none, ext4, ext2, fat (BOOTFS_TYPE)
	# root: ext4, btrfs, f2fs, nfs (ROOTFS_TYPE)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkopts_label mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	parttype[xfs]=xfs
	# parttype[nfs] is empty

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	# add -N number of inodes to keep mount from running out
	# create bigger number for desktop builds
	if [[ $BUILD_DESKTOP == yes ]]; then local node_number=4096; else local node_number=1024; fi
	if [[ $HOSTRELEASE =~ buster|bullseye|focal|jammy|sid ]]; then
		mkopts[ext4]="-q -m 2 -O ^64bit,^metadata_csum -N $((128*${node_number}))"
	fi
	# mkopts[fat] is empty
	mkopts[ext2]='-q'
	# mkopts[f2fs] is empty
	mkopts[btrfs]='-m dup'
	# mkopts[xfs] is empty
	# mkopts[nfs] is empty

	mkopts_label[ext4]='-L '
	mkopts_label[ext2]='-L '
	mkopts_label[fat]='-n '
	mkopts_label[f2fs]='-l '
	mkopts_label[btrfs]='-L '
	mkopts_label[xfs]='-L '
	# mkopts_label[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	mkfs[xfs]=xfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[ext2] is empty
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	mountopts[btrfs]=',commit=600'
	# mountopts[xfs] is empty
	# mountopts[nfs] is empty

	# default BOOTSIZE to use if not specified
	DEFAULT_BOOTSIZE=256	# MiB
	# size of UEFI partition. 0 for no UEFI. Don't mix UEFISIZE>0 and BOOTSIZE>0
	UEFISIZE=${UEFISIZE:-0}
	BIOSSIZE=${BIOSSIZE:-0}
	UEFI_MOUNT_POINT=${UEFI_MOUNT_POINT:-/boot/efi}
	UEFI_FS_LABEL="${UEFI_FS_LABEL:-armbi_efi}"
	ROOT_FS_LABEL="${ROOT_FS_LABEL:-armbi_root}"
	BOOT_FS_LABEL="${BOOT_FS_LABEL:-armbi_boot}"

	call_extension_method "pre_prepare_partitions" "prepare_partitions_custom" <<'PRE_PREPARE_PARTITIONS'
*allow custom options for mkfs*
Good time to change stuff like mkfs opts, types etc.
PRE_PREPARE_PARTITIONS

	# stage: determine partition configuration
	local next=1
	# Check if we need UEFI partition
	if [[ $UEFISIZE -gt 0 ]]; then
		if [[ "${IMAGE_PARTITION_TABLE}" == "gpt" ]]; then
			local uefipart=15
			# Check if we need BIOS partition
			[[ $BIOSSIZE -gt 0 ]] && local biospart=14
		else
			local uefipart=$(( next++ ))
		fi
	fi
	# Check if we need boot partition
	if [[ -n $BOOTFS_TYPE || $ROOTFS_TYPE != ext4 || $CRYPTROOT_ENABLE == yes ]]; then
		local bootpart=$(( next++ ))
		local bootfs=${BOOTFS_TYPE:-ext4}
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	else
		BOOTSIZE=0
	fi
	# Check if we need root partition
	[[ $ROOTFS_TYPE != nfs ]] \
		&& local rootpart=$(( next++ ))

	# stage: calculate rootfs size
	export rootfs_size=$(du -sm $SDCARD/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"

	call_extension_method "prepare_image_size" "config_prepare_image_size" << 'PREPARE_IMAGE_SIZE'
*allow dynamically determining the size based on the $rootfs_size*
Called after `${rootfs_size}` is known, but before `${FIXED_IMAGE_SIZE}` is taken into account.
A good spot to determine `FIXED_IMAGE_SIZE` based on `rootfs_size`.
UEFISIZE can be set to 0 for no UEFI partition, or to a size in MiB to include one.
Last chance to set `USE_HOOK_FOR_PARTITION`=yes and then implement create_partition_table hook_point.
PREPARE_IMAGE_SIZE

	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $ROOTFS_TYPE != nfs && $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE + $UEFISIZE + $EXTRA_ROOTFS_MIB_SIZE)) # MiB
		# +40% overhead for kernel, boot loader and plymouth. Align the size up to 4MiB
		local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.40) / 1 + 0) / 4 + 1) * 4")
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	if [[ $FAST_CREATE_IMAGE == yes ]]; then
		truncate --size=${sdsize}M ${SDCARD}.raw # sometimes results in fs corruption, revert to previous know to work solution
		sync
	else
		dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) -N "[ .... ] dd" | dd status=none of=${SDCARD}.raw
	fi

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	if [[ "${USE_HOOK_FOR_PARTITION}" == "yes" ]]; then
		{
			[[ "$IMAGE_PARTITION_TABLE" == "msdos" ]] \
				&& echo "label: dos" \
				|| echo "label: $IMAGE_PARTITION_TABLE"
		} | sfdisk ${SDCARD}.raw >>"${DEST}/${LOG_SUBPATH}/install.log" 2>&1 \
			|| exit_with_error "Create partition table fail. Please check" "${DEST}/${LOG_SUBPATH}/install.log"

		call_extension_method "create_partition_table" <<- 'CREATE_PARTITION_TABLE'
		*only called when USE_HOOK_FOR_PARTITION=yes to create the complete partition table*
		Finally, we can get our own partition table. You have to partition ${SDCARD}.raw
		yourself. Good luck.
		CREATE_PARTITION_TABLE
	else
		{
			[[ "$IMAGE_PARTITION_TABLE" == "msdos" ]] \
				&& echo "label: dos" \
				|| echo "label: $IMAGE_PARTITION_TABLE"

			local next=$OFFSET
			if [[ -n "$biospart" ]]; then
				echo "$biospart : name=\"bios\", start=${next}MiB, size=${BIOSSIZE}MiB, type=\"BIOS boot\""
				local next=$(( $next + $BIOSSIZE ))
			fi
			if [[ -n "$uefipart" ]]; then
				echo "$uefipart : name=\"efi\", start=${next}MiB, size=${UEFISIZE}MiB, type=uefi"
				local next=$(( $next + $UEFISIZE ))
			fi
			if [[ -n "$bootpart" ]]; then
				if [[ -n "$rootpart" ]]; then
					echo "$bootpart : name=\"bootfs\", start=${next}MiB, size=${BOOTSIZE}MiB, type=\"Linux extended boot\""
					local next=$(( $next + $BOOTSIZE ))
				else
					# no `size` argument mean "as much as possible"
					echo "$bootpart : name=\"bootfs\", start=${next}MiB, type=linux"
				fi
			fi
			if [[ -n "$rootpart" ]]; then
				# no `size` argument  mean "as much as possible"
				echo "$rootpart : name=\"rootfs\", start=${next}MiB, type=linux"
			fi
		} | sfdisk ${SDCARD}.raw >>"${DEST}/${LOG_SUBPATH}/install.log" 2>&1 \
			|| exit_with_error "Partition fail. Please check" "${DEST}/${LOG_SUBPATH}/install.log"
	fi

	call_extension_method "post_create_partitions" <<- 'POST_CREATE_PARTITIONS'
	*called after all partitions are created, but not yet formatted*
	POST_CREATE_PARTITIONS

	# stage: mount image
	# lock access to loop devices
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -x $FD

	LOOP=$(losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	check_loop_device "$LOOP"

	losetup $LOOP ${SDCARD}.raw

	# loop device was grabbed here, unlock
	flock -u $FD

	partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	rm -f $SDCARD/etc/fstab
	if [[ -n $rootpart ]]; then
		local rootdevice="${LOOP}p${rootpart}"

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			display_alert "Encrypting root partition with LUKS..." "cryptsetup luksFormat $rootdevice" ""
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksFormat $CRYPTROOT_PARAMETERS $rootdevice -
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksOpen $rootdevice $ROOT_MAPPER -
			display_alert "Root partition encryption complete." "" "ext"
			# TODO: pass /dev/mapper to Docker
			rootdevice=/dev/mapper/$ROOT_MAPPER # used by `mkfs` and `mount` commands
		fi

		check_loop_device "$rootdevice"
		display_alert "Creating rootfs" "$ROOTFS_TYPE on $rootdevice"
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} $rootdevice >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback $rootdevice > /dev/null
		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi
		mount ${fscreateopt} $rootdevice $MOUNT/
		# create fstab (and crypttab) entry
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			# map the LUKS container partition via its UUID to be the 'cryptroot' device
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab
			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	else
		# update_initramfs will fail if /lib/modules/ doesn't exist
		mount --bind --make-private $SDCARD $MOUNT/
		echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${mkopts_label[$bootfs]:+${mkopts_label[$bootfs]}"$BOOT_FS_LABEL"} ${LOOP}p${bootpart} >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
		mkdir -p $MOUNT/boot/
		mount ${LOOP}p${bootpart} $MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi
	if [[ -n $uefipart ]]; then
		display_alert "Creating EFI partition" "FAT32 ${UEFI_MOUNT_POINT} on ${LOOP}p${uefipart} label ${UEFI_FS_LABEL}"
		check_loop_device "${LOOP}p${uefipart}"
		mkfs.fat -F32 -n "${UEFI_FS_LABEL}" ${LOOP}p${uefipart} >>"${DEST}"/debug/install.log 2>&1
		mkdir -p "${MOUNT}${UEFI_MOUNT_POINT}"
		mount ${LOOP}p${uefipart} "${MOUNT}${UEFI_MOUNT_POINT}"
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${uefipart}) ${UEFI_MOUNT_POINT} vfat defaults 0 2" >>$SDCARD/etc/fstab
	fi
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	call_extension_method "format_partitions" <<- 'FORMAT_PARTITIONS'
	*if you created your own partitions, this would be a good time to format them*
	The loop device is mounted, so ${LOOP}p1 is it's first partition etc.
	FORMAT_PARTITIONS

	# stage: adjust boot script or boot environment
	if [[ -f $SDCARD/boot/armbianEnv.txt ]]; then
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "rootdev=$rootdevice cryptdevice=UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}):$ROOT_MAPPER" >> $SDCARD/boot/armbianEnv.txt
		else
			echo "rootdev=$rootfs" >> $SDCARD/boot/armbianEnv.txt
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/$bootscript_dst
	fi

	# if we have boot.ini = remove armbianEnv.txt and add UUID there if enabled
	if [[ -f $SDCARD/boot/boot.ini ]]; then
		sed -i -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.ini
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			local rootpart="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
			sed -i 's/^setenv rootdev .*/setenv rootdev "\/dev\/mapper\/'$ROOT_MAPPER' cryptdevice='$rootpart':'$ROOT_MAPPER'"/' $SDCARD/boot/boot.ini
		else
			sed -i 's/^setenv rootdev .*/setenv rootdev "'$rootfs'"/' $SDCARD/boot/boot.ini
		fi
		if [[  $LINUXFAMILY != meson64 ]]; then
			[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
		fi
	fi

	# if we have a headless device, set console to DEFAULT_CONSOLE
	if [[ -n $DEFAULT_CONSOLE && -f $SDCARD/boot/armbianEnv.txt ]]; then
		if grep -lq "^console=" $SDCARD/boot/armbianEnv.txt; then
			sed -i "s/^console=.*/console=$DEFAULT_CONSOLE/" $SDCARD/boot/armbianEnv.txt
		else
			echo "console=$DEFAULT_CONSOLE" >> $SDCARD/boot/armbianEnv.txt
	        fi
	fi

	# recompile .cmd to .scr if boot.cmd exists

	if [[ -f $SDCARD/boot/boot.cmd ]]; then
		if [ -z $BOOTSCRIPT_OUTPUT ]; then BOOTSCRIPT_OUTPUT=boot.scr; fi
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/$BOOTSCRIPT_OUTPUT > /dev/null 2>&1
	fi


	# create extlinux config
	if [[ -f $SDCARD/boot/extlinux/extlinux.conf ]]; then
		echo "  append root=$rootfs $SRC_CMDLINE $MAIN_CMDLINE" >> $SDCARD/boot/extlinux/extlinux.conf
		[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
	fi

} #############################################################################

# update_initramfs
#
# this should be invoked as late as possible for any modifications by
# customize_image (userpatches) and prepare_partitions to be reflected in the
# final initramfs
#
# especially, this needs to be invoked after /etc/crypttab has been created
# for cryptroot-unlock to work:
# https://serverfault.com/questions/907254/cryproot-unlock-with-dropbear-timeout-while-waiting-for-askpass
#
# since Debian buster, it has to be called within create_image() on the $MOUNT
# path instead of $SDCARD (which can be a tmpfs and breaks cryptsetup-initramfs).
# see: https://github.com/armbian/build/issues/1584
#
update_initramfs()
{
	local chroot_target=$1
	local target_dir=$(
		find ${chroot_target}/lib/modules/ -maxdepth 1 -type d -name "*${VER}*"
	)
	if [ "$target_dir" != "" ]; then
		update_initramfs_cmd="update-initramfs -uv -k $(basename $target_dir)"
	else
		exit_with_error "No kernel installed for the version" "${VER}"
	fi
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/"

	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" >> $DEST/${LOG_SUBPATH}/install.log 2>&1 || {
		display_alert "Updating initramfs FAILED, see:" "$DEST/${LOG_SUBPATH}/install.log" "err"
		exit 23
	}
	display_alert "Updated initramfs." "for details see: $DEST/${LOG_SUBPATH}/install.log" "info"

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# create DESTIMG, hooks might put stuff there early.
	mkdir -p $DESTIMG

	# stage: create file name
	local version="${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to" "/"
		echo -e "\nCopying files to [/]" >>"${DEST}"/${LOG_SUBPATH}/install.log
		rsync -aHWXh \
			  --exclude="/boot/*" \
			  --exclude="/dev/*" \
			  --exclude="/proc/*" \
			  --exclude="/run/*" \
			  --exclude="/tmp/*" \
			  --exclude="/sys/*" \
			  --info=progress0,stats1 $SDCARD/ $MOUNT/ >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "rootfs.tgz" | gzip -c > $DEST/images/${version}-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot"
	echo -e "\nCopying files to [/boot]" >>"${DEST}"/${LOG_SUBPATH}/install.log
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh \
			  --info=progress0,stats1 \
			  --log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT
	else
		# ext4
		rsync -aHWXh \
			  --info=progress0,stats1 \
			  --log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" << 'PRE_UPDATE_INITRAMFS'
*allow config to hack into the initramfs create process*
Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ -n $KERNELSOURCE ]] && {
		update_initramfs $MOUNT
	}

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	echo -e "$freespace" >> $DEST/${LOG_SUBPATH}/debootstrap.log
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# stage: write u-boot, unless the deb is not there, which would happen if BOOTCONFIG=none
	# exception: if we use the one from repository, install version which was downloaded from repo
	if [[ -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
		 write_uboot $LOOP
	elif [[ "${UPSTREM_VER}" ]]; then
		 write_uboot $LOOP
	fi

	# fix wrong / permissions
	chmod 755 $MOUNT

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" << 'PRE_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image before the unmount*
Called before unmounting both `/root` and `/boot`.
PRE_UMOUNT_FINAL_IMAGE

	# Check the partition table after the uboot code has been written
	# and print to the log file.
	echo -e "\nPartition table after write_uboot $LOOP" >>$DEST/${LOG_SUBPATH}/debootstrap.log
	sfdisk -l $LOOP >>$DEST/${LOG_SUBPATH}/debootstrap.log

	# unmount /boot/efi first, then /boot, rootfs third, image file last
	sync
	[[ $UEFISIZE != 0 ]] && umount -l "${MOUNT}${UEFI_MOUNT_POINT}"
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" << 'POST_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image after the unmount*
Called after unmounting both `/root` and `/boot`.
POST_UMOUNT_FINAL_IMAGE

	# to make sure its unmounted
	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts
	do
		display_alert "Wait for unmount" "${MOUNT}" "info"
		sleep 5
	done

	losetup -d $LOOP
	# Don't delete $DESTIMG here, extensions might have put nice things there already.
	rm -rf --one-file-system $MOUNT

	mkdir -p $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${version}.img

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	if [[ -z $SEND_TO_SERVER ]]; then

		if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,img"
		elif [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.gz" "info"
			pigz -3 < $DESTIMG/${version}.img > $DESTIMG/${version}.img.gz
			compression_type=".gz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.xz" "info"
			# compressing consumes a lot of memory we don't have. Waiting for previous packing job to finish helps to run a lot more builds in parallel
			available_cpu=$(grep -c 'processor' /proc/cpuinfo)
			[[ ${available_cpu} -gt 16 ]] && available_cpu=16 # using more cpu cores for compressing is pointless
			available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}') # in percentage
			# build optimisations when memory drops below 5%
			pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < $DESTIMG/${version}.img > ${DESTIMG}/${version}.img.xz
			compression_type=".xz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
#			mv $DESTIMG/${version}.img ${FINALDEST}/${version}.img || exit 1
			compression_type=""
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			cd ${DESTIMG}
			display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
			sha256sum -b ${version}.img${compression_type} > ${version}.img${compression_type}.sha
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
			cd ${DESTIMG}
			if [[ -n $GPG_PASS ]]; then
				display_alert "GPG signing" "${version}.img${compression_type}" "info"
				if [[ -n $SUDO_USER ]]; then
					sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DESTIMG}"/
					SUDO_PREFIX="sudo -H -u ${SUDO_USER}"
				else
					SUDO_PREFIX=""
				fi
				echo "${GPG_PASS}" | $SUDO_PREFIX bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${DESTIMG}/${version}.img${compression_type}" || exit 1
			else
				display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
			fi
		fi

		fingerprint_image "${DESTIMG}/${version}.img${compression_type}.txt" "${version}"

		if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.7z" "info"
			7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on \
			${DESTIMG}/${version}.7z ${version}.key ${version}.img* >/dev/null 2>&1
			find ${DESTIMG}/ -type \
			f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 \
			| xargs -0 rm >/dev/null 2>&1
		fi

	fi
	display_alert "Done building" "${DESTIMG}/${version}.img" "info"

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	export FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image"  << 'POST_BUILD_IMAGE'
*custom post build hook*
Called after the final .img file is built, before it is (possibly) written to an SD writer.
- *NOTE*: this hook used to take an argument ($1) for the final image produced.
  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
It is the last possible chance to modify `$CARD_DEVICE`.
POST_BUILD_IMAGE

	# move artefacts from temporally directory to its final destination
	[[ -n $compression_type ]] && rm $DESTIMG/${version}.img
	rsync -a --no-owner --no-group --remove-source-files $DESTIMG/${version}* ${FINALDEST}
	rm -rf --one-file-system $DESTIMG

	# write image to SD card
	if [[ $(lsblk "$CARD_DEVICE" 2>/dev/null) && -f ${FINALDEST}/${version}.img ]]; then

		# make sha256sum if it does not exists. we need it for comparisson
		if [[ -f "${FINALDEST}/${version}".img.sha ]]; then
			local ifsha=$(cat ${FINALDEST}/${version}.img.sha | awk '{print $1}')
		else
			local ifsha=$(sha256sum -b "${FINALDEST}/${version}".img | awk '{print $1}')
		fi

		display_alert "Writing image" "$CARD_DEVICE ${readsha}" "info"

		# write to SD card
		pv -p -b -r -c -N "[ .... ] dd" ${FINALDEST}/${version}.img | dd of=$CARD_DEVICE bs=1M iflag=fullblock oflag=direct status=none

		call_extension_method "post_write_sdcard"  <<- 'POST_BUILD_IMAGE'
		*run after writing img to sdcard*
		After the image is written to `$CARD_DEVICE`, but before verifying it.
		You can still set SKIP_VERIFY=yes to skip verification.
		POST_BUILD_IMAGE

		if [[ "${SKIP_VERIFY}" != "yes" ]]; then
			# read and compare
			display_alert "Verifying. Please wait!"
			local ofsha=$(dd if=$CARD_DEVICE count=$(du -b ${FINALDEST}/${version}.img | cut -f1) status=none iflag=count_bytes oflag=direct | sha256sum | awk '{print $1}')
			if [[ $ifsha == $ofsha ]]; then
				display_alert "Writing verified" "${version}.img" "info"
			else
				display_alert "Writing failed" "${version}.img" "err"
			fi
		fi
	elif [[ `systemd-detect-virt` == 'docker' && -n $CARD_DEVICE ]]; then
		# display warning when we want to write sd card under Docker
		display_alert "Can't write to $CARD_DEVICE" "Enable docker privileged mode in config-docker.conf" "wrn"
	fi

} #############################################################################
