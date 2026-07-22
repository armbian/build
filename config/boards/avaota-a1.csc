# Allwinner Cortex-A55 octa core 2/4GB RAM SoC USB3 USB-C 2x GbE LCD
BOARD_NAME="Avaota A1"
BOARD_VENDOR="allwinner"
BOARD_MAINTAINER="juanesf"
INTRODUCED="2024"
OVERLAY_PREFIX="sun55i-t527"
BOOT_FDT_FILE="allwinner/sun55i-t527-avaota-a1.dtb"
HAS_VIDEO_OUTPUT=no
KERNEL_TARGET="legacy,edge"
KERNEL_TEST_TARGET="legacy,edge"

# Branch selection:
#   BRANCH=legacy -> SyterKit bootloader + Allwinner BSP kernel 5.15 (sun55iw3-syterkit)
#   BRANCH=edge   -> mainline U-Boot 2026.01 + mainline kernel 7.0 (sun55iw3)
case "${BRANCH}" in
	legacy)
		BOARDFAMILY="sun55iw3-syterkit"
		SRC_EXTLINUX="yes"
		SRC_CMDLINE="earlycon=uart8250,mmio32,0x02500000 clk_ignore_unused initcall_debug=0 console=ttyAS0,115200 loglevel=8 cma=64M init=/sbin/init"
		BOOTFS_TYPE="fat"
		BOOTSIZE="256"
		SERIALCON="ttyAS0"
		declare -g SYTERKIT_BOARD_ID="avaota-a1" # This _only_ used for syterkit-allwinner extension
		;;
	edge)
		BOARDFAMILY="sun55iw3"
		BOOTCONFIG="avaota-a1_defconfig"

		# Boot partition configuration (mainline U-Boot needs FAT boot + ext4 root)
		IMAGE_PARTITION_TABLE="msdos"
		BOOTFS_TYPE="fat"
		BOOTSTART="8192"
		BOOTSIZE="512"
		ROOTSTART="1056768"
		;;
esac

# Legacy-only: apply Allwinner boot blobs (SyterKit needs them)
function post_family_tweaks__avaota-a1() {
	[[ "${BRANCH}" != "legacy" ]] && return 0

	display_alert "Applying boot blobs"
	cp -v "$SRC/packages/blobs/sunxi/sun55iw3/bl31.bin" "$SDCARD/boot/bl31.bin"
	cp -v "$SRC/packages/blobs/sunxi/sun55iw3/scp.bin" "$SDCARD/boot/scp.bin"
	cp -v "$SRC/packages/blobs/sunxi/sun55iw3/splash.bin" "$SDCARD/boot/splash.bin"

	display_alert "Applying wifi firmware"
	pushd "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800D80" "aic8800d80" # use armbian-firmware
	popd
}

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

# AIC8800
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

# AIC8800 Wireless
function post_family_tweaks_bsp__aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d
	# Add wireless conf
	cat > "${destination}"/etc/modprobe.d/aic8800-avaota-a1.conf <<- EOT
	options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	options aic8800_bsp aic_fw_path=/lib/firmware/aic8800/SDIO/aic8800D80
	EOT
	# Add needed bluetooth modules
	cat > "${destination}"/etc/modules-load.d/aic8800-btlpm.conf <<- EOT
	hidp
	rfcomm
	bnep
	aic8800_btlpm_sdio
	EOT
	# Add AIC8800 Bluetooth Service and Script
	if [[ -d "$SRC/packages/bsp/aic8800" ]]; then
		install -d -m 0755 "${destination}/usr/bin"
		install -m 0755 "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}/usr/bin/aic-bluetooth"
		install -d -m 0755 "${destination}/usr/lib/systemd/system"
		install -m 0644 "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}/usr/lib/systemd/system/aic-bluetooth.service"
	else
		display_alert "$BOARD" "Skipping AIC8800 BT assets (packages/bsp/aic8800 not found)" "warn"
	fi
}

# Enable AIC8800 Bluetooth Service
function post_family_tweaks__enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	if chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service || chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	else
		display_alert "$BOARD" "aic-bluetooth.service not found in image; skipping enable" "warn"
	fi
}
