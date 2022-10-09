# this gets from cache or produces a new rootfs, and leaves a mounted chroot "$SDCARD" at the end.
get_or_create_rootfs_cache_chroot_sdcard() {
	# @TODO: this was moved from configuration to this stage, that way configuration can be offline
	# if variable not provided, check which is current version in the cache storage in GitHub.
	if [[ -z "${ROOTFSCACHE_VERSION}" ]]; then
		display_alert "ROOTFSCACHE_VERSION not set, getting remotely" "Github API and armbian/mirror " "debug"
		ROOTFSCACHE_VERSION=$(curl https://api.github.com/repos/armbian/cache/releases/latest -s --fail | jq .tag_name -r || true)
		# anonymous API access is very limited which is why we need a fallback
		ROOTFSCACHE_VERSION=${ROOTFSCACHE_VERSION:-$(curl -L --silent https://cache.armbian.com/rootfs/latest --fail)}
	fi

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

	##PRESERVE## # check if cache exists and we want to make it
	##PRESERVE## if [[ -f ${cache_fname} && "$ROOT_FS_CREATE_ONLY" == "yes" ]]; then
	##PRESERVE## 	display_alert "Checking cache integrity" "$display_name" "info"
	##PRESERVE## 	zstd -tqq ${cache_fname} || {
	##PRESERVE## 		rm $cache_fname
	##PRESERVE## 		exit_with_error "Cache $cache_fname is corrupted and was deleted. Please restart!"
	##PRESERVE## 	}
	##PRESERVE## fi

	# if aria2 file exists download didn't succeeded
	if [[ "$ROOT_FS_CREATE_ONLY" != "yes" && -f $cache_fname && ! -f $cache_fname.aria2 ]]; then

		local date_diff=$((($(date +%s) - $(stat -c %Y $cache_fname)) / 86400))
		display_alert "Extracting $cache_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$(logging_echo_prefix_for_pv "extract_rootfs") $cache_name" "$cache_fname" | zstdmt -dc | tar xp --xattrs -C $SDCARD/
		[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Restart."
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf
		create_sources_list "$RELEASE" "$SDCARD/"
	else
		local ROOT_FS_CREATE_VERSION=${ROOT_FS_CREATE_VERSION:-$(date --utc +"%Y%m%d")}
		local cache_name=${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-${ROOT_FS_CREATE_VERSION}.tar.zst
		local cache_fname=${SRC}/cache/rootfs/${cache_name}

		display_alert "Creating new rootfs cache for" "$RELEASE" "info"

		create_new_rootfs_cache

		# needed for backend to keep current only
		echo "$cache_fname" > $cache_fname.current

	fi

	# used for internal purposes. Faster rootfs cache rebuilding
	if [[ "$ROOT_FS_CREATE_ONLY" == "yes" ]]; then
		umount --lazy "$SDCARD"
		rm -rf $SDCARD
		# remove exit trap
		remove_all_trap_handlers INT TERM EXIT
		exit
	fi

	mount_chroot "${SDCARD}"
}

function create_new_rootfs_cache() {
	# this is different between debootstrap and regular apt-get; here we use acng as a prefix to the real repo
	local debootstrap_apt_mirror="http://${APT_MIRROR}"
	if [[ $NO_APT_CACHER != yes ]]; then
		local debootstrap_apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/${APT_MIRROR}"
		acng_check_status_or_restart
	fi

	display_alert "Installing base system" "Stage 1/2" "info"
	cd "${SDCARD}" || exit_with_error "cray-cray about SDCARD" "${SDCARD}" # this will prevent error sh: 0: getcwd() failed
	local -a deboostrap_arguments=(
		"--variant=minbase"                                                # minimal base variant. go ask Debian about it.
		"--include=${DEBOOTSTRAP_LIST// /,}"                               # from aggregation?
		${PACKAGE_LIST_EXCLUDE:+ --exclude="${PACKAGE_LIST_EXCLUDE// /,}"} # exclude some
		"--arch=${ARCH}"                                                   # the arch
		"--components=${DEBOOTSTRAP_COMPONENTS}"                           # from aggregation?
		"--foreign" "${RELEASE}" "${SDCARD}/" "${debootstrap_apt_mirror}"  # path and mirror
	)

	run_host_command_logged debootstrap "${deboostrap_arguments[@]}" || {
		exit_with_error "Debootstrap first stage failed" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	}
	[[ ! -f ${SDCARD}/debootstrap/debootstrap ]] && exit_with_error "Debootstrap first stage did not produce marker file"

	deploy_qemu_binary_to_chroot "${SDCARD}" # this is cleaned-up later by post_debootstrap_tweaks()

	mkdir -p "${SDCARD}/usr/share/keyrings/"
	run_host_command_logged cp -pv /usr/share/keyrings/*-archive-keyring.gpg "${SDCARD}/usr/share/keyrings/"

	display_alert "Installing base system" "Stage 2/2" "info"
	export if_error_detail_message="Debootstrap second stage failed ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	chroot_sdcard LC_ALL=C LANG=C /debootstrap/debootstrap --second-stage
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

	# stage: create apt-get sources list (basic Debian/Ubuntu apt sources, no external nor PPAS)
	create_sources_list "$RELEASE" "$SDCARD/"

	# add armhf arhitecture to arm64, unless configured not to do so.
	if [[ "a${ARMHF_ARCH}" != "askip" ]]; then
		[[ $ARCH == arm64 ]] && chroot_sdcard LC_ALL=C LANG=C dpkg --add-architecture armhf
	fi

	# this should fix resolvconf installation failure in some cases
	chroot_sdcard 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

	# Add external / PPAs to apt sources; decides internally based on minimal/cli/desktop dir/file structure
	add_apt_sources

	# uset asset logging for this; actually log contents of the files too
	run_host_command_logged ls -l "${SDCARD}/usr/share/keyrings"
	run_host_command_logged ls -l "${SDCARD}/etc/apt/sources.list.d"
	run_host_command_logged cat "${SDCARD}/etc/apt/sources.list"

	# stage: update packages list
	display_alert "Updating package list" "$RELEASE" "info"
	do_with_retries 3 chroot_sdcard_apt_get update

	# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
	display_alert "Upgrading base packages" "Armbian" "info"
	do_with_retries 3 chroot_sdcard_apt_get upgrade

	# stage: install additional packages
	display_alert "Installing the main packages for" "Armbian" "info"
	export if_error_detail_message="Installation of Armbian main packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
	# First, try to download-only up to 3 times, to work around network/proxy problems.
	do_with_retries 3 chroot_sdcard_apt_get_install_download_only "$PACKAGE_MAIN_LIST"

	# Now do the install, all packages should have been downloaded by now
	chroot_sdcard_apt_get_install "$PACKAGE_MAIN_LIST"

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
		# Retry download-only 3 times first.
		do_with_retries 3 chroot_sdcard_apt_get_install_download_only ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP

		# Then do the actual install.
		export if_error_detail_message="Installation of Armbian desktop packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
		chroot_sdcard_apt_get install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP
	fi

	# stage: check md5 sum of installed packages. Just in case.
	display_alert "Checking MD5 sum of installed packages" "debsums" "info"
	export if_error_detail_message="Check MD5 sum of installed packages failed"
	# shellcheck disable=SC2154 # this '$' and '\n' syntax is for dpkg-query
	chroot_sdcard dpkg-query -f '"${binary:Package}\n"' -W "|" xargs debsums --silent || true # @TODO: ignore result for now until we can find all the divergences

	# Remove packages from packages.uninstall
	display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
	# shellcheck disable=SC2086
	chroot_sdcard_apt_get purge $PACKAGE_LIST_UNINSTALL

	# stage: purge residual packages
	display_alert "Purging residual packages for" "Armbian" "info"
	PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
	chroot_sdcard_apt_get remove --purge $PURGINGPACKAGES

	# stage: remove downloaded packages
	chroot_sdcard_apt_get autoremove
	chroot_sdcard_apt_get clean

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	[[ -d "${MOUNT}" ]] &&
		display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# create list of installed packages for debug purposes - this captures it's own stdout.
	chroot "${SDCARD}" /bin/bash -c "dpkg -l | grep ^ii | awk '{ print \$2\",\"\$3 }' > '${cache_fname}.list'"

	# creating xapian index that synaptic runs faster
	if [[ $BUILD_DESKTOP == yes ]]; then
		display_alert "Recreating Synaptic search index" "Please wait" "info"
		chroot_sdcard "[[ -f /usr/sbin/update-apt-xapian-index ]] && /usr/sbin/update-apt-xapian-index -u || true"
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
		--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s "$(du -sb $SDCARD/ | cut -f1)" -N "$(logging_echo_prefix_for_pv "store_rootfs") $cache_name" | zstdmt -5 -c > "${cache_fname}"

	# sign rootfs cache archive that it can be used for web cache once. Internal purposes
	if [[ -n "${GPG_PASS}" && "${SUDO_USER}" ]]; then
		[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/
		echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
	fi

	# needed for backend to keep current only
	echo "$cache_fname" > $cache_fname.current

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
