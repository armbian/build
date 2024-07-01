# Rockchip RK3588j Octa core 4GB-32GB eMMC GBE HDMI HDMI-IN PCIe SATA USB3 WiFi 4G 5G
BOARD_NAME="Firefly ITX-3588J"
BOARDFAMILY="rockchip-rk3588"
BOOT_SOC="rk3588"
BOARD_MAINTAINER=""
KERNEL_TARGET="vendor"
BOOTCONFIG="rk3588_defconfig"
BOOT_FDT_FILE="rockchip/rk3588-firefly-itx-3588j.dtb"
BOOT_LOGO="desktop"
FULL_DESKTOP="yes"
IMAGE_PARTITION_TABLE="gpt"

function post_family_tweaks_bsp__firefly_itx_3588j() {
	display_alert "$BOARD" "Installing rk3588-bluetooth.service" "info"

	# Bluetooth on this board is handled by a Broadcom (AP6275PR3) chip and requires
	# a custom brcm_patchram_plus binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/rk3588-bluetooth.service

	# Reuse the service file, ttyS0 -> ttyS6; BCM4345C5.hcd -> BCM4362A2.hcd
	sed -i 's/ttyS0/ttyS6/g' $destination/lib/systemd/system/rk3588-bluetooth.service
	sed -i 's/BCM4345C5.hcd/BCM4362A2.hcd/g' $destination/lib/systemd/system/rk3588-bluetooth.service
	return 0
}

function post_family_tweaks__firefly_itx_3588j_naming_audios() {
	display_alert "$BOARD" "Renaming firefly-itx-3588j audios" "info"
	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	return 0
}

function post_family_tweaks__firefly_itx_3588j_enable_services() {
	display_alert "$BOARD" "Enabling rk3588-bluetooth.service" "info"
	chroot_sdcard systemctl enable rk3588-bluetooth.service
	return 0
}

# Mainline U-Boot
function post_family_config__firefly_itx_3588j_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="generic-rk3588_defconfig"             # Use generic defconfig which should boot all RK3588 boards
	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2024.07-rc5"
	declare -g BOOTPATCHDIR="v2024.07/board_${BOARD}"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
