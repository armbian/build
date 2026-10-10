#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Alastair D'Silva <alastair@d-silva.org>
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function is_valid_ipv4() {
	local ip=$1
	local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
	if [[ $ip =~ $rx ]]; then
		local IFS='.'
		local -a octets
		octets=($ip)
		if (( octets[0] <= 255 && octets[1] <= 255 && octets[2] <= 255 && octets[3] <= 255 )); then
			return 0
		fi
	fi
	return 1
}

function netboot_parse_variables() {
	# 1. Parse or prompt variables (TFTP server, NFS server, NFS path)
	if [[ -n "${NETBOOT_TFTP_SERVER}" ]]; then
		if ! is_valid_ipv4 "${NETBOOT_TFTP_SERVER}"; then
			exit_with_error "Provided NETBOOT_TFTP_SERVER='${NETBOOT_TFTP_SERVER}' is not a valid IPv4 address."
		fi
	else
		if [[ -t 0 ]]; then
			while true; do
				read -p "Enter TFTP Server IP address [192.168.1.1]: " NETBOOT_TFTP_SERVER
				NETBOOT_TFTP_SERVER=${NETBOOT_TFTP_SERVER:-"192.168.1.1"}
				if is_valid_ipv4 "${NETBOOT_TFTP_SERVER}"; then
					break
				fi
				display_alert "Invalid IPv4 address" "${NETBOOT_TFTP_SERVER}" "wrn"
			done
		else
			NETBOOT_TFTP_SERVER="192.168.1.1"
		fi
	fi

	if [[ -n "${NETBOOT_NFS_SERVER}" ]]; then
		if ! is_valid_ipv4 "${NETBOOT_NFS_SERVER}"; then
			exit_with_error "Provided NETBOOT_NFS_SERVER='${NETBOOT_NFS_SERVER}' is not a valid IPv4 address."
		fi
	else
		NETBOOT_NFS_SERVER="${NETBOOT_TFTP_SERVER}"
	fi

	if [[ -z "${NETBOOT_NFS_PATH}" ]]; then
		NETBOOT_NFS_PATH="/srv/nfs/${BOARD}"
	fi

	if [[ -n "${NETBOOT_SUBNET}" ]]; then
		if ! is_valid_ipv4 "${NETBOOT_SUBNET}"; then
			exit_with_error "Provided NETBOOT_SUBNET='${NETBOOT_SUBNET}' is not a valid IPv4 address."
		fi
	else
		if [[ -t 0 ]]; then
			while true; do
				read -p "Enter Target Subnet Address [192.168.1.0]: " NETBOOT_SUBNET
				NETBOOT_SUBNET=${NETBOOT_SUBNET:-"192.168.1.0"}
				if is_valid_ipv4 "${NETBOOT_SUBNET}"; then
					break
				fi
				display_alert "Invalid IPv4 address" "${NETBOOT_SUBNET}" "wrn"
			done
		else
			NETBOOT_SUBNET="192.168.1.0"
		fi
	fi

	if [[ -n "${NETBOOT_ROUTER_IP}" ]]; then
		if ! is_valid_ipv4 "${NETBOOT_ROUTER_IP}"; then
			exit_with_error "Provided NETBOOT_ROUTER_IP='${NETBOOT_ROUTER_IP}' is not a valid IPv4 address."
		fi
	else
		if [[ -t 0 ]]; then
			while true; do
				read -p "Enter Router/Gateway IP [192.168.1.1]: " NETBOOT_ROUTER_IP
				NETBOOT_ROUTER_IP=${NETBOOT_ROUTER_IP:-"192.168.1.1"}
				if is_valid_ipv4 "${NETBOOT_ROUTER_IP}"; then
					break
				fi
				display_alert "Invalid IPv4 address" "${NETBOOT_ROUTER_IP}" "wrn"
			done
		else
			NETBOOT_ROUTER_IP="192.168.1.1"
		fi
	fi

	if [[ -n "${NETBOOT_NETMASK}" ]]; then
		if ! is_valid_ipv4 "${NETBOOT_NETMASK}"; then
			exit_with_error "Provided NETBOOT_NETMASK='${NETBOOT_NETMASK}' is not a valid IPv4 address."
		fi
	else
		if [[ -t 0 ]]; then
			while true; do
				read -p "Enter Network Mask [255.255.255.0]: " NETBOOT_NETMASK
				NETBOOT_NETMASK=${NETBOOT_NETMASK:-"255.255.255.0"}
				if is_valid_ipv4 "${NETBOOT_NETMASK}"; then
					break
				fi
				display_alert "Invalid IPv4 address" "${NETBOOT_NETMASK}" "wrn"
			done
		else
			NETBOOT_NETMASK="255.255.255.0"
		fi
	fi

	display_alert "Netboot configuration" "TFTP: ${NETBOOT_TFTP_SERVER}, NFS: ${NETBOOT_NFS_SERVER}:${NETBOOT_NFS_PATH}, Subnet: ${NETBOOT_SUBNET}/${NETBOOT_NETMASK}, Router: ${NETBOOT_ROUTER_IP}" "info"

	# Calculate version via calculate_image_version
	declare calculated_image_version="undetermined"
	calculate_image_version
	declare -r -g version="${calculated_image_version}"
}

