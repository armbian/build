# Rockchip RK3568 quad core 4GB RAM eMMC NVMe 2x USB3 1x GbE 2x 2.5GbE
BOARD_NAME="NanoPi R5S"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="utlark"
INTRODUCED="2022"
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="rockchip/rk3568-nanopi-r5s.dtb"
SRC_EXTLINUX="no"
ASOUND_STATE="asound.state.station-m2" # TODO verify me
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2026.07"
BOOTPATCHDIR="v2026.07"
BOOTCONFIG="nanopi-r5s-rk3568_defconfig"

OVERLAY_PREFIX="rockchip-rk3568"
DEFAULT_OVERLAYS="nanopi-r5s-leds"

function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=2 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}

function post_family_tweaks__nanopir5s_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces WAN1 LAN1 LAN2" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe2a0000.ethernet", NAME:="wan1"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:01:00.0", NAME:="lan1"
		        SUBSYSTEM=="net", ACTION=="add", KERNELS=="0001:11:00.0", NAME:="lan2"
	EOF
}

# We've an overlay (DEFAULT_OVERLAYS="nanopi-r5s-leds") to drive the LEDs. Disable armbian-led-state service.
function pre_customize_image__nanopi-r5s_leds_kernel_only() {
	display_alert "$BOARD" "Disabling armbian-led-state service since we have DEFAULT_OVERLAYS='${DEFAULT_OVERLAYS}'" "info"
	chroot_sdcard systemctl --no-reload disable armbian-led-state
}

# Attention: the Power USB-C port is NOT the OTG port; instead, the USB-A closest to the edge is the OTG port.
function pre_config_uboot_target__nanopir5s_patch_uboot_dtsi_for_ums() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	# Append to the u-boot dtsi file with stuff for enabling gadget/otg/peripheral mode
	cat <<- EOD >> arch/arm/dts/rk3568-nanopi-r5s-u-boot.dtsi
		&usb_host0_xhci { dr_mode = "otg"; };
	EOD
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
function pre_config_uboot_target__nanopir5s_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "usb" "mmc0" "scsi" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_config_uboot_target__extra_configs_for_nanopir5s_mainline() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led led-power on; led led-lan1 on; led led-lan2 on; led led-wan on; pci enum; nvme scan; led led-lan1 off; led led-lan2 off; led led-wan off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable EFI debugging commands" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more filesystems support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable LWIP (new networking stack)" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MII
	run_host_command_logged scripts/config --enable CONFIG_NET_LWIP

	# UMS, RockUSB, gadget stuff
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable UMS/RockUSB gadget" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}
