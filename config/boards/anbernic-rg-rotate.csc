# Unisoc T618 (UMS512) octa core 4" 720x720 swivel touch LCD eMMC MicroSD WiFi/BT
BOARD_NAME="RG Rotate"
BOARD_VENDOR="anbernic"
BOARDFAMILY="sprd-ums512"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

BOOT_FDT_FILE="sprd/ums512-rg-rotate.dtb"

IMAGE_PARTITION_TABLE="gpt"

# extlinux is hardcoded to mmc 1:2, so /boot must be a real partition 2.
BOOTFS_TYPE="fat"

SERIALCON="ttyGS0"
# loglevel=1 keeps the WCN driver's 5-second chatter off the panel, which is the
# only console here. Not 0: a panic has nowhere else to go.
SRC_CMDLINE="console=tty0 loglevel=1 log_buf_len=8M"

PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev alsa-utils alsa-ucm-conf"

# Vendor BSP U-Boot: it carries the sprd DDR/PMIC/panel init and the extlinux
# scan. Mainline U-Boot has no ums512 support.
function post_family_config__anbernic_rg_rotate_vendor_uboot() {
	display_alert "$BOARD" "vendor BSP U-Boot (ums512_1h10 board, rg_rotate config)" "info"

	# Mirror of beebono/u-boot-ums512, pinned (see the family config for why).
	declare -g BOOTSOURCE="https://github.com/crackerjacques/u-boot-ums512.git"
	declare -g BOOTBRANCH="commit:d1f91089bcb2df300f1e8a92938c1ca84a183e8c"
	# Not the generic ums512_1h10 defconfig: only this board's header defines
	# CONFIG_FS_FAT, without which extlinux halts on "No OS found".
	declare -g BOOTCONFIG="ums512_rg_rotate_defconfig"
	declare -g BOOTDIR="u-boot-${BOARD}"
	# Drops -ansi from the cpp rules; the Spreadtrum headers use // comments.
	declare -g BOOTPATCHDIR="u-boot-ums512"
	declare -g UBOOT_TARGET_MAP="ARCH=arm DEVICE_TREE=ums512_rg_rotate u-boot-dtb.bin;;uboot_dhtb.img"
	declare -g BOOTSCRIPT=""
}

# The splash hides the boot on a panel-only console.
function post_family_config__anbernic_rg_rotate_no_plymouth() {
	declare -g PLYMOUTH="no"
	declare -g MAIN_CMDLINE="${MAIN_CMDLINE/ splash/}"
	declare -g MAIN_CMDLINE="${MAIN_CMDLINE/ plymouth.ignore-serial-consoles/}"
	display_alert "$BOARD" "Plymouth disabled" "info"
}

# Vendor WCN / AGDSP firmware; without it Wi-Fi, Bluetooth and audio are dead.
function post_family_tweaks__anbernic_rg_rotate_wcn_firmware() {
	display_alert "$BOARD" "installing sprd WCN/AGDSP firmware" "info"

	declare blobs="${SRC}/packages/blobs/sprd-ums512"
	[[ -d "${blobs}" ]] || exit_with_error "Missing sprd firmware blobs" "${blobs}"

	# Named explicitly, not a glob: every file here has a driver that requests it
	# by that exact name, and a glob makes a blob nobody wants impossible to spot.
	declare -a fw=(agdsp.bin wcnmodem.bin sprd/bt_configure_pskey.ini
		sprd/bt_configure_rf.ini sprd/wifi_board_config.ini)
	declare f

	run_host_command_logged mkdir -p "${SDCARD}/lib/firmware/updates/sprd"
	for f in "${fw[@]}"; do
		[[ -f "${blobs}/${f}" ]] || exit_with_error "Missing sprd firmware blob" "${blobs}/${f}"
		run_host_command_logged cp -v "${blobs}/${f}" "${SDCARD}/lib/firmware/updates/${f}"
	done

	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/hooks"
	cat <<- 'INITRAMFS_HOOK' > "${SDCARD}/etc/initramfs-tools/hooks/sprd-firmware"
		#!/bin/sh
		PREREQ=""
		prereqs() { echo "$PREREQ"; }
		case "$1" in prereqs) prereqs; exit 0 ;; esac
		. /usr/share/initramfs-tools/hook-functions

		# ONLY agdsp.bin: sprd-audcp-boot probes before the rootfs is mounted. Do
		# NOT add wcnmodem.bin - reachable firmware makes the WCN core commit to a
		# full bring-up in the initramfs, which wedges udev until /init panics.
		for f in /lib/firmware/updates/agdsp.bin; do
			[ -f "$f" ] && copy_file firmware "$f" "$f"
		done
		exit 0
	INITRAMFS_HOOK
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/hooks/sprd-firmware"
}

# MODULES=most pulls sc23xx_wlan_sdio into the initrd, and probing it there wedges
# udev until /init panics. Nothing in the root path needs a module.
function post_family_tweaks__anbernic_rg_rotate_initramfs_modules() {
	display_alert "$BOARD" "initrd: MODULES=dep (keep WCN out of early boot)" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/conf.d"
	cat <<- 'INITRAMFS_CONF' > "${SDCARD}/etc/initramfs-tools/conf.d/rg-rotate.conf"
		MODULES=dep
	INITRAMFS_CONF
}

