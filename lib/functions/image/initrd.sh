#!/usr/bin/env bash
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
update_initramfs() {
	local chroot_target=$1
	local target_dir="$(find "${chroot_target}/lib/modules"/ -maxdepth 1 -type d -name "*${VER}*")" # @TODO: rpardini: this will break when we add multi-kernel images
	local initrd_kern_ver initrd_file initrd_cache_key initrd_cache_file_path initrd_hash
	local initrd_cache_current_manifest_filepath initrd_cache_last_manifest_filepath
	if [ "$target_dir" != "" ]; then
		initrd_kern_ver="$(basename "$target_dir")"
		initrd_file="${chroot_target}/boot/initrd.img-${initrd_kern_ver}"

		update_initramfs_cmd="TMPDIR=/tmp update-initramfs -uv -k ${initrd_kern_ver}" # @TODO: why? TMPDIR=/tmp
	else
		exit_with_error "No kernel installed for the version" "${VER}"
	fi

	# Caching.
	# Find all modules and all firmware in the target.
	# Find all initramfs configuration in /etc
	# Find all bash, cpio and gzip binaries in /bin
	# Hash the contents of them all.
	# If there's a match, use the cache.

	display_alert "computing initrd cache hash" "${chroot_target}" "debug"
	mkdir -p "${SRC}/cache/initrd"
	initrd_cache_current_manifest_filepath="${WORKDIR}/initrd.img-${initrd_kern_ver}.${ARMBIAN_BUILD_UUID}.manifest"
	initrd_cache_last_manifest_filepath="${SRC}/cache/initrd/initrd.manifest-${initrd_kern_ver}.last.manifest"

	# Find all the affected files; parallel md5sum sum them; invert hash and path, and remove chroot prefix.
	find "${target_dir}" "${chroot_target}/usr/bin/bash" "${chroot_target}/etc/initramfs" \
		"${chroot_target}/etc/initramfs-tools" -type f | parallel -X md5sum |
		awk '{print $2 " - " $1}' |
		sed -e "s|^${chroot_target}||g" | LC_ALL=C sort > "${initrd_cache_current_manifest_filepath}"

	initrd_hash="$(cat "${initrd_cache_current_manifest_filepath}" | md5sum | cut -d ' ' -f 1)" # hash of the hashes.
	initrd_cache_key="initrd.img-${initrd_kern_ver}-${initrd_hash}"
	initrd_cache_file_path="${SRC}/cache/initrd/${initrd_cache_key}"
	display_alert "initrd cache hash" "${initrd_hash}" "debug"

	display_alert "Mounting chroot for update-initramfs" "update-initramfs" "debug"
	deploy_qemu_binary_to_chroot "${chroot_target}"

	mount_chroot "$chroot_target/"

	if [[ -f "${initrd_cache_file_path}" ]]; then
		display_alert "initrd cache hit" "${initrd_cache_key}" "cachehit"
		run_host_command_logged cp -pv "${initrd_cache_file_path}" "${initrd_file}"
		touch "${initrd_cache_file_path}" # touch cached file timestamp; LRU bump.
		if [[ -f "${initrd_cache_last_manifest_filepath}" ]]; then
			touch "${initrd_cache_last_manifest_filepath}" # touch the manifest file timestamp; LRU bump.
		fi

		# Convert to bootscript expected format, by calling into the script manually.
		if [[ -f "${chroot_target}"/etc/initramfs/post-update.d/99-uboot ]]; then
			chroot_custom "$chroot_target" /etc/initramfs/post-update.d/99-uboot "${initrd_kern_ver}" "/boot/initrd.img-${initrd_kern_ver}"
		fi
	else
		display_alert "Cache miss for initrd cache" "${initrd_cache_key}" "debug"

		# Show the differences between the last and the current, so we realize why it isn't hit (eg; what changed).
		if [[ -f "${initrd_cache_last_manifest_filepath}" ]]; then
			if [[ "${SHOW_DEBUG}" == "yes" ]]; then
				display_alert "Showing diff between last and current initrd cache manifests" "initrd" "debug"
				run_host_command_logged diff -u --color=always "${initrd_cache_last_manifest_filepath}" "${initrd_cache_current_manifest_filepath}" "|| true" # no errors please
			fi
		fi

		display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
		local logging_filter="2>&1 | grep --line-buffered -v -e '.xz' -e 'ORDER ignored' -e 'Adding binary ' -e 'Adding module ' -e 'Adding firmware ' "
		chroot_custom_long_running "$chroot_target" "$update_initramfs_cmd" "${logging_filter}"
		display_alert "Updated initramfs." "${update_initramfs_cmd}" "info"

		display_alert "Storing initrd in cache" "${initrd_cache_key}" "debug"                                              # notice there's no -p here: no need to touch LRU
		run_host_command_logged cp -v "${initrd_file}" "${initrd_cache_file_path}"                                         # store the new initrd in the cache.
		run_host_command_logged cp -v "${initrd_cache_current_manifest_filepath}" "${initrd_cache_last_manifest_filepath}" # store the current contents in the last file.

		# clean old cache files so they don't pile up forever.
		if [[ "${SHOW_DEBUG}" == "yes" ]]; then
			display_alert "Showing which initrd caches would be removed/expired" "initrd" "debug"
			# 60: keep the last 30 initrd + manifest pairs. this should be higher than the total number of kernels we support, otherwise churn will be high
			find "${SRC}/cache/initrd" -type f -printf "%T@ %p\\n" | sort -n -r | sed "1,60d" | xargs rm -fv
		fi
	fi

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot_custom "$chroot_target" chmod -v +x /etc/kernel/postinst.d/initramfs-tools

	display_alert "Unmounting chroot" "update-initramfs" "debug"
	umount_chroot "${chroot_target}/"
	undeploy_qemu_binary_from_chroot "${chroot_target}"

	# no need to remove ${initrd_cache_current_manifest_filepath} manually, since it's under ${WORKDIR}
	return 0 # avoid future short-circuit problems
}
