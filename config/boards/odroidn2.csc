# Amlogic S922X hexa core 2GB/4GB RAM SoC 1.8-2.4Ghz eMMC GBE USB3 SPI RTC
BOARD_NAME="Odroid N2"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOT_LOGO="desktop"
BOOTCONFIG="odroid-n2_defconfig" # For mainline uboot

# Newer u-boot for the N2/N2+, less patches: a single boot order patch
BOOTBRANCH_BOARD="tag:v2022.10"
BOOTPATCHDIR="v2022.10"

# Enable writing u-boot to SPI on the N2(+) for current and edge
# @TODO: replace this with an overlay, after meson64 overlay revamp
# To enable the SPI NOR the -spi .dtb is required, because eMMC shares a pin with SPI on the N2(+). To use it:
# fdtfile=amlogic/meson-g12b-odroid-n2-plus-spi.dtb # in armbianEnv.txt and reboot, then run nand-sata-install
UBOOT_TARGET_MAP="u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img u-boot.bin:u-boot-spi.bin"
write_uboot_platform_mtd() {
	dd if=$1/u-boot-spi.bin of=/dev/mtdblock0
}

# MAX might be different for N2/N2+, for now use N2+'s
# @TODO: remove? cpufreq is not used anymore, instead DT should be patched
CPUMIN=1000000
CPUMAX=2400000
GOVERNOR=performance # some people recommend performance to avoid random hangs after 24+ hours running.

# U-boot has detection code for the ODROID boards.
#    https://github.com/u-boot/u-boot/blob/v2021.04/board/amlogic/odroid-n2/odroid-n2.c#L35-L106
# Unfortunately it uses n2_plus instead of n2-plus as the Kernel expects it.
#    So there is a hack at and around config/bootscripts/boot-meson64.cmd L90
# If needed (eg for extlinux) you can specify the N2/N2+/ DTB in BOOT_FDT_FILE, example for the N2+:
# BOOT_FDT_FILE="amlogic/meson-g12b-odroid-n2-plus.dtb"
