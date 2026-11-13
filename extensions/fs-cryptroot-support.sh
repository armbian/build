# @description Encrypts the root partition with LUKS via `cryptsetup luksFormat`, adds `cryptsetup-initramfs` to the image and requires a separate boot partition. Supports a passphrase, an auto-generated autounlock keyfile, or `dropbear-initramfs` remote SSH unlock (`CRYPTROOT_SSH_UNLOCK`). Auto-enabled when `CRYPTROOT_ENABLE=yes`.

# `cryptroot` / LUKS support is no longer included by default in prepare-host.sh.
# Enable this extension to include the required dependencies for building.
# This is automatically enabled if CRYPTROOT_ENABLE is set to yes in main-config.sh.

function add_host_dependencies__add_cryptroot_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "cryptsetup dmsetup openssh-client" "info"
	EXTRA_BUILD_DEPS+=("fs-tools::cryptsetup" "fs-tools::dmsetup" "openssh-client")
}

function extension_prepare_config__prepare_cryptroot() {
	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "cryptsetup cryptsetup-initramfs" "info"
	add_packages_to_image cryptsetup cryptsetup-initramfs

	# Unlocks other /etc/crypttab entries at boot. Older releases have it in systemd.
	case "${RELEASE}" in
		bookworm | noble) ;;
		*) add_packages_to_image systemd-cryptsetup ;;
	esac

	# Config for cryptroot, a boot partition is required.
	declare -g BOOTPART_REQUIRED=yes
	EXTRA_IMAGE_SUFFIXES+=("-crypt")

	if [[ $CRYPTROOT_SSH_UNLOCK == yes ]]; then
		display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "dropbear-initramfs" "info"
		add_packages_to_image dropbear-initramfs
	fi
}