function netboot_provision_rootfs() {
	# 1. Write netboot MOTD checker to target rootfs
	display_alert "Adding netboot MOTD checker" "${SDCARD}/etc/update-motd.d/42-netboot-check" "info"
	mkdir -p "${SDCARD}/etc/update-motd.d"
	cat <<'EOF' > "${SDCARD}/etc/update-motd.d/42-netboot-check"
#!/bin/sh
# Check if system is running on NFS root
if grep -q "root=/dev/nfs" /proc/cmdline; then
	printf "\n\033[1;33m*** Running on Network Boot (NFS Root) ***\033[0m\n"
	nfs_source=$(mount | grep "on / type nfs")
	if [ -n "${nfs_source}" ]; then
		printf "  NFS Export: %s\n" "${nfs_source}"
		printf "  To boot the upgraded kernel, ensure the host-side bind-mount of /boot\n"
		printf "  to the TFTP root directory is active and working.\n\n"
	fi
fi
EOF
	chmod 755 "${SDCARD}/etc/update-motd.d/42-netboot-check"

	# Disable filesystem resize service (resizing NFS is meaningless and error-prone)
	touch "${SDCARD}/root/.no_rootfs_resize"

	# Adjust /etc/fstab inside target rootfs to comment out block devices
	if [[ -f "${SDCARD}/etc/fstab" ]]; then
		display_alert "Adjusting fstab for netboot" "${SDCARD}/etc/fstab" "info"
		sed -i -E 's@^([[:space:]]*(UUID=|PARTUUID=|LABEL=|/dev/[a-zA-Z0-9]))@# \1@' "${SDCARD}/etc/fstab"
	fi
}

function netboot_setup_overlayroot() {
	# 2. Add overlayroot support for read-only NFS rootfs sharing (writes go to tmpfs/RAM)
	# This installs an init-bottom script in initramfs-tools which moves the RO NFS mount
	# to /overlay-ro and sets up an overlayfs with a tmpfs upper over it if 'overlayroot=tmpfs'
	# is passed in the boot cmdline.
	local overlay_script="${SDCARD}/etc/initramfs-tools/scripts/init-bottom/overlay-nfs"
	mkdir -p "${SDCARD}/etc/initramfs-tools/scripts/init-bottom"
	cat <<'EOF' > "${overlay_script}"
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
echo "overlay-nfs: init-bottom script started"
echo "overlay-nfs: init-bottom script started" > /dev/kmsg 2>/dev/null || true

# read-only NFS root + per-board tmpfs overlay (writes -> RAM).
cmdline=""
if [ -r /proc/cmdline ]; then
    read -r cmdline </proc/cmdline
fi
case " $cmdline " in
    *" overlayroot=tmpfs "*)
        ;;
    *)
        echo "overlay-nfs: overlayroot=tmpfs not found in cmdline"
        echo "overlay-nfs: overlayroot=tmpfs not found in cmdline" > /dev/kmsg 2>/dev/null || true
        exit 0
        ;;
