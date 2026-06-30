# Freescale / NXP iMx dual/quad core 1-2GB Gbe Wifi
BOARD_NAME="Udoo"
BOARD_VENDOR="seco"
BOARDFAMILY="imx6"
BOARD_MAINTAINER=""
INTRODUCED="2014"
BOOTCONFIG="udoo_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"

# --- u-boot bump: v2017.11 -> v2026.07-rc4 (pilot; builds on trixie, no distutils/SWIG break) ---
# imx6.conf pins udoo to v2017.11 in a `case $BOARD` sourced AFTER this file, so
# override in post_family_config. The legacy/u-boot-imx6 patchset is for v2017.11
# and will not apply, so point at a fresh (empty) patchdir.
function post_family_config__udoo_uboot_v2026() {
	display_alert "udoo" "u-boot bump v2017.11 -> v2026.07-rc4 (pilot)" "info"
	declare -g BOOTBRANCH="tag:v2026.07-rc4"
	declare -g BOOTPATCHDIR="v2026.07-imx6"
	# Modern udoo_defconfig is DM/OF_CONTROL -> SPL payload is u-boot-dtb.img.
	# Keep Armbian's raw-dd layout (SPL@1KiB, u-boot@69KiB); see the SPL raw-mode
	# override below.
	declare -g UBOOT_TARGET_MAP="SPL:SPL.sdhc u-boot-dtb.img:u-boot.img.sdhc"
}

# Upstream udoo_defconfig has SPL load u-boot-dtb.img from an EXT4 filesystem,
# but Armbian writes u-boot to a raw offset (69 KiB) via write_uboot_platform.
# Switch SPL to raw-sector load: SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR defaults to
# 0x8a (=sector 138 = 69 KiB) on MX6, matching the dd seek exactly.
function post_config_uboot_target__udoo_raw_spl() {
	display_alert "udoo" "SPL raw u-boot load @ sector 0x8a (69 KiB)" "info"
	run_host_command_logged scripts/config --disable CONFIG_SPL_FS_EXT4
	run_host_command_logged scripts/config --disable CONFIG_SPL_FS_FAT
	run_host_command_logged scripts/config --enable CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR
}
