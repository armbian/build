# Rockchip RK3588j Octa core 4GB-32GB eMMC GBE HDMI HDMI-IN PCIe SATA USB3 WiFi 4G 5G
BOARD_NAME="Firefly ITX-3588J"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="SeeleVolleri"
KERNEL_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-firefly-itx-3588j.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS02,1500000 console=tty0"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__firefly-itx-3588j_use_vendor_uboot() {
	BOOTCONFIG="rk3588_defconfig"
	BOOTSOURCE='https://github.com/150balbes/u-boot-rk'
	BOOTBRANCH='branch:rk3588'
	BOOTDIR="u-boot-${BOARD}"
	BOOTPATCHDIR="u-boot-firefly-itx-3588j"
}

function post_family_tweaks_bsp__firefly-itx-3588j() {
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

function post_family_tweaks__firefly-itx-3588j_enable_services() {
	display_alert "$BOARD" "Enabling rk3588-bluetooth.service" "info"
	chroot_sdcard systemctl enable rk3588-bluetooth.service
	return 0
}
