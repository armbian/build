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
		umount --recursive "${target}"/dev > /dev/null 2>&1 || true
		umount "${target}"/proc > /dev/null 2>&1 || true
		umount "${target}"/sys > /dev/null 2>&1 || true
		sync
	done
}

# demented recursive version, for final umount.
umount_chroot_recursive() {
	set +e # really, ignore errors. we wanna unmount everything and will try very hard.
	local target="$1"

	if [[ ! -d "${target}" ]]; then # only even try if target is a directory
		return 0                       # success, nothing to do.
	fi
	display_alert "Unmounting recursively" "$target" ""
	sync # sync. coalesce I/O. wait for writes to flush to disk. it might take a second.
	# First, try to umount some well-known dirs, in a certain order. for speed.
	local -a well_known_list=("dev/pts" "dev" "proc" "sys" "boot/efi" "boot/firmware" "boot" "tmp" ".")
	for well_known in "${well_known_list[@]}"; do
		umount --recursive "${target}${well_known}" &> /dev/null && sync
	done

	# now try in a loop to unmount all that's still mounted under the target
	local -i tries=1 # the first try above
	mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
	while [[ ${#current_mount_list[@]} -gt 0 ]]; do
		if [[ $tries -gt 10 ]]; then
			display_alert "${#current_mount_list[@]} dirs still mounted after ${tries} tries:" "${current_mount_list[*]}" "wrn"
		fi
		cut -d " " -f 2 "/proc/mounts" | grep "^${target}" | xargs -n1 umount --recursive &> /dev/null
		sync # wait for fsync, then count again for next loop.
		mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
		tries=$((tries + 1))
	done

	display_alert "Unmounted OK after ${tries} attempt(s)" "$target" "info"
	return 0
}

# unmount_on_exit
#
unmount_on_exit() {
	trap - ERR           # Also remove any error trap. it's too late for that.
	set +e               # we just wanna plow through this, ignoring errors.
	trap - INT TERM EXIT # remove the trap

	local stacktrace
	stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
	display_alert "trap caught, shutting down" "${stacktrace}" "err"
	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		ERROR_DEBUG_SHELL=no # dont do it twice
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL" "err"
		bash < /dev/tty >&2 || true
	fi

	cd "${SRC}" || echo "Failed to cwd to ${SRC}" # Move pwd away, so unmounts work
	# those will loop until they're unmounted.
	umount_chroot_recursive "${SDCARD}/"
	umount_chroot_recursive "${MOUNT}/"

	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain >&2 # @TODO: why does Igor uses lazy umounts? nfs?
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs >&2
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}" >&2

	# shellcheck disable=SC2153 # global var. also a local 'loop' in another function. sorry.
	if [[ -b "${LOOP}" ]]; then
		display_alert "Freeing loop" "unmount_on_exit ${LOOP}" "wrn"
		losetup -d "${LOOP}" >&2
	fi

	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"
	[[ -d "${MOUNT}" ]] && rm -rf --one-file-system "${MOUNT}"

	# if we've been called by exit_with_error itself, don't recurse.
	if [[ "${ALREADY_EXITING_WITH_ERROR:-no}" != "yes" ]]; then
		exit_with_error "generic error during build_rootfs_image: ${stacktrace}" || true # but don't trigger error again
	fi

	return 47 # trap returns error. # exit successfully. we're already handling a trap here.
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
	display_alert "Preparing u-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d || exit 1)
	chmod 700 ${TEMP_DIR}
	revision=${REVISION}
	if [[ -n $UPSTREM_VER ]]; then
		revision=${UPSTREM_VER}
		dpkg -x "${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${revision}_${ARCH}.deb" ${TEMP_DIR}/ 2>&1
	else
		dpkg -x "${DEB_STORAGE}/${CHOSEN_UBOOT}_${revision}_${ARCH}.deb" ${TEMP_DIR}/ 2>&1
	fi

	if [[ ! -f "${TEMP_DIR}/usr/lib/u-boot/platform_install.sh" ]]; then
		exit_with_error "Missing ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh"
	fi

	display_alert "Sourcing u-boot install functions" "$loop" "info"
	source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh 2>&1

	display_alert "Writing u-boot bootloader" "$loop" "info"
	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop" 2>&1
	[[ $? -ne 0 ]] && {
		rm -rf ${TEMP_DIR}
		exit_with_error "U-boot bootloader failed to install" "@host"
	}
	rm -rf ${TEMP_DIR}

	return 0
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

apt_purge_unneeded_packages() {
	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	display_alert "No longer needed packages" "purge" "info"
	chroot_sdcard_apt_get autoremove
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
	run_host_command_logged_raw chroot "${SDCARD}" /bin/bash -e -c "$*"
}

function chroot_custom_long_running() {
	local target=$1
	shift
	local _exit_code=1
	if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
		run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
		_exit_code=$?
	else
		run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
		_exit_code=$?
	fi
	return $_exit_code
}

function chroot_custom() {
	local target=$1
	shift
	run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
}

# for long-running, host-side expanded bash invocations.
# the user gets a pv-based spinner based on the number of lines that flows to stdout (log messages).
# the raw version is already redirect stderr to stdout, and we'll be running under do_with_logging,
# so: _the stdout must flow_!!!
function run_host_command_logged_long_running() {
	local _exit_code=1
	if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
		run_host_command_logged_raw /bin/bash -e -c "$*"
		_exit_code=$?
	else
		run_host_command_logged_raw /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
		_exit_code=$?
	fi
	return $_exit_code
}

# run_host_command_logged is the very basic, should be used for everything, but, please use helpers above, this is very low-level.
function run_host_command_logged() {
	run_host_command_logged_raw /bin/bash -e -c "$*"
}

# do NOT use directly, it does NOT expand the way it should (through bash)
function run_host_command_logged_raw() {
	# Log the command to the current logfile, so it has context of what was run.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "       " >> "${CURRENT_LOGFILE}" # blank line for reader's benefit
		echo "-->" "$*" " <- at $(date --utc)" >> "${CURRENT_LOGFILE}"
	fi

	# uncomment when desperate to understand what's going on
	# echo "cmd about to run" "$@" >&2

	local exit_code=666
	"$@" 2>&1 # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "--> cmd exited with code ${exit_code} at $(date --utc)" >> "${CURRENT_LOGFILE}"
	fi
	if [[ $exit_code != 0 ]]; then
		display_alert "cmd exited with code ${exit_code}" "$*" "wrn"
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
	chroot_sdcard "${@}"
}
