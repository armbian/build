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

# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot() {

	local target=$1
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts

}

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot() {

	local target=$1
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts; do
		umount -l --recursive "${target}"/dev > /dev/null 2>&1
		umount -l "${target}"/proc > /dev/null 2>&1
		umount -l "${target}"/sys > /dev/null 2>&1
		sleep 5
	done

}

# unmount_on_exit
#
unmount_on_exit() {
	trap - INT TERM EXIT # remove the trap
	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		ERROR_DEBUG_SHELL=no # dont do it twice
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL" "err"
		bash < /dev/tty || true
	fi

	umount_chroot "${SDCARD}/"
	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs
	umount -l "${SDCARD}"/tmp > /dev/null 2>&1
	umount -l "${SDCARD}" > /dev/null 2>&1
	umount -l "${MOUNT}"/boot > /dev/null 2>&1
	umount -l "${MOUNT}" > /dev/null 2>&1
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}"
	losetup -d "${LOOP}" > /dev/null 2>&1
	rm -rf --one-file-system "${SDCARD}"

	# if we've been called by exit_with_error itself, don't recurse. it makes no sense.
	if [[ "${ALREADY_EXITING_WITH_ERROR:-no}" != "yes" ]]; then
		exit_with_error "generic error during build_rootfs_image: ${stacktrace}" || true # but don't trigger error again
	fi

	return 0 # exit successfully. we're already handling a trap here.
}

# check_loop_device <device_node>
#
check_loop_device() {

	local device=$1
	#display_alert "Checking look device" "${device}" "wrn"
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi

}

# write_uboot <loopdev>
#
write_uboot() {

	local loop=$1 revision
	display_alert "Writing U-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d || exit 1)
	chmod 700 ${TEMP_DIR}
	revision=${REVISION}
	if [[ -n $UPSTREM_VER ]]; then
		revision=${UPSTREM_VER}
		dpkg -x "${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	else
		dpkg -x "${DEB_STORAGE}/${CHOSEN_UBOOT}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	fi

	# source platform install to read $DIR
	source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh
	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -rf ${TEMP_DIR}

}

# copy_all_packages_files_for <folder> to package
#
copy_all_packages_files_for() {
	local package_name="${1}"
	for package_src_dir in ${PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS}; do
		local package_dirpath="${package_src_dir}/${package_name}"
		if [ -d "${package_dirpath}" ]; then
			cp -r "${package_dirpath}/"* "${destination}/" 2> /dev/null
			display_alert "Adding files from" "${package_dirpath}"
		fi
	done
}

customize_image() {

	# for users that need to prepare files at host
	[[ -f $USERPATCHES_PATH/customize-image-host.sh ]] && source "$USERPATCHES_PATH"/customize-image-host.sh

	call_extension_method "pre_customize_image" "image_tweaks_pre_customize" << 'PRE_CUSTOMIZE_IMAGE'
*run before customize-image.sh*
This hook is called after `customize-image-host.sh` is called, but before the overlay is mounted.
It thus can be used for the same purposes as `customize-image-host.sh`.
PRE_CUSTOMIZE_IMAGE

	cp "$USERPATCHES_PATH"/customize-image.sh "${SDCARD}"/tmp/customize-image.sh
	chmod +x "${SDCARD}"/tmp/customize-image.sh
	mkdir -p "${SDCARD}"/tmp/overlay
	# util-linux >= 2.27 required
	mount -o bind,ro "$USERPATCHES_PATH"/overlay "${SDCARD}"/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot "${SDCARD}" /bin/bash -c "/tmp/customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP $ARCH"
	CUSTOMIZE_IMAGE_RC=$?
	umount -i "${SDCARD}"/tmp/overlay > /dev/null 2>&1
	mountpoint -q "${SDCARD}"/tmp/overlay || rm -r "${SDCARD}"/tmp/overlay
	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "customize-image.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi

	call_extension_method "post_customize_image" "image_tweaks_post_customize" << 'POST_CUSTOMIZE_IMAGE'
*post customize-image.sh hook*
Run after the customize-image.sh script is run, and the overlay is unmounted.
POST_CUSTOMIZE_IMAGE

	return 0
}

# shortcut
function chroot_sdcard_apt_get_install() {
	chroot_sdcard_apt_get --no-install-recommends install "$@"
}

function chroot_sdcard_apt_get() {
	local -a apt_params=("-${APT_OPTS:-yqq}")
	[[ $NO_APT_CACHER != yes ]] && apt_params+=(
		-o "Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
		-o "Acquire::http::Proxy::localhost=\"DIRECT\""
		-o "Dpkg::Use-Pty=0" # Please be quiet
	)
	# IMPORTANT: this function returns the exit code of last statement, in this case chroot (which gets its result from bash which calls apt-get)
	chroot_sdcard DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@"
}

# please, please, unify around this function. if SDCARD is not enough, I'll make a mount version.
function chroot_sdcard() {
	# Log the command to the current logfile, so it has context of what was run.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "(=-Armbian-->" chroot "\${SDCARD}" /bin/bash -e -c "$*" " <- at $(date --utc)" >> "${CURRENT_LOGFILE}" # SDCARD's $ is escaped on purpose here.
	fi
	local exit_code=666
	chroot "${SDCARD}" /bin/bash -e -c "$*" 2>&1 # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "(=-Armbian--> cmd exited with code ${exit_code} at $(date --utc)" >> "${CURRENT_LOGFILE}" # SDCARD's $ is escaped on purpose here.
	fi
	return $exit_code
}

# this is called by distributions.sh->install_common(), and thus already under a logging manager.
install_deb_chroot() {
	local package=$1
	local variant=$2
	local transfer=$3
	local name
	local desc
	if [[ ${variant} != remote ]]; then
		# @TODO: this can be sped up significantly by mounting debs readonly directly in chroot /root/debs and installing from there
		# also won't require cleanup later
		name="/root/"$(basename "${package}")
		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"
		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	# @TODO: this is mostly duplicated in distributions.sh->install_common(), refactor into "chroot_apt_get()"
	display_alert "Installing${desc}" "${name/\/root\//}"
	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	# when building in bulk from remote, lets make sure we have up2date index
	[[ $BUILD_ALL == yes && ${variant} == remote ]] && chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get $apt_extra -yqq update"

	# install in chroot via apt-get, not dpkg, so dependencies are also installed from repo if needed.
	chroot_sdcard_apt_get --no-install-recommends install "${name}" || {
		exit_with_error "Installation of $name failed" "${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	}

	# @TODO: mysterious. store installed/downloaded packages in deb storage. only used for u-boot deb. why?
	[[ ${variant} == remote && ${transfer} == yes ]] && rsync -rq "${SDCARD}"/var/cache/apt/archives/*.deb ${DEB_STORAGE}/

	# IMPORTANT! Do not use conditional above as last statement in a function, since it determines the result of the function.
	return 0
}

# @TODO: logging: used by desktop.sh exclusively. let's unify?
run_on_sdcard() {
	# Lack of quotes allows for redirections and pipes easily.
	chroot "${SDCARD}" /bin/bash -c "${@}" >> "${DEST}/${LOG_SUBPATH}/install.log"
}