# The WCN BSP keeps udev events outstanding for the whole initramfs, so upstream's
# init-bottom/udev aborts under "set -e" before moving /dev and /init panics.
# Nothing here needs a settled queue; both overrides are upstream bar the settle.
function post_family_tweaks__anbernic_rg_rotate_initramfs_udev() {
	display_alert "$BOARD" "initrd: bounded udevadm settle in init-top/init-bottom" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/scripts/init-bottom"
	cat <<- 'INIT_BOTTOM_UDEV' > "${SDCARD}/etc/initramfs-tools/scripts/init-bottom/udev"
		#!/bin/sh
		# Board override of /usr/share/initramfs-tools/scripts/init-bottom/udev:
		# no "set -e", and a short, non-fatal settle. See the Armbian board config.

		PREREQS=""

		prereqs() { echo "$PREREQS"; }

		case "$1" in
		    prereqs)
		    prereqs
		    exit 0
		    ;;
		esac

		# Do not let a still-busy queue abort this script: /dev MUST be moved
		# below, or /init cannot open ${rootmnt}/dev/console and the kernel panics.
		if ! udevadm settle --timeout=0 > /dev/null 2>&1; then
		    echo "udev queue not empty; continuing anyway" > /dev/kmsg
		fi
		udevadm control --exit || true

		# move the /dev tmpfs to the rootfs; fall back to util-linux mount that does
		# not understand -o move
		mount -n -o move /dev "${rootmnt:?}/dev" || mount -n --move /dev "${rootmnt}/dev"

		# create a temporary symlink to the final /dev for other initramfs scripts
		if command -v nuke >/dev/null; then
		    nuke /dev
		else
		    # shellcheck disable=SC2114
		    rm -rf /dev
		fi
		ln -s "${rootmnt}/dev" /dev
	INIT_BOTTOM_UDEV
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/scripts/init-bottom/udev"

	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/scripts/init-top"
	cat <<- 'INIT_TOP_UDEV' > "${SDCARD}/etc/initramfs-tools/scripts/init-top/udev"
		#!/bin/sh -e
		# Board override of /usr/share/initramfs-tools/scripts/init-top/udev:
		# the settle below is bounded. See the Armbian board config.

		PREREQS=""

		prereqs() { echo "$PREREQS"; }

		case "$1" in
		    prereqs)
		    prereqs
		    exit 0
		    ;;
		esac

		if [ -w /sys/kernel/uevent_helper ]; then
			echo > /sys/kernel/uevent_helper
		fi

		if [ "${quiet:-n}" = "y" ]; then
			log_level=notice
		else
			log_level=info
		fi

		# Not a fixed path: a non-usr-merged initramfs has only /lib/systemd, and
		# this script runs under "sh -e", so a missing binary aborts udev startup.
		for udevd in /usr/lib/systemd/systemd-udevd /lib/systemd/systemd-udevd; do
			[ -x "$udevd" ] && break
		done
		SYSTEMD_LOG_LEVEL=$log_level "$udevd" --daemon --resolve-names=never

		udevadm trigger --type=subsystems --action=add
		udevadm trigger --type=devices --action=add
		# --timeout=0 only samples the queue, so this costs nothing; silence it
		# because udevadm prints its own error on a non-empty queue and this
		# board's console is the panel.
		udevadm settle --timeout=0 > /dev/null 2>&1 || true

	INIT_TOP_UDEV
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/scripts/init-top/udev"
}

# USB-gadget serial console; no UART here. The drop-in is not optional.
function post_family_tweaks__anbernic_rg_rotate_console() {
	display_alert "$BOARD" "enabling ttyGS0 console" "info"
	mkdir -p "${SDCARD}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/serial-getty@.service \
		"${SDCARD}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

	display_alert "$BOARD" "ttyGS0: keeping systemd-executor off the gadget TTY" "info"
	run_host_command_logged mkdir -p \
		"${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d"
	cat <<- 'GADGET_TTY' > "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d/10-gadget-nonblocking.conf"
		# See the Armbian board config for why this exists: without it,
		# systemd-executor blocks in the pre-exec TTY setup of this unit while
		# holding the exclusive flock on /dev/console, and PID 1 deadlocks on
		# that lock the first time it needs the console.
		[Service]
		TTYPath=
		TTYReset=no
		TTYVHangup=no
		StandardInput=null
		StandardOutput=journal
		StandardError=journal
		ExecStart=
		ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud --local-line 115200,57600,38400,9600 ttyGS0 $TERM
	GADGET_TTY
}

# Gamepad-to-keyboard remap (bsp-cli payload). On by default: the only inputs are
# the gamepad GPIOs and the touchscreen.
function post_family_tweaks__anbernic_rg_rotate_helpers() {
	display_alert "$BOARD" "enabling rotate-pad2key" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	run_host_command_logged ln -sf /etc/systemd/system/rotate-pad2key.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rotate-pad2key.service"
}

# rotate-wcn-nosleep ships but is NOT enabled: ~10 mA on a ~114 mA idle draw to
# remove a 1-2 s hole after idle. See its script header.

# Audio (bsp-cli payload: UCM profile, WirePlumber rules, mixer setup, prime).
# Registration can land after multi-user.target.
function post_family_tweaks__anbernic_rg_rotate_audio() {
	display_alert "$BOARD" "enabling speaker routing" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	run_host_command_logged ln -sf /etc/systemd/system/rotate-audio.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rotate-audio.service"
}
