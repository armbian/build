# Rockchip RK3588 SoC octa core Jetson SoM
declare -g BOARD_NAME="Mixtile Core3588E"
declare -g BOARD_VENDOR="mixtile"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g KERNEL_TARGET="edge,vendor"
declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-core3588e.dtb" # same name vendor and edge
declare -g BOOT_SCENARIO="spl-blobs"
declare -g BOOT_SOC="rk3588"
declare -g BOOTCONFIG="mixtile-core3588e-rk3588_defconfig" # vendor name
declare -g IMAGE_PARTITION_TABLE="gpt"
# Does NOT have a UEFI_EDK2_BOARD_ID

# Vendor kernel:
# - https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr5.1/arch/arm64/boot/dts/rockchip/rk3588-mixtile-core3588e.dts
#   - mostly works, still sucks as it's vendor kernel
#   - mainline u-boot can boot the vendor kernel just fine
# Mainline kernel:
# - https://github.com/Joshua-Riek/linux/blob/v6.7-rk3588/arch/arm64/boot/dts/rockchip/rk3588-mixtile-core3588e.dts
#   - a _lot_ of fixes and additions done on top; gpu/npu/i2c/thermals/etc

# Hardware notes:
# - With the LEETOP carrier board (as shipped by Mixtile)
#   - Recovery "button" (NOT real "Maskrom"): "jumper cap to connect the FCREC and GND pins"; this depends on u-boot actually working (not bricked)
#   - OTG/Maskrom port is micro-USB port
#   - The "real" maskrom is to short two tiny solder-joints near the SoC on the SoM; see https://dh19rycdk230a.cloudfront.net/app/uploads/2023/11/solder-joints.png

# Vendor u-boot; use the default family (rockchip-rk3588) u-boot. See config/sources/families/rockchip-rk3588.conf
function post_family_config__vendor_uboot_core3588e() {
	if [[ "${BRANCH}" == "vendor" || "${BRANCH}" == "legacy" ]]; then
		display_alert "$BOARD" "Using vendor u-boot for $BOARD on branch $BRANCH" "info"
	else
		return 0
	fi

	display_alert "$BOARD" "Configuring $BOARD vendor u-boot (using Radxa's older next-dev-v2024.03)" "info"
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing

	# Override the stuff from rockchip-rk3588 family; a patch for stable MAC address that breaks with Radxa's next-dev-v2024.10+
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH='branch:next-dev-v2024.03'     # NOT next-dev-v2024.10
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx" # Patches from https://github.com/Joshua-Riek/ubuntu-rockchip/blob/main/packages/u-boot-radxa-rk3588/debian/patches/0002-board-rockchip-Add-the-Mixtile-Core-3588E.patch
}

function post_family_config__core3588e_use_mainline_uboot() {
	if [[ "${BRANCH}" != "edge" ]]; then
		return 0
	fi

	display_alert "$BOARD" "mainline (generic) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="generic-rk3588_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01-rc4"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}"

	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin" # NOT u-boot-rockchip-spi.bin
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd                                 # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
}
