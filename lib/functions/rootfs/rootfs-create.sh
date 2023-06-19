#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function create_new_rootfs_cache_tarball() {
	# validate cache_fname is set
	[[ -n "${cache_fname}" ]] || exit_with_error "create_new_rootfs_cache_tarball: cache_fname is not set"
	# validate SDCARD is set
	[[ -n "${SDCARD}" ]] || exit_with_error "create_new_rootfs_cache_tarball: SDCARD is not set"
	# validate cache_name is set
	[[ -n "${cache_name}" ]] || exit_with_error "create_new_rootfs_cache_tarball: cache_name is not set"

	# create list of installed packages for debug purposes - this captures it's own stdout.
	# @TODO: sanity check, compare this with the source of the hash coming from aggregation
	chroot_sdcard "dpkg -l | grep ^ii | awk '{ print \$2\",\"\$3 }'" > "${cache_fname}.list"
	echo "${AGGREGATED_ROOTFS_HASH_TEXT}" > "${cache_fname}.hash_text"

	# Show the disk space usage of the rootfs
	display_alert "Disk space usage of rootfs" "${RELEASE}:: ${cache_name}" "info"
	run_host_command_logged "cd ${SDCARD} && " du -h -d 4 -x "." "| sort -h | tail -20"
	wait_for_disk_sync "after disk-space usage report of rootfs"

	declare compression_ratio_rootfs="${ROOTFS_COMPRESSION_RATIO:-"5"}"

	display_alert "zstd tarball of rootfs" "${RELEASE}:: ${cache_name} :: compression ${compression_ratio_rootfs}" "info"
	tar cp --xattrs --directory="$SDCARD"/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' \
		--exclude='./tmp/*' --exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . |
		pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" -N "$(logging_echo_prefix_for_pv "store_rootfs") $cache_name" |
		zstdmt "-${compression_ratio_rootfs}" -c > "${cache_fname}"

	declare -a pv_tar_zstdmt_pipe_status=("${PIPESTATUS[@]}") # capture and the pipe_status array from PIPESTATUS
	declare one_pipe_status
	for one_pipe_status in "${pv_tar_zstdmt_pipe_status[@]}"; do
		if [[ "$one_pipe_status" != "0" ]]; then
			exit_with_error "create_new_rootfs_cache_tarball: compress: ${cache_fname} failed (${pv_tar_zstdmt_pipe_status[*]}) - out of disk space?"
		fi
	done

	wait_for_disk_sync "after zstd tarball rootfs"

	# get the human readable size of the cache
	local cache_size
	cache_size=$(du -sh "${cache_fname}" | cut -f1)

	display_alert "rootfs cache created" "${cache_fname} [${cache_size}]" "info"
}

function create_new_rootfs_cache_via_debootstrap() {
	[[ ! -d "${SDCARD:?}" ]] && exit_with_error "create_new_rootfs_cache_via_debootstrap: ${SDCARD} is not a directory"

	# this is different between debootstrap and regular apt-get; here we use acng as a prefix to the real repo
	declare debootstrap_apt_mirror="http://${APT_MIRROR}"
	if [[ "${MANAGE_ACNG}" == "yes" ]]; then
		local debootstrap_apt_mirror="http://localhost:3142/${APT_MIRROR}"
		acng_check_status_or_restart
	fi

	# @TODO: one day: https://gitlab.mister-muffin.de/josch/mmdebstrap/src/branch/main/mmdebstrap

	display_alert "Installing base system with ${#AGGREGATED_PACKAGES_DEBOOTSTRAP[@]} packages" "Stage 1/2" "info"
	cd "${SDCARD}" || exit_with_error "cray-cray about SDCARD" "${SDCARD}" # this will prevent error sh: 0: getcwd() failed

	declare -a deboostrap_arguments=(
		"--variant=minbase"                                         # minimal base variant. go ask Debian about it.
		"--arch=${ARCH}"                                            # the arch
		"'--include=${AGGREGATED_PACKAGES_DEBOOTSTRAP_COMMA}'"      # from aggregation.py
		"'--components=${AGGREGATED_DEBOOTSTRAP_COMPONENTS_COMMA}'" # from aggregation.py
	)

	# Small detour for local apt caching option.
	local_apt_deb_cache_prepare "before debootstrap" # sets LOCAL_APT_CACHE_INFO
	if [[ "${LOCAL_APT_CACHE_INFO[USE]}" == "yes" ]]; then
		deboostrap_arguments+=("--cache-dir=${LOCAL_APT_CACHE_INFO[HOST_DEBOOTSTRAP_CACHE_DIR]}") # cache .deb's used
	fi

	deboostrap_arguments+=("--foreign") # release name

	# Debian does not carry riscv64 in their main repo, needs ports, which needs a specific keyring in the host.
	# that's done in prepare-host.sh when by adding debian-ports-archive-keyring hostdep, but there's an if anyway.
	# debian-ports-archive-keyring is also included in-image by: config/optional/architectures/riscv64/_config/cli/_all_distributions/main/packages
	# Revise this after bookworm release.
	# @TODO: rpardini: this clearly shows a need for hooks for debootstrap
	if [[ "${ARCH}" == "riscv64" ]] && [[ $DISTRIBUTION == Debian ]]; then
		if [[ -f /usr/share/keyrings/debian-ports-archive-keyring.gpg ]]; then
			display_alert "Adding ports keyring for Debian debootstrap" "riscv64" "info"
			deboostrap_arguments+=("--keyring" "/usr/share/keyrings/debian-ports-archive-keyring.gpg")
		else
			exit_with_error "Debian debootstrap for riscv64 needs debian-ports-archive-keyring hostdep"
		fi
	fi

	deboostrap_arguments+=("${RELEASE}" "${SDCARD}/" "${debootstrap_apt_mirror}") # release, path and mirror; always last, positional arguments.

	run_host_command_logged debootstrap "${deboostrap_arguments[@]}" || {
		exit_with_error "Debootstrap first stage failed" "${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	}
	[[ ! -f ${SDCARD}/debootstrap/debootstrap ]] && exit_with_error "Debootstrap first stage did not produce marker file"

	skip_target_check="yes" local_apt_deb_cache_prepare "after debootstrap first stage" # just for size reference in logs; skip the target check: debootstrap uses it for second stage.

	deploy_qemu_binary_to_chroot "${SDCARD}" # this is cleaned-up later by post_debootstrap_tweaks() @TODO: which is too late for a cache

	display_alert "Installing base system" "Stage 2/2" "info"
	declare -g if_error_detail_message="Debootstrap second stage failed ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}"
	chroot_sdcard LC_ALL=C LANG=C /debootstrap/debootstrap --second-stage
	[[ ! -f "${SDCARD}/bin/bash" ]] && exit_with_error "Debootstrap first stage did not produce /bin/bash"

	# Done with debootstrap. Clean-up it's litterbox.
	display_alert "Cleaning up after debootstrap" "debootstrap cleanup" "info"
	run_host_command_logged rm -rf "${SDCARD}/var/cache/apt" "${SDCARD}/var/lib/apt/lists"

	local_apt_deb_cache_prepare "after debootstrap second stage" # just for size reference in logs

	mount_chroot "${SDCARD}" # we mount the chroot here... it's un-mounted below when all is done, or by cleanup handler '' @TODO

	display_alert "Diverting" "initctl/start-stop-daemon" "info"
	# policy-rc.d script prevents starting or reloading services during image creation
	printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
	chroot_sdcard LC_ALL=C LANG=C dpkg-divert --quiet --local --rename --add /sbin/initctl
	chroot_sdcard LC_ALL=C LANG=C dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon
	printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > "$SDCARD/sbin/start-stop-daemon"
	printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > "$SDCARD/sbin/initctl"
	chmod 755 "${SDCARD}/usr/sbin/policy-rc.d"
	chmod 755 "${SDCARD}/sbin/initctl"
	chmod 755 "${SDCARD}/sbin/start-stop-daemon"

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

	# stage: create apt-get sources list (basic Debian/Ubuntu apt sources, no external nor PPAS).
	# for the Armbian repo, only the components which are _not_ produced by armbian/build are included (-desktop and -utils)
	create_sources_list_and_deploy_repo_key "root" "$RELEASE" "$SDCARD/"

	# optionally add armhf arhitecture to arm64, if asked to do so.
	if [[ "a${ARMHF_ARCH}" == "ayes" ]]; then
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
	do_with_retries 3 chroot_sdcard_apt_get_update

	# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
	display_alert "Upgrading base packages" "Armbian" "info"
	do_with_retries 3 chroot_sdcard_apt_get upgrade

	# stage: install additional packages
	display_alert "Installing the main packages for" "Armbian" "info"
	declare -g if_error_detail_message="Installation of Armbian main packages for ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
	# First, try to download-only up to 3 times, to work around network/proxy problems.
	# AGGREGATED_PACKAGES_ROOTFS is generated by aggregation.py
	chroot_sdcard_apt_get_install_dry_run "${AGGREGATED_PACKAGES_ROOTFS[@]}"
	do_with_retries 3 chroot_sdcard_apt_get_install_download_only "${AGGREGATED_PACKAGES_ROOTFS[@]}"

	# Now do the install, all packages should have been downloaded by now
	chroot_sdcard_apt_get_install "${AGGREGATED_PACKAGES_ROOTFS[@]}"

	if [[ $BUILD_DESKTOP == "yes" ]]; then
		# how how many items in AGGREGATED_PACKAGES_DESKTOP array
		display_alert "Installing ${#AGGREGATED_PACKAGES_DESKTOP[@]} desktop packages" "${RELEASE} ${DESKTOP_ENVIRONMENT}" "info"

		# dry-run, make sure everything can be installed.
		chroot_sdcard_apt_get_install_dry_run "${AGGREGATED_PACKAGES_DESKTOP[@]}"

		# Retry download-only 3 times first.
		do_with_retries 3 chroot_sdcard_apt_get_install_download_only "${AGGREGATED_PACKAGES_DESKTOP[@]}"

		# Then do the actual install.
		declare -g if_error_detail_message="Installation of Armbian desktop packages for ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
		chroot_sdcard_apt_get_install "${AGGREGATED_PACKAGES_DESKTOP[@]}"
	fi

	# stage: check md5 sum of installed packages. Just in case. @TODO: rpardini: this should also be done when a cache is used, not only when it is created
	display_alert "Checking MD5 sum of installed packages" "debsums" "info"
	declare -g if_error_detail_message="Check MD5 sum of installed packages failed"
	chroot_sdcard debsums --silent

	# # Remove packages from packages.uninstall
	# # @TODO: aggregation.py handling of this... if we wanted it removed in rootfs cache, why did we install it in the first place?
	# display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
	# # shellcheck disable=SC2086
	# DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get purge $PACKAGE_LIST_UNINSTALL

	# # if we remove with --purge then this is not needed
	# # stage: purge residual packages
	# display_alert "Purging residual packages for" "Armbian" "info"
	# PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
	# DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get purge $PURGINGPACKAGES

	# stage: remove packages that are installed, but not required anymore after other packages were installed/removed.
	# don't touch the local cache.
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get autoremove

	# Purge/clean apt cache in the target. It should _not_ have been used, but if it was, warn & clean.
	apt_purge_unneeded_packages_and_clean_apt_caches

	# DEBUG: print free space
	local free_space
	free_space=$(LC_ALL=C df -h)
	display_alert "Free disk space on rootfs" "SDCARD: $(echo -e "${free_space}" | awk -v mp="${SDCARD}" '$6==mp {print $5}')" "info"

	# this is needed for the build process later since resolvconf generated file in /run is not saved
	run_host_command_logged rm -v "${SDCARD}"/etc/resolv.conf
	run_host_command_logged echo "nameserver $NAMESERVER" ">" "${SDCARD}"/etc/resolv.conf

	# Remove `machine-id` (https://www.freedesktop.org/software/systemd/man/machine-id.html)
	# Note: This will mark machine `firstboot`
	run_host_command_logged echo "uninitialized" ">" "${SDCARD}/etc/machine-id"
	run_host_command_logged rm -v "${SDCARD}/var/lib/dbus/machine-id"

	# Mask `systemd-firstboot.service` which will prompt locale, timezone and root-password too early.
	# `armbian-first-run` will do the same thing later
	chroot_sdcard systemctl mask systemd-firstboot.service

	# stage: make rootfs cache archive
	display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
	wait_for_disk_sync "before tar rootfs"

	# we're done with using the chroot which we mounted above.
	# if something failed, the cleanup handler (via trap manager) will take care of it.
	umount_chroot "${SDCARD}"

	wait_for_disk_sync "after unmounting chroot used for rootfs build"

	return 0
}