esac

if [ -z "$rootmnt" ]; then
    echo "overlay-nfs: rootmnt is empty"
    echo "overlay-nfs: rootmnt is empty" > /dev/kmsg 2>/dev/null || true
    exit 0
fi
echo "overlay-nfs: loading overlay module"
echo "overlay-nfs: loading overlay module" > /dev/kmsg 2>/dev/null || true
modprobe overlay 2>/dev/null || true

mkdir -p /overlay-ro /overlay-rw
echo "overlay-nfs: mounting tmpfs on /overlay-rw"
echo "overlay-nfs: mounting tmpfs on /overlay-rw" > /dev/kmsg 2>/dev/null || true
if ! mount -t tmpfs -o mode=0755 tmpfs /overlay-rw; then
    echo "overlay-nfs: failed to mount tmpfs on /overlay-rw"
    echo "overlay-nfs: failed to mount tmpfs on /overlay-rw" > /dev/kmsg 2>/dev/null || true
    exit 0
fi

mkdir -p /overlay-rw/upper /overlay-rw/work
echo "overlay-nfs: moving rootmnt $rootmnt to /overlay-ro"
echo "overlay-nfs: moving rootmnt $rootmnt to /overlay-ro" > /dev/kmsg 2>/dev/null || true
if ! mount -o move "$rootmnt" /overlay-ro; then
    echo "overlay-nfs: failed to move rootmnt $rootmnt to /overlay-ro"
    echo "overlay-nfs: failed to move rootmnt $rootmnt to /overlay-ro" > /dev/kmsg 2>/dev/null || true
    exit 0
fi

echo "overlay-nfs: mounting overlayfs onto $rootmnt"
echo "overlay-nfs: mounting overlayfs onto $rootmnt" > /dev/kmsg 2>/dev/null || true
if ! mount -t overlay \
        -o lowerdir=/overlay-ro,upperdir=/overlay-rw/upper,workdir=/overlay-rw/work overlay "$rootmnt"; then
    echo "overlay-nfs: overlay mount failed, moving lower back to $rootmnt"
    echo "overlay-nfs: overlay mount failed, moving lower back to $rootmnt" > /dev/kmsg 2>/dev/null || true
    mount -o move /overlay-ro "$rootmnt"   # overlay failed -> boot the RO root, still bootable
    exit 0
fi

