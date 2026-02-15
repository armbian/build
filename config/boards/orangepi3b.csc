# Rockchip RK3566 quad core 4/8GB RAM SoC WIFI/BT eMMC USB2 USB3 NVMe PCIe GbE HDMI SPI
BOARD_NAME="Orange Pi 3B"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-3b-rk3566_defconfig"
BOOTCONFIG_SATA="orangepi-3b-sata-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="vendor,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="binman"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__orangepi3b_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDELAY=1

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} $BOOTCONFIG_SATA;;u-boot-rockchip-spi-sata.bin
	BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} $BOOTCONFIG;;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
}

function pre_config_uboot_target__orangepi3b_patch_uboot_bootconfig_hack_for_sata() {
	display_alert "u-boot for ${BOARD}" "u-boot: hack bootconfig for sata spi image" "info"

	if [[ $target_make == *"orangepi-3b-sata-rk3566_defconfig"* ]]; then
		cp configs/orangepi-3b-rk3566_defconfig configs/orangepi-3b-sata-rk3566_defconfig
		echo "CONFIG_DWC_AHCI=y" >> configs/orangepi-3b-sata-rk3566_defconfig

		BOOTCONFIG="orangepi-3b-sata-rk3566_defconfig"
		target_make=${target_make/orangepi-3b-sata-rk3566_defconfig/}
	else
		BOOTCONFIG="orangepi-3b-rk3566_defconfig"
		target_make=${target_make/orangepi-3b-rk3566_defconfig/}
	fi
}

function post_config_uboot_target__orangepi3b_keep_sata_bootconfig() {
	display_alert "u-boot for ${BOARD}" "u-boot: hack bootconfig for sata spi image" "info"

	if [[ $BOOTCONFIG == "orangepi-3b-sata-rk3566_defconfig" ]]; then
		cp .config "${uboottempdir}/.config.sata"
	fi
}

function pre_package_uboot_image__orangepi3b_copy_sataconfig_to_package() {
	if [[ -f "${uboottempdir}/.config.sata" ]]; then
		run_host_command_logged cp "${uboottempdir}/.config.sata" "$uboottempdir/usr/lib/u-boot/orangepi-3b-sata-rk3566_defconfig"
		run_host_command_logged rm "${uboottempdir}/.config.sata"
	fi
}

function post_family_tweaks_bsp__orangepi3b() {
	display_alert "$BOARD" "Installing orangepi3b-sprd-bluetooth.service" "info"

	# Bluetooth on orangepi3b board is handled by a Spreadtrum (sprd) chip and requires
	# a custom hciattach_opi binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/hciattach_opi $destination/usr/bin
	install -m 755 $SRC/packages/bsp/orangepi3b/orangepi3b-sprd-bluetooth $destination/usr/bin/
	cp $SRC/packages/bsp/orangepi3b/orangepi3b-sprd-bluetooth.service $destination/lib/systemd/system/

	return 0
}

function post_family_tweaks__orangepi3b_enable_services() {
	display_alert "$BOARD" "Enabling orangepi3b-sprd-bluetooth.service" "info"
	chroot_sdcard systemctl enable orangepi3b-sprd-bluetooth.service
	return 0
}

function post_family_tweaks__orangepi3b_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi3b audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi-sound", ENV{SOUND_DESCRIPTION}="HDMI Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-rk809-sound", ENV{SOUND_DESCRIPTION}="RK809 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules # vendor dts
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-sound", ENV{SOUND_DESCRIPTION}="RK809 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules       # mainline dts

	return 0
}
