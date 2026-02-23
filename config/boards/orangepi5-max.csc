# Rockchip RK3588 octa core 4/8/16GB RAM SoC SPI NVMe 2x USB2 2x USB3 2x HDMI
BOARD_NAME="Orange Pi 5 Max"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-5-max-rk3588_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,current,edge"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-orangepi-5-max.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
enable_extension "bcmdhd"
BCMDHD_TYPE="sdio"

# Mainline U-Boot for edge kernel
function post_family_config_branch_edge__orangepi5max_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	unset BOOT_FDT_FILE
	declare -g BOOTCONFIG="orangepi-5-max-rk3588_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.04"
	declare -g BOOTPATCHDIR="v2025.04"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	function write_uboot_platform_mtd() {
		flashcp -v -p "$1/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}

function post_family_tweaks__orangepi5max_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi5max audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI1 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_tweaks_bsp__orangepi5max_bluetooth() {
	display_alert "$BOARD" "Installing ap6611s-bluetooth.service and udev rules" "info"

	# Bluetooth on this board is handled by a Broadcom (AP6611S) chip and requires
	# a custom brcm_patchram_plus binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/ap6611s-bluetooth.service

	# Reuse the service file, ttyS0 -> ttyS7; BCM4345C5.hcd -> SYN43711A0.hcd
	sed -i 's/ttyS0/ttyS7/g' $destination/lib/systemd/system/ap6611s-bluetooth.service
	sed -i 's/BCM4345C5.hcd/SYN43711A0.hcd/g' $destination/lib/systemd/system/ap6611s-bluetooth.service

	# Bind UART Bluetooth service lifecycle to rfkill events.
	# This prevents firmware loss by dynamically reloading patchram upon rfkill unblock.
	mkdir -p $destination/etc/udev/rules.d/
	cat <<-EOF > $destination/etc/udev/rules.d/99-ap6611s-bluetooth.rules
		# Stop service on rfkill block
		ACTION=="add|change", SUBSYSTEM=="rfkill", ENV{RFKILL_NAME}=="bt_default", ENV{RFKILL_TYPE}=="bluetooth", ENV{RFKILL_STATE}=="0", RUN+="/usr/bin/systemctl stop --no-block ap6611s-bluetooth.service"
		# Restart service to reload firmware on rfkill unblock
		ACTION=="add|change", SUBSYSTEM=="rfkill", ENV{RFKILL_NAME}=="bt_default", ENV{RFKILL_TYPE}=="bluetooth", ENV{RFKILL_STATE}=="1", RUN+="/bin/sh -c 'sleep 2 && systemctl restart --no-block ap6611s-bluetooth.service'"
	EOF

	return 0
}
