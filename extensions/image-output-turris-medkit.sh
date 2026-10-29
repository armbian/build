# @description Builds a medkit for the Turris Omnia: `omnia-medkit-${version}.tar.gz` and its `.sha256` in the output folder. The Turris rescue system installs the medkit from a USB flash drive to the eMMC (reset with 4 LEDs). Only for `BOARD=turris-omnia`.

#
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# The rescue system unpacks the medkit to the btrfs subvolume @ on mmcblk0p1.
# It takes the medkit with the greatest name, so keep one on the flash drive.

function extension_prepare_config__prepare_turris_medkit() {
	[[ "${BOARD}" == "turris-omnia" ]] || exit_with_error "${EXTENSION} only supports the Turris Omnia" "${BOARD}"
	[[ "${CRYPTROOT_ENABLE:-no}" != "yes" ]] || exit_with_error "${EXTENSION} does not support an encrypted root" "CRYPTROOT_ENABLE=yes"
	# An NFS image has no root file system and another boot script
	[[ "${ROOTFS_TYPE}" != "nfs" ]] || exit_with_error "${EXTENSION} does not support an NFS root" "ROOTFS_TYPE=nfs"
	add_packages_to_image btrfs-progs
	return 0
}

# The medkit root is btrfs, but the image root may not be. List the module, so
# the initramfs has it with MODULES=dep too.
function pre_update_initramfs__turris_medkit_btrfs_module() {
	echo "btrfs" >> "${MOUNT}/etc/initramfs-tools/modules"
}

function pre_umount_final_image__900_build_turris_medkit() {
	[[ -z $version ]] && exit_with_error "version is not set"

	# Not ${DESTIMG}/${version}.*, the build would compress it again. The build
	# removes ${DESTIMG} on failure.
	declare medkit="omnia-medkit-${version}.tar.gz" staging tarball
	staging="$(mktemp -d -p "${DESTIMG}" "turris-medkit.XXXXXX")"
	tarball="${staging}/${medkit}"
	display_alert "Building Turris medkit" "${medkit}" "info"

	# The rescue system makes the file system, so the root is mmcblk0p1. No
	# compress option, the stock U-Boot cannot read zstd files. noatime keeps
	# metadata shared with the @factory snapshot.
	awk '$2 == "/" { print "/dev/mmcblk0p1 / btrfs defaults,noatime,commit=120,subvol=@ 0 0"; next } $1 ~ /^UUID=/ { next } { print }' "${MOUNT}/etc/fstab" > "${staging}/fstab"
	[[ "$(grep -c '^/dev/mmcblk0p1 / ' "${staging}/fstab")" == 1 ]] || exit_with_error "${MOUNT}/etc/fstab must have one root file system" "$(< "${MOUNT}/etc/fstab")"
	sed -e '/^rootdev=/d' -e '/^rootfstype=/d' "${MOUNT}/boot/armbianEnv.txt" > "${staging}/armbianEnv.txt"
	chmod --reference="${MOUNT}/etc/fstab" "${staging}/fstab"
	chmod --reference="${MOUNT}/boot/armbianEnv.txt" "${staging}/armbianEnv.txt"

	# GNU tar format like the official medkits. The exclusions also match the new
	# files, so they get other names here and --transform puts them in place. The
	# archive has no file capabilities, so fping, the only file with one, needs root.
	declare -a cmd
	cmd=(tar --create --file=- --format=gnu --numeric-owner --anchored
		--exclude=./lost+found --exclude=./boot/lost+found --exclude=./etc/fstab --exclude=./boot/armbianEnv.txt
		--exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./sys/*' --exclude='./tmp/*'
		--transform='s,^fstab$,./etc/fstab,S' --transform='s,^armbianEnv\.txt$,./boot/armbianEnv.txt,S'
		--directory="${MOUNT}" . --directory="${staging}" fstab armbianEnv.txt)
	run_host_command_logged "${cmd[*]@Q}" "|" pigz ">" "${tarball@Q}"
	(set -o pipefail && tar -xzOf "${tarball}" ./etc/fstab ./boot/armbianEnv.txt | cmp -s - <(cat "${staging}/fstab" "${staging}/armbianEnv.txt")) ||
		exit_with_error "The medkit does not have the new fstab and armbianEnv.txt" "${medkit}"
	# The rescue systems compare this line with sha256sum or run sha256sum -c
	(cd "${staging}" && sha256sum "${medkit}" > "${medkit}.sha256" && sha256sum --quiet -c "${medkit}.sha256")

	# rsync renames each file when it is complete, so no partial medkit appears
	mkdir -p "${FINALDEST}"
	cmd=(rsync -av --no-owner --no-group --remove-source-files "${tarball}" "${tarball}.sha256" "${FINALDEST}/")
	run_host_command_logged "${cmd[*]@Q}"
	rm -rf "${staging}"
	display_alert "Built Turris medkit" "${FINALDEST}/${medkit}" "info"
}
