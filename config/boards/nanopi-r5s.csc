# Rockchip RK3568 quad core 4GB RAM eMMC NVMe 2x USB3 1x GbE 2x 2.5GbE
BOARD_NAME="NanoPi R5S"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="utlark"
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3568-nanopi-r5s.dtb"
SRC_EXTLINUX="no"
ASOUND_STATE="asound.state.station-m2" # TODO verify me
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2024.04"
BOOTPATCHDIR="v2024.04"
BOOTCONFIG="nanopi-r5s-rk3568_defconfig"

OVERLAY_PREFIX="rockchip-rk3568"
DEFAULT_OVERLAYS="nanopi-r5s-leds"

function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=2 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}

function post_family_tweaks__nanopir5s_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces WAN LAN1 LAN2" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe2a0000.ethernet", NAME:="wan"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:01:00.0", NAME:="lan1"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0001:01:00.0", NAME:="lan2"
	EOF
}

# We've an overlay (DEFAULT_OVERLAYS="nanopi-r5s-leds") to drive the LEDs. Disable armbian-led-state service.
function pre_customize_image__nanopi-r5s_leds_kernel_only() {
	display_alert "$BOARD" "Disabling armbian-led-state service since we have DEFAULT_OVERLAYS='${DEFAULT_OVERLAYS}'" "info"
	chroot_sdcard systemctl --no-reload disable armbian-led-state
}

# For UMS/RockUSB to work in u-boot, &usb_host0_xhci { dr_mode = "otg" } is required. See 0002-usb-otg-mode.patch
# Attention: the Power USB-C port is NOT the OTG port; instead, the USB-A closest to the edge is the OTG port.
function post_config_uboot_target__extra_configs_for_nanopi-r5s() {
	display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & flash all LEDs and do PCI/NVMe enumeration in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led led-power on; led led-lan1 on; led led-lan2 on; led led-wan on; pci enum; nvme scan; led led-lan1 off; led led-lan2 off; led led-wan off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable ${config}" "info"
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT

}
