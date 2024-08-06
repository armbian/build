# Allwinner Cortex-A55 octa core 2/4GB RAM SoC USB3 PCIE USB-C 2x GbE
BOARD_NAME="LonganPi 4B"
BOARDFAMILY="sun55iw3-syterkit"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="legacy"
BOOT_FDT_FILE="allwinner/sun55i-t527-longanpi-4b-pcie.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="earlycon=uart8250,mmio32,0x02500000 clk_ignore_unused initcall_debug=0 console=ttyAS0,115200 loglevel=8 cma=64M init=/sbin/init"
BOOTFS_TYPE="fat"
BOOTSIZE="256"
SERIALCON="ttyAS0"
declare -g SYTERKIT_BOARD_ID="longanpi-4b" # This _only_ used for syterkit-allwinner extension

function post_family_tweaks__longanpi-4b() {
	display_alert "Applying boot blobs"
	cp -v "$SRC/packages/blobs/sunxi/sun50iw3/bl31.bin" "$SDCARD/boot/bl31.bin"
	cp -v "$SRC/packages/blobs/sunxi/sun50iw3/scp.bin" "$SDCARD/boot/scp.bin"

	display_alert "Applying wifi firmware"
	pushd "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fmacfw_rf.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_adid.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_patch_table.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/aic_userconfig.txt" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fmacfw_rf_usb.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_adid_u03.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_patch_table_u03.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fmacfw.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fmacfw_usb.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_patch.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800/fw_patch_u03.bin" "$SDCARD/lib/firmware"
	ln -s "aic8800/SDIO/aic8800D80" "aic8800d80" # use armbian-firmware
	popd
}
