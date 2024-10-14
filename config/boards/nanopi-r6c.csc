# Rockchip RK3588S octa core 8GB RAM SoC eMMC 1x NVMe 1x USB3 1x USB2 1x 2.5GbE 1x GbE
BOARD_NAME="NanoPi R6C"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ColorfulRhino"
BOOTCONFIG="nanopi-r6c-rk3588s_defconfig" # Mainline defconfig, enables booting from NVMe
BOOT_SOC="rk3588"
KERNEL_TARGET="edge,current,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588s-nanopi-r6c.dtb"
BOOT_SCENARIO="spl-blobs"

function post_family_tweaks__nanopi_r6c_naming_audios() {
	display_alert "$BOARD" "Renaming NanoPi R6C HDMI audio interface to human-readable form" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"'
	EOF
}

function post_family_tweaks__nanopi_r6c_naming_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming NanoPi R6C network interfaces to 'wan' and 'lan'" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe1c0000.ethernet", NAME:="wan"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0003:31:00.0", NAME:="lan"
	EOF
}

# Mainline U-Boot
function post_family_config__nanopi_r6c_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
