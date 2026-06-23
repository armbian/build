# RK3568 quad-core dual 4" 640x480 MIPI-DSI eMMC/MicroSD WiFi/BT 2xUSB-C
BOARD_NAME="Anbernic RG DS"
BOARD_VENDOR="Anbernic"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3568"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2025"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev xinput"

# Load the USB serial gadget at boot so the ttyGS0 console (OTG port) exists.
# The shared kernel ships USB_G_SERIAL as a module, so the board loads it here.
MODULES="g_serial"

BOOT_FDT_FILE="rockchip/rk3568-anbernic-rg-ds.dtb"
BOOT_SCENARIO="spl-blobs"
SERIALCON="ttyS2" # RG DS serial console: ttyS2 @ 1500000
BOOTFS_TYPE="fat"
IMAGE_PARTITION_TABLE="gpt"

# rk3568 DDR v1.23 / BL31 v1.45 (matches the ROCKNIX-proven bootloader on this
# board). Fetched from armbian/rkbin at build time; no binaries committed here.
BL31_BLOB="rk35/rk3568_bl31_v1.45.elf"
DDR_BLOB="rk35/rk3568_ddr_1056MHz_v1.23.bin"

# Mainline U-Boot (quartz64-a-rk3566 defconfig + rk3568 DDR v1.23 / BL31 v1.45)
function post_family_config__anbernic_rg_ds_mainline_uboot() {
	display_alert "$BOARD" "mainline U-Boot v2026.01 (quartz64-a-rk3566 + rk3568 DDR v1.23)" "info"
	declare -g BOOTCONFIG="quartz64-a-rk3566_defconfig"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# Board helper payloads (dual-screen layout, gamepad-to-keyboard remap, the
# desktop toggle/launcher, polkit rule and controls README) ship as real files
# under config/optional/boards/anbernic-rg-ds/_packages/bsp-cli/ and are baked
# into the board bsp package. Here we only wire up what needs activation:
#   - ttyGS0 getty: USB-C gadget serial console (no accessible physical UART)
#   - rgds-pad2key.service: gamepad D-pad/buttons -> keyboard (evdev/uinput)
# The X11 dual-screen helper needs no enabling - it is an xdg autostart entry
# that self-guards to X11 sessions (see usr/bin/rgds-screen).
function post_family_tweaks__anbernic_rg_ds_enable_helpers() {
	display_alert "$BOARD" "enabling ttyGS0 console + gamepad-to-keyboard" "info"

	# USB-gadget serial console login on the OTG port
	mkdir -p "${SDCARD}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/serial-getty@.service \
		"${SDCARD}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

	# Gamepad-to-keyboard remap (unit file shipped via bsp-cli)
	mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/rgds-pad2key.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rgds-pad2key.service"
}
