# Rockchip RK3566 quad core
BOARD_NAME="Radxa ZERO 3"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="radxa-zero3-rk3566_defconfig"
KERNEL_TARGET="vendor,current,edge"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-radxa-zero3.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat" # Only for vendor/legacy
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_config__use_mainline_uboot_except_vendor() {
	# use mainline u-boot for _current_ and _edge_
	if [[ "$BRANCH" != "current" && "$BRANCH" != "edge" ]]; then
    	return 0
	fi
	unset BOOT_FDT_FILE # boot.scr will use whatever u-boot detects and sets 'fdtfile' to
	unset BOOTFS_TYPE   # mainline u-boot can boot ext4 directly
	BOOTCONFIG="radxa-zero-3-rk3566_defconfig"
	BOOTSOURCE="https://github.com/u-boot/u-boot"
	BOOTBRANCH="tag:v2025.04"
	BOOTPATCHDIR="v2025.04"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config_branch_vendor__radxa-zero3_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/radxa/u-boot.git'
	BOOTBRANCH='branch:rk35xx-2024.01'
	BOOTPATCHDIR="u-boot-radxa-latest"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

# AIC8800 Wireless
function post_family_tweaks_bsp__aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d
	# Add udev rule
	cat <<EOF > "${destination}"/etc/modprobe.d/aic8800-wireless.conf
options aic8800_fdrv aicwf_dbg_level=0 custregd=0 ps_on=0
options aic8800_bsp aic_fw_path=/lib/firmware/aic8800_sdio
EOF
	# Add needed bluetooth modules
	cat <<EOF > "${destination}"/etc/modules-load.d/aic8800-btlpm.conf
hidp
rfcomm
bnep
aic8800_btlpm
EOF
	if [[ -d "$SRC/packages/bsp/aic8800" ]]; then
		mkdir -p "${destination}"/etc/systemd/system
		mkdir -p "${destination}"/usr/bin
		cp -f "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}"/usr/bin
		chmod +x "${destination}"/usr/bin/aic-bluetooth
		cp -f "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}"/etc/systemd/system
	fi
}

# Enable AIC8800 Bluetooth Service
function post_family_tweaks__enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
}