echo "overlay-nfs: overlay mount succeeded!"
echo "overlay-nfs: overlay mount succeeded!" > /dev/kmsg 2>/dev/null || true
# keep the lower (NFS) + upper (tmpfs) reachable from inside the booted system
mkdir -p "$rootmnt/run/overlay/ro" "$rootmnt/run/overlay/rw"
mount -o move /overlay-ro "$rootmnt/run/overlay/ro" 2>/dev/null || true
mount -o move /overlay-rw "$rootmnt/run/overlay/rw" 2>/dev/null || true
EOF
	chmod 755 "${overlay_script}"

	# Force overlay module to be loaded by including it in /etc/initramfs-tools/modules
	mkdir -p "${SDCARD}/etc/initramfs-tools"
	touch "${SDCARD}/etc/initramfs-tools/modules"
	if ! grep -qxF overlay "${SDCARD}/etc/initramfs-tools/modules"; then
		echo overlay >> "${SDCARD}/etc/initramfs-tools/modules"
	fi

	# Ensure initramfs-tools is installed inside the target rootfs
	if ! chroot_sdcard_with_stdout test -x /usr/sbin/update-initramfs; then
		display_alert "Installing initramfs-tools in target rootfs" "apt-get" "info"
		chroot_sdcard_apt_get_install initramfs-tools
	fi

	# Rebuild the initramfs with update-initramfs inside the chroot
	if chroot_sdcard_with_stdout test -x /usr/sbin/update-initramfs; then
		display_alert "Rebuilding initramfs with overlayroot support" "update-initramfs" "info"
		chroot_sdcard update-initramfs -c -k all
	fi

	# Generate uInitrd from the newly compiled initrd image
	local newest_initrd
	newest_initrd=$(ls -1t "${SDCARD}/boot/initrd.img-"* 2>/dev/null | head -n 1)
	if [[ -n "${newest_initrd}" ]]; then
		display_alert "Generating uInitrd from newest initrd.img" "$(basename "${newest_initrd}")" "info"
		local arch="arm64"
		case "${ARCH}" in
			armhf|armel) arch="arm" ;;
			riscv64) arch="riscv" ;;
			x86_64) arch="x86_64" ;;
		esac
		mkimage -A "${arch}" -O linux -T ramdisk -C none -n uInitrd -d "${newest_initrd}" "${SDCARD}/boot/uInitrd" >/dev/null 2>&1
		[[ -s "${SDCARD}/boot/uInitrd" ]] || exit_with_error "Failed to generate netboot uInitrd"
	fi
}

