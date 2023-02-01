#!/usr/bin/env bash
# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version

get_package_list_hash() {
	local package_arr exclude_arr
	local list_content
	read -ra package_arr <<< "${DEBOOTSTRAP_LIST} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"
	(
		printf "%s\n" "${package_arr[@]}"
		printf -- "-%s\n" "${exclude_arr[@]}"
	) | sort -u | md5sum | cut -d' ' -f 1
}

# get_rootfs_cache_list <cache_type> <packages_hash>
#
# return a list of versions of all avaiable cache from remote and local.
get_rootfs_cache_list() {
	local cache_type=$1
	local packages_hash=$2

	{
		curl --silent --fail -L "https://api.github.com/repos/armbian/cache/releases?per_page=3" | jq -r '.[].tag_name' \
		|| curl --silent --fail -L https://cache.armbian.com/rootfs/list

		find ${SRC}/cache/rootfs/ -mtime -7 -name "${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-*.tar.zst" |
			sed -e 's#^.*/##' |
			sed -e 's#\..*$##' |
			awk -F'-' '{print $5}'
	} | sort | uniq
}

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache() {
	local packages_hash=$(get_package_list_hash)
	local packages_hash=${packages_hash:0:8}

	local cache_type="cli"
	[[ ${BUILD_DESKTOP} == yes ]] && local cache_type="xfce-desktop"
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"
	[[ ${BUILD_MINIMAL} == yes ]] && local cache_type="minimal"

	# seek last cache, proceed to previous otherwise build it
	local cache_list
	readarray -t cache_list <<< "$(get_rootfs_cache_list "$cache_type" "$packages_hash" | sort -r)"
	for ROOTFSCACHE_VERSION in "${cache_list[@]}"; do

		local cache_name=${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-${ROOTFSCACHE_VERSION}.tar.zst
		local cache_fname=${SRC}/cache/rootfs/${cache_name}

		[[ "$ROOT_FS_CREATE_ONLY" == yes ]] && break

		display_alert "Checking cache" "$cache_name" "info"

		# if aria2 file exists download didn't succeeded
		if [[ ! -f $cache_fname || -f ${cache_fname}.aria2 ]]; then
			display_alert "Downloading from servers"
			download_and_verify "rootfs" "$cache_name" ||
				continue
		fi

		[[ -f $cache_fname && ! -f ${cache_fname}.aria2 ]] && break
	done

	# if aria2 file exists download didn't succeeded
	if [[ "$ROOT_FS_CREATE_ONLY" != "yes" && -f $cache_fname && ! -f $cache_fname.aria2 ]]; then

		local date_diff=$((($(date +%s) - $(stat -c %Y $cache_fname)) / 86400))
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
		chroot $SDCARD /bin/bash -e -c "debsums -s"
		[[ $? -ne 0 ]] && exit_with_error "MD5 sums check of installed packages failed"

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
		display_alert "Free SD cache" "$(echo -e "$freespace" | awk -v mp="${SDCARD}" '$6==mp {print $5}')" "info"
		display_alert "Mount point" "$(echo -e "$freespace" | awk -v mp="${MOUNT}" '$6==mp {print $5}')" "info"

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

		# Remove `machine-id` (https://www.freedesktop.org/software/systemd/man/machine-id.html)
		# Note: This will mark machine `firstboot`
		echo "uninitialized" > "${SDCARD}/etc/machine-id"
		rm "${SDCARD}/var/lib/dbus/machine-id"

		# Mask `systemd-firstboot.service` which will prompt locale, timezone and root-password too early.
		# `armbian-first-run` will do the same thing later
		chroot $SDCARD /bin/bash -c "systemctl mask systemd-firstboot.service >/dev/null 2>&1"

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$SDCARD"

		tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$cache_name" | zstdmt -"$K_ZST" -c > $cache_fname

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
}
