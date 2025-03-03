# Rockchip RK3588s SoC octa core 4-16GB SoC eMMC USB3 NvME
BOARD_NAME="Odroid M2"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="mlegenovic"
BOOT_SOC="rk3588"
KERNEL_TARGET="edge"
BOOT_FDT_FILE="rockchip/rk3588s-odroid-m2.dtb"
BOOT_SCENARIO="binman"
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="no"
BOOT_LOGO="yes"

BOOTBRANCH_BOARD="tag:v2025.04-rc2"
BOOTBRANCH="${BOOTBRANCH_BOARD}"
BOOTPATCHDIR="v2025.04-rc2"

BOOTCONFIG="odroid-m2-rk3588s_defconfig"
BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

OVERLAY_PREFIX='rockchip-rk3588'

function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/$BL31_BLOB ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}
}

# "rockchip-common: boot SD card first, then NVMe, then SATA, then USB, then mmc"
# On odroidm2, mmc0 is the eMMC, mmc1 is the SD card slot
function pre_config_uboot_target__odroidm2_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "mmc0" "usb" "pxe" "dhcp") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

# add a network rule to rename default name
function post_family_tweaks__odroidm2_rename_gmac_eth0() {
	display_alert "Creating network rename rule for Odroid M2"
	mkdir -p "${SDCARD}"/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}"/etc/udev/rules.d/70-rename-lan.rules
		SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", KERNEL=="end*", NAME="eth0"
	EOF

}
