# Rockchip RK3588S octa core 4/8/16GB RAM SoC NVMe USB3 USB-C GbE
BOARD_NAME="Orange Pi 5"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="efectn"
BOOTCONFIG="orangepi-5-rk3588s_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOTCONFIG_SATA="orangepi-5-sata-rk3588s_defconfig"
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,edge"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-orangepi-5.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="orangepi-5" # This _only_ used for uefi-edk2-rk3588 extension

# @TODO: consider removing those, as the defaults in rockchip64_common have been bumped up
DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.15.bin'
BL31_BLOB='rk35/rk3588_bl31_v1.44.elf'

declare -g BLUETOOTH_HCIATTACH_PARAMS="-s 115200 /dev/ttyS9 bcm43xx 1500000" # For the bluetooth-hciattach extension
enable_extension "bluetooth-hciattach"                                       # Enable the bluetooth-hciattach extension

function post_family_tweaks_bsp__orangepi5_copy_usb2_service() {
	if [[ $BRANCH == "edge" ]]; then
		return
	fi

	display_alert "Installing BSP firmware and fixups"

	# Add USB2 init service. Otherwise, USB2 and TYPE-C won't work by default
	cp $SRC/packages/bsp/orangepi5/orangepi5-usb2-init.service $destination/lib/systemd/system/

	return 0
}

function post_family_tweaks__orangepi5_enable_usb2_service() {
	if [[ $BRANCH == "edge" ]]; then
		return
	fi

	display_alert "$BOARD" "Installing board tweaks" "info"

	# enable usb2 init service
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable orangepi5-usb2-init.service >/dev/null 2>&1"

	return 0
}

function post_family_tweaks__orangepi5_naming_audios() {
	if [[ $BRANCH == "edge" ]]; then
		return
	fi

	display_alert "$BOARD" "Renaming orangepi5 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_config__orangepi5_uboot_add_sata_target() {
	if [[ $BRANCH == "edge" ]]; then
		return
	fi

	display_alert "$BOARD" "Configuring ($BOARD) standard and sata uboot target map" "info"

	UBOOT_TARGET_MAP="
	BL31=$RKBIN_DIR/$BL31_BLOB $BOOTCONFIG spl/u-boot-spl.bin u-boot.dtb u-boot.itb;;idbloader.img u-boot.itb rkspi_loader.img
	BL31=$RKBIN_DIR/$BL31_BLOB $BOOTCONFIG_SATA spl/u-boot-spl.bin u-boot.dtb u-boot.itb;; rkspi_loader_sata.img
	"
}

function post_family_config_branch_edge__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} edge overrides" "info"
	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin u-boot.itb idbloader.img idbloader-spi.img"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}

	# Smarter/faster/better to-spi writer using flashcp (hopefully with --partition), using the binman-provided 'u-boot-rockchip-spi.bin'
	function write_uboot_platform_mtd() {
		declare -a extra_opts_flashcp=("--verbose")
		if flashcp -h | grep -q -e '--partition'; then
			echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
			extra_opts_flashcp+=("--partition")
		else
			echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
		fi
		flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}

function post_uboot_custom_postprocess__create_sata_spi_image() {
	if [[ $BRANCH == "edge" ]]; then
		return
	fi

	display_alert "$BOARD" "Create rkspi_loader_sata.img" "info"

	dd if=/dev/zero of=rkspi_loader_sata.img bs=1M count=0 seek=16
	/sbin/parted -s rkspi_loader_sata.img mklabel gpt
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart idbloader 64 7167
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart vnvm 7168 7679
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved_space 7680 8063
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved1 8064 8127
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart uboot_env 8128 8191
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved2 8192 16383
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart uboot 16384 32734
	dd if=idbloader.img of=rkspi_loader_sata.img seek=64 conv=notrunc
	dd if=u-boot.itb of=rkspi_loader_sata.img seek=16384 conv=notrunc
}

function post_family_config_branch_edge__orangepi5_use_mainline_uboot() {
	if [[ $BRANCH == "edge" ]]; then
		BOOTCONFIG="orangepi-5-rk3588s_defconfig"
		BOOTSOURCE="https://github.com/u-boot/u-boot.git"
		BOOTBRANCH="commit:2f0282922b2c458eea7f85c500a948a587437b63"
		BOOTDIR="u-boot-${BOARD}"
		BOOTPATCHDIR="v2024.01/board_${BOARD}"
	fi
}
