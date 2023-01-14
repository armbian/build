#!/usr/bin/env bash

# this gets from cache or produces a new rootfs, and leaves a mounted chroot "$SDCARD" at the end.
get_or_create_rootfs_cache_chroot_sdcard() {
	# @TODO: this was moved from configuration to this stage, that way configuration can be offline
	# if variable not provided, check which is current version in the cache storage in GitHub.
	if [[ -z "${ROOTFSCACHE_VERSION}" ]]; then
		if [[ "${SKIP_ARMBIAN_REPO}" != "yes" ]]; then
			display_alert "ROOTFSCACHE_VERSION not set, getting remotely" "Github API and armbian/mirror " "debug"
			# rpardini: why 2 calls?
			# this uses `jq` hostdep
			ROOTFSCACHE_VERSION=$(curl https://api.github.com/repos/armbian/cache/releases/latest -s --fail | jq .tag_name -r || true)
			# anonymous API access is very limited which is why we need a fallback
			# rpardini: yeah but this is 404'ing
			#ROOTFSCACHE_VERSION=${ROOTFSCACHE_VERSION:-$(curl -L --silent https://cache.armbian.com/rootfs/latest --fail)}
			display_alert "Remotely-obtained ROOTFSCACHE_VERSION" "${ROOTFSCACHE_VERSION}" "debug"
		else
			ROOTFSCACHE_VERSION=668 # The neighbour of the beast.
		fi
	fi

	local packages_hash="${AGGREGATED_ROOTFS_HASH}" # Produced by aggregation.py
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
			if [[ "${SKIP_ARMBIAN_REPO}" != "yes" ]]; then
				display_alert "Downloading from servers"
				download_and_verify "rootfs" "$cache_name" ||
					continue
			fi
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
	if [[ "${MANAGE_ACNG}" == "yes" ]]; then
		local debootstrap_apt_mirror="http://localhost:3142/${APT_MIRROR}"
		acng_check_status_or_restart
	fi

	# @TODO: one day: https://gitlab.mister-muffin.de/josch/mmdebstrap/src/branch/main/mmdebstrap

	display_alert "Installing base system" "Stage 1/2" "info"
	cd "${SDCARD}" || exit_with_error "cray-cray about SDCARD" "${SDCARD}" # this will prevent error sh: 0: getcwd() failed

	local -a deboostrap_arguments=(
		"--variant=minbase"                                         # minimal base variant. go ask Debian about it.
		"--arch=${ARCH}"                                            # the arch
		"'--include=${AGGREGATED_PACKAGES_DEBOOTSTRAP_COMMA}'"      # from aggregation.py
		"'--components=${AGGREGATED_DEBOOTSTRAP_COMPONENTS_COMMA}'" # from aggregation?
	)

	# Small detour for local apt caching option.
	local use_local_apt_cache apt_cache_host_dir
	local_apt_deb_cache_prepare use_local_apt_cache apt_cache_host_dir "before debootstrap" # 2 namerefs + "when"
	if [[ "${use_local_apt_cache}" == "yes" ]]; then
		# Small difference for debootstrap, if compared to apt: we need to pass it the "/archives" subpath to share cache with apt.
		deboostrap_arguments+=("--cache-dir=${apt_cache_host_dir}/archives") # cache .deb's used
	fi

	# This always last, positional arguments.
	deboostrap_arguments+=("--foreign" "${RELEASE}" "${SDCARD}/" "${debootstrap_apt_mirror}") # path and mirror

	run_host_command_logged debootstrap "${deboostrap_arguments[@]}" || {
		exit_with_error "Debootstrap first stage failed" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	}
	[[ ! -f ${SDCARD}/debootstrap/debootstrap ]] && exit_with_error "Debootstrap first stage did not produce marker file"

	local_apt_deb_cache_prepare use_local_apt_cache apt_cache_host_dir "after debootstrap" # 2 namerefs + "when"

	deploy_qemu_binary_to_chroot "${SDCARD}" # this is cleaned-up later by post_debootstrap_tweaks()

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

	# stage: configure language and locales.
	# this _requires_ DEST_LANG, otherwise, bomb: if it's not here _all_ locales will be generated which is very slow.
	display_alert "Configuring locales" "DEST_LANG: ${DEST_LANG}" "info"
	[[ "x${DEST_LANG}x" == "xx" ]] && exit_with_error "Bug: got to config locales without DEST_LANG set"

	[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# ${DEST_LANG}/${DEST_LANG}/" $SDCARD/etc/locale.gen
	chroot_sdcard LC_ALL=C LANG=C locale-gen "${DEST_LANG}"
	chroot_sdcard LC_ALL=C LANG=C update-locale "LANG=${DEST_LANG}" "LANGUAGE=${DEST_LANG}" "LC_MESSAGES=${DEST_LANG}"

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

	# @TODO: use asset logging for this; actually log contents of the files too
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
	# AGGREGATED_PACKAGES_ROOTFS is generated by aggregation.py
	chroot_sdcard_apt_get_install_dry_run "${AGGREGATED_PACKAGES_ROOTFS[@]}"
	do_with_retries 3 chroot_sdcard_apt_get_install_download_only "${AGGREGATED_PACKAGES_ROOTFS[@]}"

	# Now do the install, all packages should have been downloaded by now
	chroot_sdcard_apt_get_install "${AGGREGATED_PACKAGES_ROOTFS[@]}"

	if [[ $BUILD_DESKTOP == "yes" ]]; then
		## This is not defined anywhere.... @TODO: remove?
		#local apt_desktop_install_flags=""
		#if [[ ! -z ${DESKTOP_APT_FLAGS_SELECTED+x} ]]; then
		#	for flag in ${DESKTOP_APT_FLAGS_SELECTED}; do
		#		apt_desktop_install_flags+=" --install-${flag}"
		#	done
		#else
		#	# Myy : Using the previous default option, if the variable isn't defined
		#	# And ONLY if it's not defined !
		#	apt_desktop_install_flags+=" --no-install-recommends"
		#fi

		display_alert "Installing the desktop packages for" "Armbian" "info"

		# dry-run, make sure everything can be installed.
		chroot_sdcard_apt_get_install_dry_run "${AGGREGATED_PACKAGES_DESKTOP[@]}"

		# Retry download-only 3 times first.
		do_with_retries 3 chroot_sdcard_apt_get_install_download_only "${AGGREGATED_PACKAGES_DESKTOP[@]}"

		# Then do the actual install.
		export if_error_detail_message="Installation of Armbian desktop packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
		chroot_sdcard_apt_get install "${AGGREGATED_PACKAGES_DESKTOP[@]}"
	fi

	# stage: check md5 sum of installed packages. Just in case.
	display_alert "Checking MD5 sum of installed packages" "debsums" "info"
	export if_error_detail_message="Check MD5 sum of installed packages failed"
	chroot_sdcard debsums --silent

	# Remove packages from packages.uninstall
	# @TODO: aggregation.py handling of this...
	display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
	# shellcheck disable=SC2086
	chroot_sdcard_apt_get purge $PACKAGE_LIST_UNINSTALL

	# @TODO: if we remove with --purge then this is not needed
	# stage: purge residual packages
	display_alert "Purging residual packages for" "Armbian" "info"
	PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
	chroot_sdcard_apt_get remove --purge $PURGINGPACKAGES

	# stage: remove packages that are installed, but not required anymore after other packages were installed/removed.
	# don't touch the local cache.
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get autoremove

	# Only clean if not using local cache. Otherwise it would be cleaning the cache, not the chroot.
	if [[ "${USE_LOCAL_APT_DEB_CACHE}" != "yes" ]]; then
		display_alert "Late Cleaning" "late: package lists and apt cache" "warn"
		chroot_sdcard_apt_get clean
	fi

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	display_alert "Free SD cache" "$(echo -e "$freespace" | awk -v mp="${SDCARD}" '$6==mp {print $5}')" "info"
	[[ -d "${MOUNT}" ]] &&
		display_alert "Mount point" "$(echo -e "$freespace" | awk -v mp="${MOUNT}" '$6==mp {print $5}')" "info"

	# create list of installed packages for debug purposes - this captures it's own stdout.
	chroot_sdcard "dpkg -l | grep ^ii | awk '{ print \$2\",\"\$3 }'" > "${cache_fname}.list"

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
	chroot_sdcard systemctl mask systemd-firstboot.service

	# stage: make rootfs cache archive
	display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
	sync
	# the only reason to unmount here is compression progress display
	# based on rootfs size calculation
	umount_chroot "$SDCARD"

	display_alert "zstd ball of rootfs" "$RELEASE:: $cache_name" "debug"
	tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
		--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s "$(du -sb $SDCARD/ | cut -f1)" -N "$(logging_echo_prefix_for_pv "store_rootfs") $cache_name" | zstdmt -5 -c > "${cache_fname}"

	# sign rootfs cache archive that it can be used for web cache once. Internal purposes
	if [[ -n "${GPG_PASS}" && "${SUDO_USER}" ]]; then
		[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/
		echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
	fi

	# needed for backend to keep current only
	echo "$cache_fname" > $cache_fname.current

	display_alert "Cache prepared" "$RELEASE:: $cache_fname" "debug"

	return 0 # protect against possible future short-circuiting above this
}

# get_rootfs_cache_list <cache_type> <packages_hash>
#
# return a list of versions of all avaiable cache from remote and local.
get_rootfs_cache_list() {
	local cache_type=$1
	local packages_hash=$2

	# this uses `jq` hostdep
	{
		curl --silent --fail -L "https://api.github.com/repos/armbian/cache/releases?per_page=3" | jq -r '.[].tag_name' ||
			curl --silent --fail -L https://cache.armbian.com/rootfs/list

		find ${SRC}/cache/rootfs/ -mtime -7 -name "${ARCH}-${RELEASE}-${cache_type}-${packages_hash}-*.tar.zst" |
			sed -e 's#^.*/##' |
			sed -e 's#\..*$##' |
			awk -F'-' '{print $5}'
	} | sort | uniq
}
