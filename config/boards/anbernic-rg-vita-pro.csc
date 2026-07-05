# Rockchip RK3576 (4xA72+4xA53) gaming handheld: 5.5" 1080x1920 TDDI touch LCD,
# Mali-G52 MC3, SPI-MCU gamepad, eMMC/microSD, WiFi/BT, USB-C (USB3/DP/PD), HDMI
BOARD_NAME="Anbernic RG Vita Pro"
BOARD_VENDOR="Anbernic"
BOARDFAMILY="rk35xx"
BOOTCONFIG="generic-rk3576_defconfig"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

# Dependencies of the board helpers (vita-pad2key, vita-jack-switch, vita-screen)
PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev xinput alsa-utils"

BOOT_FDT_FILE="rockchip/rk3576-anbernic-rg-vita-pro.dtb"
BOOT_SCENARIO="spl-blobs"
SERIALCON="ttyS0" # DTS chosen: serial0 (uart0) @ 1500000n8
IMAGE_PARTITION_TABLE="gpt"

# The vendor image ships DDR fw v1.09; the family default (v1.08) does not
# initialize this board's RAM, so pin v1.09.
DDR_BLOB="rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.09.bin"

# No USB-gadget serial console on purpose: a getty holding /dev/ttyGS0 open
# blocks dwc3's device->host role switch, breaking USB host on the Type-C port.

# Default mixer state captured on hardware: speakers and headphone jack both
# enabled out of the box.
ASOUND_STATE="asound.state.anbernic-rg-vita-pro"

# Mainline U-Boot with the generic RK3576 defconfig. The family's
# boot_merger/spl-blobs path supplies BL31, usbplug and the SD-card boost the
# RK3576 BootROM needs to boot from SD. Mirrors nanopi-r76s.
function post_family_config__anbernic_rg_vita_pro_use_mainline_uboot() {
	display_alert "$BOARD" "mainline U-Boot v2026.04 (generic-rk3576) for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.04"
	declare -g BOOTPATCHDIR="v2026.04"

	# boot_merger (uboot_custom_postprocess) injects the rk3576 SD boost;
	# binman's u-boot-rockchip.bin lacks it, so emit idbloader.img + u-boot.itb
	# and let the family postprocess assemble the loader.
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;idbloader.img u-boot.itb"

	unset write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/idbloader.img" "of=$2" seek=64    conv=notrunc status=none
		dd "if=$1/u-boot.itb"    "of=$2" seek=16384 conv=notrunc status=none
	}
}

# Headphone-jack speaker switch + gamepad-to-keyboard services (bsp-cli
# payloads) + KWin GLES env.
function post_family_tweaks__anbernic_rg_vita_pro_helpers() {
	display_alert "$BOARD" "enabling vita-jack-switch + vita-pad2key + KWin GLES env" "info"
	mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/vita-jack-switch.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/vita-jack-switch.service"
	ln -sf /etc/systemd/system/vita-pad2key.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/vita-pad2key.service"
	ln -sf /etc/systemd/system/vita-offcharge.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/vita-offcharge.service"
	mkdir -p "${SDCARD}/etc/systemd/system/reboot.target.wants"
	ln -sf /etc/systemd/system/vita-offcharge-reboot-marker.service \
		"${SDCARD}/etc/systemd/system/reboot.target.wants/vita-offcharge-reboot-marker.service"

	# KWin needs a GLES context on panfrost; with desktop GL the Plasma
	# Mobile shell's legacy GL calls fail and the task switcher livelocks.
	grep -q '^KWIN_COMPOSE=' "${SDCARD}/etc/environment" 2>/dev/null || \
		echo 'KWIN_COMPOSE=O2ES' >> "${SDCARD}/etc/environment"
}

# Upstream Linux DTS aliases: mmc0 = &sdhci (eMMC), mmc1 = &sdmmc (SD),
# mmc2 = &sdio. Boot SD first so a flashed card takes precedence over eMMC.
function pre_config_uboot_target__anbernic_rg_vita_pro_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "mmc0" "nvme" "usb" "pxe" "dhcp")
	display_alert "u-boot for ${BOARD}/${BRANCH}" "boot order '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}
