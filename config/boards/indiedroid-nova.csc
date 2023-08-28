# Rockchip RK3588S octa core 4/8/16GB RAM SoC eMMC USB3 USB-C GbE
declare -g BOARD_NAME="Indiedroid Nova"
declare -g BOARD_MAINTAINER="lanefu"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOOTCONFIG="indiedroid_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
declare -g BOOT_SOC="rk3588"
declare -g KERNEL_TARGET="legacy,collabora,edge"
declare -g FULL_DESKTOP="yes"
declare -g BOOT_LOGO="desktop"
declare -g BOOT_FDT_FILE="rockchip/rk3588s-indiedroid-nova.dtb"
declare -g BOOT_SCENARIO="spl-blobs"
declare -g BOOT_SUPPORT_SPI="no"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g SKIP_BOOTSPLASH="yes" # Skip boot splash patch, conflicts with CONFIG_VT=yes
declare -g BOOTFS_TYPE="fat"
declare -g SRC_EXTLINUX="no" # going back to standard uboot for now
declare -g BL31_BLOB='rk35/rk3588_bl31_v1.38.elf'
declare -g DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.11.bin'

## only applies to extlinux so not used
declare -g SRC_CMDLINE="console=ttyS0,115200n8 console=tty1 console=both net.ifnames=0 rootflags=data=writeback"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__indiedroid-nova_use_stvhay_uboot() {
	declare -g BOOTSOURCE='https://github.com/stvhay/u-boot.git'
	declare -g BOOTBRANCH='branch:rockchip-rk3588-unified'
	declare -g BOOTPATCHDIR="legacy"
}

# BSP kernel uses device name from contract manufacturer rather than production name in mainline
function post_family_config_branch_legacy__use_9tripod_dtb() {
	declare -g BOOT_FDT_FILE="rockchip/rk3588s-9tripod-linux.dtb"
}

# Add bluetooth packages to the image (not rootfs cache)
function post_family_config__bluetooth_hciattach_add_bluetooth_packages() {
	display_alert "${BOARD}" "adding bluetooth packages to image" "info"
	add_packages_to_image rfkill bluetooth bluez bluez-tools
}

# setup bluetooth stuff
function pre_customize_image__indiedroid_add_bluetooth() {
	display_alert "${BOARD}" "install bluetooth firmware" "info"
	local TMPDIR

	# Build firmware
	TMPDIR=$(mktemp -d)
	pushd "${TMPDIR}" || exit 1
	git clone https://github.com/stvhay/rkwifibt || exit 1
	cd rkwifibt || exit 1
	make -C realtek/rtk_hciattach || exit 1
	# Install the firmware and utility
	mkdir -p "${SDCARD}/lib/firmware/rtl_bt"
	cp -fr realtek/RTL8821CS/* "${SDCARD}/lib/firmware/rtl_bt/"
	cp -f realtek/rtk_hciattach/rtk_hciattach "${SDCARD}/usr/bin/"
	cp -f bt_load_rtk_firmware "${SDCARD}/usr/bin/"
	chroot_sdcard chmod +x /usr/bin/{rtk_hciattach,bt_load_rtk_firmware}
	echo hci_uart >> "${SDCARD}/etc/modules"
	popd || exit 1

	#TODO this should probably be replaced with the existing extensions/bluetooth-hciattach.sh

	display_alert "${BOARD}" "setup bluetooth service" "info"
	# Systemd service
	cat > "${SDCARD}/etc/systemd/system/bluetooth-rtl8821cs.service" <<- EOD
		[Unit]
		Description=RTL8821CS Firmware Service
		After=network.target

		[Service]
		Type=oneshot
		Environment=BT_TTY_DEV=/dev/ttyS9
		ExecStart=/usr/bin/bt_load_rtk_firmware
		RemainAfterExit=true
		StandardOutput=journal

		[Install]
		WantedBy=multi-user.target
	EOD
	chroot_sdcard systemctl enable bluetooth-rtl8821cs.service
}
function post_family_tweaks__indiedroid_naming_audios() {
	display_alert "$BOARD" "Renaming indiedroid audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
