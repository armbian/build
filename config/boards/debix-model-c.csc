# NXP i.MX93 dual Cortex-A55 SoC, 1/2GB LPDDR4X, 2x GbE (EQoS TSN + FEC), Wi-Fi/BT, 2x USB2 + OTG, LVDS, Ethos-U65 NPU, 8MB NOR
BOARD_NAME="DEBIX Model C"
BOARD_VENDOR="polyhex"
BOARDFAMILY="imx93"
BOARD_MAINTAINER="HeyMeco"
INTRODUCED="2023"
HAS_VIDEO_OUTPUT="no" # LVDS only, no panel described yet

KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyLP0"
BOOT_FDT_FILE="freescale/imx93-debix-model-c.dtb"
OVERLAY_PREFIX="imx93-debix-model-c"

BOOTBRANCH="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOTCONFIG="imx93_debix_model_c_defconfig"

UBOOT_TARGET_MAP=";;flash.bin flash-spi.bin"

# FlexSPI NOR boot image: FCB at 0x400, flash.bin at 0x1000. FCB values match the vendor image.
function post_uboot_custom_postprocess__debix_model_c_flash_spi() {
	display_alert "${BOARD}" "Building FlexSPI NOR image flash-spi.bin" "info"
	local fcb="fspi-fcb.bin"
	head -c 512 /dev/zero > "${fcb}"
	# put <offset> <bytes>
	put() { printf "$2" | dd of="${fcb}" bs=1 seek=$(($1)) conv=notrunc status=none; }
	put 0x000 'FCFB\x00\x00\x01\x56'              # tag, version 1.0.0
	put 0x00c '\x00\x03\x03\x00'                  # loopback read sample clock, CS hold/setup 3
	put 0x044 '\x01\x01\x02\x00'                  # serial NOR, 1 pad, 60 MHz
	put 0x050 '\x00\x00\x00\x10'                  # flash A1 size
	put 0x080 '\x0b\x04\x18\x08\x08\x30\x04\x24'  # LUT read: 0x0B, 24-bit address, 8 dummy, read
	put 0x1c0 '\x00\x01\x00\x00\x00\x10\x00\x00'  # page 256 B, sector 4 KiB
	{
		head -c 1024 /dev/zero | LC_ALL=C tr '\0' '\377'
		cat "${fcb}"
		head -c 2560 /dev/zero | LC_ALL=C tr '\0' '\377'
		cat flash.bin
	} > flash-spi.bin
}

write_uboot_platform_mtd() {
	dd if="$1/flash-spi.bin" of="$2" bs=4K conv=fsync status=none >> "${3:-/dev/null}" 2>&1
}

# NXP IW416 Wi-Fi/BT module. The minimal armbian-firmware package does not ship its firmware.
# mwifiex loads the SDIO-UART combo image, which also starts Bluetooth.
function post_family_tweaks__debix_model_c_iw416_firmware() {
	local fw="${SDCARD}/lib/firmware/mrvl/sdiouartiw416_combo_v0.bin"

	display_alert "${BOARD}" "Installing NXP IW416 firmware" "info"
	mkdir -p "${fw%/*}"
	curl -fsSL -o "${fw}" "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/20261019/mrvl/sdiouartiw416_combo_v0.bin" ||
		exit_with_error "Download of IW416 firmware failed"
	echo "afcca1b8c240a97b9c452ef8023a829c1942127072907efe34c25bfabb2ba7f9  ${fw}" | sha256sum -c - ||
		exit_with_error "IW416 firmware checksum mismatch"
}

# btnxpuart must probe after mwifiex started the combo firmware. Else it waits for a BT bootloader that never answers.
# mwifiex names its interface mlan0. Rename it to wlan0: armbian-config detects Wi-Fi by the w* name.
function post_family_tweaks_bsp__debix_model_c_iw416() {
	mkdir -p "${destination}/etc/modprobe.d" "${destination}/etc/udev/rules.d" "${destination}/etc/systemd/network"
	cat > "${destination}/etc/systemd/network/10-debix-model-c-wlan.link" <<- 'EOF'
		[Match]
		OriginalName=mlan*
		Driver=mwifiex_sdio

		[Link]
		Name=wlan0
	EOF
	cat > "${destination}/etc/modprobe.d/debix-model-c-bt.conf" <<- 'EOF'
		# Loaded by 90-debix-model-c-bt.rules after the Wi-Fi firmware is active
		blacklist btnxpuart
	EOF
	cat > "${destination}/etc/udev/rules.d/90-debix-model-c-bt.rules" <<- 'EOF'
		# mwifiex adds its network interface after the IW416 combo firmware is active
		ACTION=="add", SUBSYSTEM=="net", DRIVERS=="mwifiex_sdio", RUN+="/sbin/modprobe btnxpuart"
	EOF
}
