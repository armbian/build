# Rockchip RK3566 quad core 4/8GB RAM SoC WIFI/BT eMMC USB2 USB3 NVMe PCIe GbE HDMI SPI
BOARD_NAME="orangepi3b"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-3b-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-orangepi-3b.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
MODULES="sprdbt_tty sprdwl_ng"
MODULES_BLACKLIST_LEGACY="bcmdhd"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__orangepi3b_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (Kwiboo's tree) u-boot overrides" "info"

	BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git"
	BOOTBRANCH="branch:rk3xxx-2024.04" # specific commit tested is commit:ccef7dfc453bc03c5b5c61fa67d2745b96fa7da6
	BOOTPATCHDIR="v2024.04-orangepi3b" # empty, patches are already in Kwiboo's branch:rk3xxx-2024.04

	BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

	BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin u-boot.itb idbloader.img idbloader-spi.img"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}

	# Smarter/faster/better to-spi writer using flashcp (hopefully with --partition), using the binman-provided 'u-boot-rockchip-spi.bin'
	function write_uboot_platform_mtd() {
		declare -a extra_opts_flashcp=("--verbose")
		if flashcp -h | grep -q -e '--partition'; then
			echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
			extra_opts_flashcp+=("--partition")
		else
			echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
		fi
		flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot-rockchip-spi.bin" /dev/mtd0
	}

}

function post_family_tweaks_bsp__orangepi3b() {
	display_alert "$BOARD" "Installing sprd-bluetooth.service" "info"

	# Bluetooth on orangepi3b board is handled by a Spreadtrum (sprd) chip and requires
	# a custom hciattach_opi binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/hciattach_opi $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/sprd-bluetooth.service $destination/lib/systemd/system/

	return 0
}

function post_family_tweaks__orangepi3b_enable_services() {
	display_alert "$BOARD" "Enabling sprd-bluetooth.service" "info"
	chroot_sdcard systemctl enable sprd-bluetooth.service
	return 0
}
