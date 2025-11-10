# Mediatek MT7988a quad core Cortex-A73 4/8GB RAM 8GB EMMC mPci USB3.0 4xGBE
BOARD_NAME="Banana Pi R4"
BOARDFAMILY="filogic"
BOARD_MAINTAINER=""
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOTCONFIG="mt7988a_bananapi_bpi-r4-sdmmc_defconfig"
BOOT_FDT_FILE="mediatek/mt7988a-bananapi-bpi-r4-sd.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n1 earlyprintk loglevel=8 initcall_debug=0 swiotlb=512 cgroup_enable cgroup_memory=1 init=/sbin/init"

function post_family_tweaks__bpi-r4() {
	display_alert "Applying eth blobs"
	
	mkdir -p "$SDCARD/lib/firmware/mediatek/mt7988"
	cp -v "$SRC/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_0.bin" "$SDCARD/lib/firmware/mediatek/mt7988/mt7988_wo_0.bin"
	cp -v "$SRC/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_1.bin" "$SDCARD/lib/firmware/mediatek/mt7988/mt7988_wo_1.bin"
}