function prepare_root_device__250_encrypt_root_device() {
	# We encrypt the rootdevice (currently a loop device) and return the new mapped rootdevice
	check_loop_device "$rootdevice"
	display_alert "Extension: ${EXTENSION}: Encrypting root partition with LUKS..." "cryptsetup luksFormat $CRYPTROOT_PARAMETERS $rootdevice" ""
	if [[ $CRYPTROOT_AUTOUNLOCK == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: configuring LUKS autounlock" ""
		declare -g cryptroot_autounlock_key_file=$(mktemp)
		openssl rand -base64 32 > "$cryptroot_autounlock_key_file"
		cryptsetup luksFormat $CRYPTROOT_PARAMETERS "$rootdevice" "$cryptroot_autounlock_key_file"
		cryptroot_open_mapper
	else # CRYPTROOT_PASSPHRASE case
		display_alert "Extension: ${EXTENSION}: configuring LUKS password" ""
		echo -n "$CRYPTROOT_PASSPHRASE" | cryptsetup luksFormat $CRYPTROOT_PARAMETERS "$rootdevice" -
		cryptroot_open_mapper
	fi
	add_cleanup_handler cleanup_cryptroot
	display_alert "Extension: ${EXTENSION}: Root partition encryption complete." "" "ext"
	# TODO: pass /dev/mapper to Docker
	rootdevice=/dev/mapper/$CRYPTROOT_MAPPER # used by `mkfs` and `mount` commands
}

# The image needs the fixed CRYPTROOT_MAPPER name: cryptsetup-initramfs finds the root in crypttab by its live name.
# Mapper names are global to the host kernel. Wait while another build on this host uses the name.
# The owner holds the mapping open until cleanup. A mapping unused for 2 minutes is stale: its build is gone.
function cryptroot_open_mapper() {
	declare -i waited=0 idle=0 timeout="${CRYPTROOT_MAPPER_TIMEOUT:-3600}"
	declare seen="" uuid="" open=""
	declare -i rc
	while true; do
		if [[ $CRYPTROOT_AUTOUNLOCK == "yes" ]]; then
			cryptsetup luksOpen --key-file "$cryptroot_autounlock_key_file" "$rootdevice" "$CRYPTROOT_MAPPER" && break || rc=$?
		else
			echo -n "$CRYPTROOT_PASSPHRASE" | cryptsetup luksOpen "$rootdevice" "$CRYPTROOT_MAPPER" - && break || rc=$?
		fi
		# Exit code 5: the device exists or is busy. Any other failure is fatal.
		((rc == 5)) || exit_with_error "cryptsetup luksOpen failed with code ${rc}" "$rootdevice"
		if ((waited >= timeout)); then
			exit_with_error "Mapper name in use after ${timeout}s" "close a stale mapping: cryptsetup luksClose $CRYPTROOT_MAPPER"
		fi
		((waited == 0)) && display_alert "Mapper name in use, another build runs" "waiting for /dev/mapper/$CRYPTROOT_MAPPER" "wrn"
		# The UUID changes with each luksFormat. Count idle time for one mapping only.
		read -r uuid open < <(dmsetup info -c --noheadings --separator ' ' -o uuid,open "$CRYPTROOT_MAPPER" 2> /dev/null) || true
		if [[ -z $uuid || $uuid != "$seen" || $open != 0 ]]; then
			seen="$uuid"
			idle=0
		elif ((idle >= 120)); then
			display_alert "Closing stale mapping, unused for ${idle}s" "$CRYPTROOT_MAPPER $uuid" "wrn"
			# Remove by UUID, not by name: another build can create a new mapping with the same name.
			dmsetup remove -u "$uuid" || true # Another waiting build can remove it first.
			idle=0
			continue
		else
			idle+=15
		fi
		sleep 15
		waited+=15
	done
	# Keep the open count above 0, also between mkfs and mount. The kernel drops the hold when the build ends.
	exec {cryptroot_hold_fd}< "/dev/mapper/$CRYPTROOT_MAPPER" ||
		display_alert "Cannot hold mapping open" "a waiting build can remove it after 2 minutes idle" "wrn"
}

function pre_install_kernel_debs__adjust_dropbear_configuration() {
	# Adjust initramfs dropbear configuration
	# Needs to be done before kernel installation, else it won't be in the initrd image
	if [[ $CRYPTROOT_SSH_UNLOCK == yes ]]; then
		declare dropbear_dir="${SDCARD}/etc/dropbear-initramfs"
		declare dropbear_config="config"

		if [[ -d "${SDCARD}/etc/dropbear/initramfs" ]]; then
			dropbear_dir="${SDCARD}/etc/dropbear/initramfs"
			dropbear_config="dropbear.conf"
		fi

		# make it publicly available to export the private.key with proper naming
		declare -g DROPBEAR_DIR=$dropbear_dir

		# Set the port of the dropbear ssh daemon in the initramfs to a different one if configured
		# this avoids the typical 'host key changed warning' - `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`
		[[ -f "${DROPBEAR_DIR}/${dropbear_config}" ]] &&
			sed -i "s/^#DROPBEAR_OPTIONS=.*/DROPBEAR_OPTIONS=\"-I 100 -j -k -p "${CRYPTROOT_SSH_UNLOCK_PORT}" -s -c cryptroot-unlock\"/" \
				"${DROPBEAR_DIR}/${dropbear_config}"

		# setup dropbear authorized_keys, either provided by userpatches or generated
		if [[ -f $USERPATCHES_PATH/dropbear_authorized_keys ]]; then
			cp "$USERPATCHES_PATH"/dropbear_authorized_keys "${DROPBEAR_DIR}"/authorized_keys
		else
			# generate a default ssh key for login on dropbear in initramfs
			# this key should be changed by the user on first login
			display_alert "Extension: ${EXTENSION}: Generating a new SSH key pair for dropbear (initramfs)" "" ""

			# Generate the SSH keys
			ssh-keygen -t ecdsa -f "${DROPBEAR_DIR}"/id_ecdsa \
				-N '' -O force-command=cryptroot-unlock -C 'AUTOGENERATED_BY_ARMBIAN_BUILD' 2>&1

			# /usr/share/initramfs-tools/hooks/dropbear will automatically add 'id_ecdsa.pub' to authorized_keys file
			# during mkinitramfs of update-initramfs
			# cat "${DROPBEAR_DIR}"/id_ecdsa.pub > "${SDCARD}"/etc/dropbear-initramfs/authorized_keys
		fi
	fi
}

function post_umount_final_image__export_private_key() {
	if [[ $CRYPTROOT_SSH_UNLOCK == yes && -f "${DROPBEAR_DIR}"/id_ecdsa ]]; then
		CRYPTROOT_SSH_UNLOCK_KEY_PATH="${DESTIMG}/${version}.key"
		# copy dropbear ssh key to image output dir for convenience
		cp "${DROPBEAR_DIR}"/id_ecdsa "${CRYPTROOT_SSH_UNLOCK_KEY_PATH}"
		display_alert "Extension: ${EXTENSION}: SSH private key for dropbear (initramfs) has been copied to:" \
			"$CRYPTROOT_SSH_UNLOCK_KEY_PATH" "info"
	fi
}

function post_umount_final_image__750_cryptroot_cleanup() {
	execute_and_remove_cleanup_handler cleanup_cryptroot
}

function cleanup_cryptroot() {
	[[ -n $cryptroot_hold_fd ]] && exec {cryptroot_hold_fd}<&- && unset cryptroot_hold_fd
	cryptsetup luksClose "${CRYPTROOT_MAPPER}" 2>&1
	display_alert "Cryptroot closed ${CRYPTROOT_MAPPER}" "${EXTENSION}" "info"
}
