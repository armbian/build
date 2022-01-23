# this gets from cache or produces a new rootfs, and leaves a mounted chroot "$SDCARD" at the end.
get_or_create_rootfs_cache_chroot_sdcard() {
	if [[ "$ROOT_FS_CREATE_ONLY" == "force" ]]; then
		local cycles=1
	else
		local cycles=2
	fi

	# seek last cache, proceed to previous otherwise build it
	for ((n = 0; n < ${cycles}; n++)); do

		[[ -z ${FORCED_MONTH_OFFSET} ]] && FORCED_MONTH_OFFSET=${n}
		local packages_hash=$(get_package_list_hash "$(date -d "$D +${FORCED_MONTH_OFFSET} month" +"%Y-%m-module$ROOTFSCACHE_VERSION" | sed 's/^0*//')")
		local cache_type="cli"
		[[ ${BUILD_DESKTOP} == yes ]] && local cache_type="xfce-desktop"
		[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"
		[[ ${BUILD_MINIMAL} == yes ]] && local cache_type="minimal"
		local cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.lz4
		local cache_fname=${SRC}/cache/rootfs/${cache_name}
		local display_name=${RELEASE}-${cache_type}-${ARCH}.${packages_hash:0:3}...${packages_hash:29}.tar.lz4

		[[ "$ROOT_FS_CREATE_ONLY" == force ]] && break

		if [[ -f ${cache_fname} && -f ${cache_fname}.aria2 ]]; then
			rm ${cache_fname}*
			display_alert "Partially downloaded file. Re-start."
			download_and_verify "_rootfs" "$cache_name"
		fi

		display_alert "Checking local cache" "$display_name" "info"

		if [[ -f ${cache_fname} && -n "$ROOT_FS_CREATE_ONLY" ]]; then
			touch $cache_fname.current
			display_alert "Checking cache integrity" "$display_name" "info"
			sudo lz4 -tqq ${cache_fname}
			[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Please restart!"
			# sign if signature is missing
			if [[ -n "${GPG_PASS}" && "${SUDO_USER}" && ! -f ${cache_fname}.asc ]]; then
				[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/
				echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
			fi
			break
		elif [[ -f ${cache_fname} ]]; then
			break
		else
			display_alert "searching on servers"
			download_and_verify "_rootfs" "$cache_name"
		fi

		if [[ ! -f $cache_fname ]]; then
			display_alert "not found: try to use previous cache"
		fi

	done

	if [[ -f $cache_fname && ! -f $cache_fname.aria2 ]]; then

		# speed up checking
		if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
			touch $cache_fname.current
			umount --lazy "$SDCARD"
			rm -rf $SDCARD
			# remove exit trap
			trap - INT TERM EXIT
			exit
		fi

		local date_diff=$((($(date +%s) - $(stat -c %Y $cache_fname)) / 86400))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$(logging_echo_prefix_for_pv "extract_rootfs") $display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $SDCARD/
		[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Restart."
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf
		create_sources_list "$RELEASE" "$SDCARD/"
	else
		display_alert "... remote not found" "Creating new rootfs cache for $RELEASE" "info"

		create_new_rootfs_cache

		# needed for backend to keep current only
		touch $cache_fname.current

	fi

	# used for internal purposes. Faster rootfs cache rebuilding
	if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
		umount --lazy "$SDCARD"
		rm -rf $SDCARD
		# remove exit trap
		trap - INT TERM EXIT
		exit
	fi

	mount_chroot "$SDCARD"
} #############################################################################

function create_new_rootfs_cache() {
	# @TODO: unify / remove this. distribuitions has the good stuff.
	# stage: debootstrap base system
	if [[ $NO_APT_CACHER != yes ]]; then
		# apt-cacher-ng apt-get proxy parameter
		local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
		local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$APT_MIRROR"
	else
		local apt_mirror="http://$APT_MIRROR"
	fi

	display_alert "Installing base system" "Stage 1/2" "info"
	cd "${SDCARD}" || exit_with_error "cray-cray about SDCARD" "${SDCARD}" # this will prevent error sh: 0: getcwd() failed
	local -a deboostrap_arguments=(
		"--variant=minbase"                                                # minimal base variant. go ask Debian about it.
		"--include=${DEBOOTSTRAP_LIST// /,}"                               # from aggregation?
		${PACKAGE_LIST_EXCLUDE:+ --exclude="${PACKAGE_LIST_EXCLUDE// /,}"} # exclude some
		"--arch=${ARCH}"                                                   # the arch
		"--components=${DEBOOTSTRAP_COMPONENTS}"                           # from aggregation?
		"--foreign" "${RELEASE}" "${SDCARD}/" "${apt_mirror}"              # path and mirror
	)
	debootstrap "${deboostrap_arguments[@]}" 2>&1 || { # invoke debootstrap, stderr to stdout.
		exit_with_error "Debootstrap first stage failed" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	}
	[[ ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap first stage did not produce marker file"

	cp "/usr/bin/$QEMU_BINARY" "$SDCARD/usr/bin/" # @TODO: who cleans this up later?

	mkdir -p "${SDCARD}/usr/share/keyrings/"
	cp /usr/share/keyrings/*-archive-keyring.gpg "${SDCARD}/usr/share/keyrings/"

	display_alert "Installing base system" "Stage 2/2" "info"
	chroot_sdcard LC_ALL=C LANG=C /debootstrap/debootstrap --second-stage 2>&1 || { # invoke inside chroot/qemu, stderr to stdout.
		exit_with_error "Debootstrap second stage failed" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	}
	[[ ! -f "${SDCARD}/bin/bash" ]] && exit_with_error "Debootstrap first stage did not produce /bin/bash"

	mount_chroot "${SDCARD}"

	display_alert "Diverting" "initctl/start-stop-daemon" "info"
	# policy-rc.d script prevents starting or reloading services during image creation
	printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
	chroot_sdcard LC_ALL=C LANG=C dpkg-divert --quiet --local --rename --add /sbin/initctl
	chroot_sdcard LC_ALL=C LANG=C dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon
	printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > "$SDCARD/sbin/start-stop-daemon"
	printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > "$SDCARD/sbin/initctl"
	chmod 755 "$SDCARD/usr/sbin/policy-rc.d"
	chmod 755 "$SDCARD/sbin/initctl"
	chmod 755 "$SDCARD/sbin/start-stop-daemon"

	# stage: configure language and locales
	display_alert "Configuring locales" "$DEST_LANG" "info"

	[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
	chroot_sdcard LC_ALL=C LANG=C locale-gen "$DEST_LANG"
	chroot_sdcard LC_ALL=C LANG=C update-locale "LANG=$DEST_LANG" "LANGUAGE=$DEST_LANG" "LC_MESSAGES=$DEST_LANG"

	if [[ -f $SDCARD/etc/default/console-setup ]]; then
		# @TODO: Should be configurable.
		sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
			-e 's/CODESET=.*/CODESET="guess"/' -i "$SDCARD/etc/default/console-setup"
		chroot_sdcard LC_ALL=C LANG=C setupcon --save --force
	fi

	# stage: create apt-get sources list
	create_sources_list "$RELEASE" "$SDCARD/"

	# add armhf arhitecture to arm64, unless configured not to do so.
	if [[ "a${ARMHF_ARCH}" != "askip" ]]; then
		[[ $ARCH == arm64 ]] && chroot_sdcard LC_ALL=C LANG=C dpkg --add-architecture armhf
	fi

	# this should fix resolvconf installation failure in some cases
	chroot_sdcard 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

	# stage: update packages list
	display_alert "Updating package list" "$RELEASE" "info"
	chroot_sdcard_apt_get update || {
		display_alert "Updating package lists" "failed" "wrn"
	}

	# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
	display_alert "Upgrading base packages" "Armbian" "info"
	chroot_sdcard_apt_get upgrade || {
		display_alert "Upgrading packages" "failed" "wrn"
	}

	# Myy: Dividing the desktop packages installation steps into multiple
	# ones. We first install the "ADDITIONAL_PACKAGES" in order to get
	# access to software-common-properties installation.
	# THEN we add the APT sources and install the Desktop packages.
	# TODO : Find a way to add APT sources WITHOUT software-common-properties

	# stage: install additional packages
	display_alert "Installing the main packages for" "Armbian" "info"
	chroot_sdcard_apt_get_install "$PACKAGE_MAIN_LIST" || {
		exit_with_error "Installation of Armbian main packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
	}

	if [[ $BUILD_DESKTOP == "yes" ]]; then
		# FIXME Myy : Are we keeping this only for Desktop users,
		# or should we extend this to CLI users too ?
		# There might be some clunky boards that require Debian packages from
		# specific repos...
		display_alert "Adding apt sources for Desktop packages"
		add_desktop_package_sources

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
		chroot_sdcard_apt_get install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP || {
			exit_with_error "Installation of Armbian desktop packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
		}
	fi

	# Remove packages from packages.uninstall
	display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
	# shellcheck disable=SC2086
	chroot_sdcard_apt_get purge $PACKAGE_LIST_UNINSTALL || exit_with_error "Un-Installation of packages failed"

	# stage: purge residual packages
	display_alert "Purging residual packages for" "Armbian" "info"
	PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
	chroot_sdcard_apt_get remove --purge $PURGINGPACKAGES || {
		exit_with_error "Purging of residual Armbian packages failed"
	}

	# stage: remove downloaded packages
	chroot_sdcard_apt_get clean

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	[[ -d "${MOUNT}" ]] &&
		display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# create list of installed packages for debug purposes - this captures it's own stdout.
	chroot "${SDCARD}" /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > "${cache_fname}.list"

	# creating xapian index that synaptic runs faster
	if [[ $BUILD_DESKTOP == yes ]]; then
		display_alert "Recreating Synaptic search index" "Please wait" "info"
		chroot_sdcard "[[ -f /usr/sbin/update-apt-xapian-index ]] && /usr/sbin/update-apt-xapian-index -u || true"
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
		--exclude='./sys/*' . | pv -p -b -r -s "$(du -sb $SDCARD/ | cut -f1)" -N "$(logging_echo_prefix_for_pv "store_rootfs") $display_name" | lz4 -5 -c > "$cache_fname"

	# sign rootfs cache archive that it can be used for web cache once. Internal purposes
	if [[ -n "${GPG_PASS}" && "${SUDO_USER}" ]]; then
		[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/
		echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
	fi

	return 0 # protect against possible future short-circuiting above this
}

# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version
get_package_list_hash() {
	local package_arr exclude_arr
	local list_content
	read -ra package_arr <<< "${DEBOOTSTRAP_LIST} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"
	( 
		(
			printf "%s\n" "${package_arr[@]}"
			printf -- "-%s\n" "${exclude_arr[@]}"
		) | sort -u
		echo "${1}"
	) |
		md5sum | cut -d' ' -f 1
}
