# Rockchip RK3399 hexa core 2GB/4GB RAM SoC GBE eMMC USB3 USB-C WiFi/BT
BOARD_NAME="NanoPi M4"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rockchip64" # Used to be rk3399
BOARD_MAINTAINER=""
INTRODUCED="2018"
BOOTCONFIG="nanopi-m4-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.rt5651"
BOOT_LOGO="desktop"
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOT_SCENARIO="binman-atf-mainline"
# DDR blob: family default v1.25. With v1.30, 6 of 20 M4 cold boots corrupted memory.

function post_family_config__nanopim4_atf() {
	display_alert "$BOARD" "u-boot: TF-A lts-v2.14.11" "info"
	declare -g ATFSOURCE="https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git"
	declare -g ATFBRANCH="tag:lts-v2.14.11"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.14"
}

# The DDR blob as TPL detects the RAM size, so one image boots 2 GB and 4 GB units.
function post_config_uboot_target__nanopim4_features() {
	display_alert "$BOARD" "u-boot: enable network boot, storage and debug commands" "info"
	local opt
	for opt in ROCKCHIP_EXTERNAL_TPL \
		CMD_DHCP CMD_PING CMD_PXE CMD_TFTPBOOT CMD_NFS CMD_WGET CMD_DNS \
		ROCKCHIP_EFUSE MISC_INIT_R CMD_PCI CMD_NVME CMD_SCSI CMD_EXT4_WRITE FAT_WRITE \
		CMD_GPIO CMD_I2C CMD_PMIC CMD_REGULATOR CMD_POWEROFF \
		DM_RNG RNG_ROCKCHIP CMD_RNG CMD_KASLRSEED CMD_HASH CMD_BOOTMENU CMD_EFICONFIG; do
		run_host_command_logged scripts/config --enable "CONFIG_${opt}"
	done
}

function post_family_tweaks__m4() {
	display_alert "$BOARD" "Installing board tweaks" "info"

	# enable fan support
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable nanopim4-pwm-fan.service >/dev/null 2>&1"

	return 0
}

function post_family_tweaks_bsp__M4() {
	display_alert "Installing BSP firmware and fixups"

	# No brcm_patchram service: the kernel's hci_uart driver loads the BCM4356A2 firmware.

	# Fan support
	cp $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.service $destination/lib/systemd/system/
	install -m 755 $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.sh $destination/usr/bin/nanopim4-pwm-fan.sh

	return 0
}