function netboot_create_archives() {
	# Choose the compressor (zstdmt > zstd > gzip)
	compressor="gzip -c"
	ext="tar.gz"
	if command -v zstdmt >/dev/null 2>&1; then
		compressor="zstdmt -c"
		ext="tar.zst"
	elif command -v zstd >/dev/null 2>&1; then
		compressor="zstd -c"
		ext="tar.zst"
	fi

	# Pack $SDCARD to rootfs.tar.zst
	display_alert "Creating rootfs archive" "${version}-rootfs.${ext}" "info"
	local exclude_home="--exclude='./home/*'"
	if [[ ${INCLUDE_HOME_DIR:-no} == yes ]]; then exclude_home=""; fi
	(
		set -o pipefail
		tar cp --xattrs --directory="$SDCARD/" --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' --exclude='./sys/*' $exclude_home . | \
			$compressor > "${FINALDEST}/${version}-rootfs.${ext}"
	)

	# Pack $SDCARD/boot to boot.tar.zst
	display_alert "Creating boot/kernel archive" "${version}-boot.${ext}" "info"
	(
		set -o pipefail
		tar cp --xattrs --directory="$SDCARD/boot" . | \
			$compressor > "${FINALDEST}/${version}-boot.${ext}"
	)
}

function netboot_compile_script() {
	display_alert "Generating netboot PXE-boot script" "${netboot_dir}/boot.scr" "info"

	local temp_boot_cmd
	temp_boot_cmd=$(mktemp)

	# Export board console arguments to set default consoleargs in bootscript
	bootscript_export_display_console
	bootscript_export_serial_console
	local board_consoleargs_raw="${BOOTSCRIPT_TEMPLATE__SERIAL_CONSOLE} ${BOOTSCRIPT_TEMPLATE__DISPLAY_CONSOLE}"
	board_consoleargs=$(echo "${board_consoleargs_raw}" | xargs)
	if [[ -z "${board_consoleargs}" ]]; then
		board_consoleargs="console=ttyS0,115200"
	fi

	cat <<EOF > "${temp_boot_cmd}"
# Default fallback variables
setenv load_addr "0x45000000"
setenv rootpath ""
setenv nfs_server_ip "${NETBOOT_NFS_SERVER}"
setenv nfs_path "${NETBOOT_NFS_PATH}"
setenv tftp_server_ip "${NETBOOT_TFTP_SERVER}"
setenv consoleargs "${board_consoleargs}"

# Load local overrides from armbianEnv.txt if present
if test -e \${devtype} \${devnum} \${prefix}armbianEnv.txt; then
	echo "Loading netboot env from SD card..."
	load \${devtype} \${devnum} \${load_addr} \${prefix}armbianEnv.txt
	env import -t \${load_addr} \${filesize}
fi

# Request network parameters via DHCP if not already set
if test -z "\${ipaddr}"; then
	echo "Requesting DHCP IP..."
	setenv autoload no
	setenv autoload 0
	dhcp
fi

# Determine TFTP server IP
if test -n "\${tftp_server_ip}"; then
	setenv serverip "\${tftp_server_ip}"
elif test -z "\${serverip}"; then
	setenv serverip "\${nfs_server_ip}"
fi
echo "TFTP Server IP: \${serverip}"

# Define standard load addresses if not set (PXE uses pxefile_addr_r for config loading)
if test -z "\${pxefile_addr_r}"; then setenv pxefile_addr_r 0x4f000000; fi

# Configure bootfile relative prefix for PXE config fetch
# This ensures U-Boot requests '${BOARD}/'
setenv bootfile "${BOARD}/"

echo "Performing PXE boot from TFTP directory: \${bootfile} ..."
if tftpboot \${pxefile_addr_r} \${bootfile}pxelinux.cfg/default; then
	pxe boot
fi
EOF

	local arch="arm64"
	case "${ARCH}" in
		armhf|armel) arch="arm" ;;
		riscv64) arch="riscv" ;;
		x86_64) arch="x86_64" ;;
	esac

	mkimage -C none -A "${arch}" -T script -d "${temp_boot_cmd}" "${netboot_dir}/boot.scr" >/dev/null 2>&1
	rm -f "${temp_boot_cmd}"
}

function netboot_stage_tftp_files() {
	# Extract raw boot files (Image, DTB, boot.scr) to ${version}-netboot/
	netboot_dir="${FINALDEST}/${version}-netboot"
	display_alert "Copying raw boot files for TFTP to" "${netboot_dir}" "info"
	mkdir -p "${netboot_dir}"

	# Copy kernel image
	if [[ -f "${SDCARD}/boot/Image" ]]; then
		cp "${SDCARD}/boot/Image" "${netboot_dir}/Image"
	elif [[ -f "${SDCARD}/boot/vmlinuz-${IMAGE_INSTALLED_KERNEL_VERSION}" ]]; then
		cp "${SDCARD}/boot/vmlinuz-${IMAGE_INSTALLED_KERNEL_VERSION}" "${netboot_dir}/Image"
	else
		# Collect candidate kernel files
		local candidates=()
		while IFS= read -r -d '' file; do
			candidates+=("$file")
		done < <(find "${SDCARD}/boot" -maxdepth 1 \( -name "vmlinuz*" -o -name "Image" \) -type f -print0 2>/dev/null)

		if [[ ${#candidates[@]} -eq 1 ]]; then
			cp "${candidates[0]}" "${netboot_dir}/Image"
		elif [[ ${#candidates[@]} -eq 0 ]]; then
			exit_with_error "No kernel image found in ${SDCARD}/boot/ to copy for netboot."
		else
			exit_with_error "Multiple kernel image candidates found in ${SDCARD}/boot/: ${candidates[*]}."
		fi
	fi

	# Copy DTB(s)
	if [[ -d "${SDCARD}/boot/dtb" ]]; then
		cp -r "${SDCARD}/boot/dtb"/* "${netboot_dir}/"
	elif [[ -d "${SDCARD}/boot/dtb-${IMAGE_INSTALLED_KERNEL_VERSION}" ]]; then
		cp -r "${SDCARD}/boot/dtb-${IMAGE_INSTALLED_KERNEL_VERSION}"/* "${netboot_dir}/"
	fi

	# Generate and compile the netboot-specific boot.scr inside TFTP staging dir
	netboot_compile_script

	# Copy uInitrd
	if [[ -f "${SDCARD}/boot/uInitrd" ]]; then
		cp "${SDCARD}/boot/uInitrd" "${netboot_dir}/"
	fi

	# Generate standard PXE configuration (pxelinux.cfg/default)
	local pxe_dir_target="${SDCARD}/boot/pxelinux.cfg"
	mkdir -p "${pxe_dir_target}"
	local dtb_rel_path=""
	local fdt_required="no"
	case "${ARCH}" in
		armhf|armel|arm64|riscv64) fdt_required="yes" ;;
	esac

	if [[ "${fdt_required}" == "yes" ]]; then
		if [[ -n "${BOOT_FDT_FILE}" && -f "${netboot_dir}/${BOOT_FDT_FILE}" ]]; then
			dtb_rel_path="${BOOT_FDT_FILE}"
		elif [[ -n "${BOOT_FDT_FILE}" && -f "${netboot_dir}/$(basename "${BOOT_FDT_FILE}")" ]]; then
			dtb_rel_path="$(basename "${BOOT_FDT_FILE}")"
		else
			# If BOOT_FDT_FILE is not set or not found, look for any .dtb file as a last resort
			local dtb_file
			dtb_file=$(find "${netboot_dir}" -name "*.dtb" -type f | head -n 1)
			if [[ -n "${dtb_file}" ]]; then
				dtb_rel_path=$(realpath --relative-to="${netboot_dir}" "${dtb_file}")
			else
				exit_with_error "Could not resolve a valid DTB file for FDT-based architecture (${ARCH}). BOOT_FDT_FILE='${BOOT_FDT_FILE}'."
			fi
		fi
	fi

	display_alert "Generating PXE configuration" "${pxe_dir_target}/default" "info"
	cat <<EOF > "${pxe_dir_target}/default"
default armbian
label armbian
  kernel Image
  initrd uInitrd
EOF

	if [[ -n "${dtb_rel_path}" ]]; then
		echo "  fdt ${dtb_rel_path}" >> "${pxe_dir_target}/default"
	fi

	cat <<EOF >> "${pxe_dir_target}/default"
  append root=/dev/nfs nfsroot=${NETBOOT_NFS_SERVER}:${NETBOOT_NFS_PATH},v3 rw ip=dhcp ${board_consoleargs}
EOF

	# Also copy to staging TFTP directory for initial setup
	local pxe_dir="${netboot_dir}/pxelinux.cfg"
	mkdir -p "${pxe_dir}"
	cp "${pxe_dir_target}/default" "${pxe_dir}/default"
}

function netboot_write_deployment_guide() {
	local extract_cmd="tar -I zstd -xf"
	if [[ "${ext}" == "tar.gz" ]]; then
		extract_cmd="tar -zxf"
	fi

	# Write netboot.md deployment guide
	display_alert "Creating deployment guide" "${netboot_dir}/netboot.md" "info"
	(
		local BOARD_CAPITALIZED="${BOARD^}"
		export BOARD BOARD_CAPITALIZED version ext NETBOOT_NFS_SERVER NETBOOT_NFS_PATH NETBOOT_SUBNET NETBOOT_NETMASK NETBOOT_TFTP_SERVER NETBOOT_ROUTER_IP extract_cmd
		envsubst '$BOARD $BOARD_CAPITALIZED $version $ext $NETBOOT_NFS_SERVER $NETBOOT_NFS_PATH $NETBOOT_SUBNET $NETBOOT_NETMASK $NETBOOT_TFTP_SERVER $NETBOOT_ROUTER_IP $extract_cmd' \
			< "${SRC}/config/templates/netboot.md.template" > "${netboot_dir}/netboot.md"
	)
}

function netboot_create_bootloader_image() {
	# Create minimal 32MB bootloader image containing U-Boot and boot.scr
	local netboot_img="${FINALDEST}/${version}-bootloader.img"
	display_alert "Creating minimal bootloader image" "${netboot_img}" "info"

	# Create blank image (32MB)
	truncate --size=32M "${netboot_img}"

	# Write partition table with sfdisk
	sfdisk "${netboot_img}" <<EOF >/dev/null 2>&1
label: dos
2048,,c,*
EOF

	# Lock and setup loop device
	exec {FD}> /var/lock/armbian-debootstrap-losetup
	flock -x $FD
	local loop_dev
	loop_dev=$(losetup --show --partscan --find "${netboot_img}")
	flock -u $FD

	# Register a cleanup handler immediately after loop_dev is assigned
	declare -g NETBOOT_LOOP_DEV="${loop_dev}"
	declare -g NETBOOT_TEMP_MOUNT=""
	cleanup_netboot_loop() {
		if [[ -n "${NETBOOT_TEMP_MOUNT}" ]]; then
			if mountpoint -q "${NETBOOT_TEMP_MOUNT}" 2>/dev/null; then
				umount "${NETBOOT_TEMP_MOUNT}" >/dev/null 2>&1 || true
			fi
			if [[ -d "${NETBOOT_TEMP_MOUNT}" ]]; then
				rmdir "${NETBOOT_TEMP_MOUNT}" >/dev/null 2>&1 || true
			fi
		fi
		if [[ -n "${NETBOOT_LOOP_DEV}" ]]; then
			free_loop_device_insistent "${NETBOOT_LOOP_DEV}" >/dev/null 2>&1 || true
		fi
	}
	add_cleanup_handler "cleanup_netboot_loop"

	# Format FAT32
	check_loop_device "${loop_dev}p1"
	mkfs.vfat -F32 -n "NETBOOT" "${loop_dev}p1" >/dev/null 2>&1

	# Mount
	local temp_mount
	temp_mount=$(mktemp -d)
	NETBOOT_TEMP_MOUNT="${temp_mount}"
	mount "${loop_dev}p1" "${temp_mount}"

	# Copy compiled boot.scr from TFTP staging directory
	cp "${netboot_dir}/boot.scr" "${temp_mount}/boot.scr"

	# Create default armbianEnv.txt
	cat <<EOF > "${temp_mount}/armbianEnv.txt"
# Environment overrides for network booting
# Uncomment and configure as needed:
# tftp_server_ip=${NETBOOT_TFTP_SERVER}
# nfs_server_ip=${NETBOOT_NFS_SERVER}
# nfs_path=${NETBOOT_NFS_PATH}
# consoleargs=${board_consoleargs}
EOF

	# Clean up mount
	umount "${temp_mount}"
	rmdir "${temp_mount}"
	NETBOOT_TEMP_MOUNT=""

	# Write U-Boot to raw sectors of the loop device
	# Check if uboot package is present in image_artifacts_debs_reversioned
	if [[ -n "${image_artifacts_debs_reversioned["uboot"]}" && -f "${DEB_STORAGE}/${image_artifacts_debs_reversioned["uboot"]}" ]]; then
		write_uboot_to_loop_image "${loop_dev}" "${DEB_STORAGE}/${image_artifacts_debs_reversioned["uboot"]}"
	else
		exit_with_error "Required U-Boot package is missing or unusable for board: ${BOARD}"
	fi

	# Clean up loop device, and disarm/remove the cleanup handler
	execute_and_remove_cleanup_handler "cleanup_netboot_loop"
}

function create_netboot_tarballs_and_images() {
	# Ensure the output directory exists
	mkdir -p "${FINALDEST}"

	# Local variables passed down to sub-functions via dynamic scoping
	local compressor=""
	local ext=""
	local netboot_dir=""
	local board_consoleargs=""

	netboot_parse_variables
	netboot_provision_rootfs
	netboot_setup_overlayroot
	netboot_stage_tftp_files
	netboot_create_archives
	netboot_write_deployment_guide
	netboot_create_bootloader_image

	return 0
}
