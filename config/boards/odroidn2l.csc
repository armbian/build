# Amlogic S922X hexa core 2GB/4GB RAM SoC 1.8-2.4Ghz eMMC GBE USB3 SPI RTC
BOARD_NAME="Odroid N2L"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
KERNEL_TARGET="edge" # @TODO: DTB for N2L is only in 6.3+; add current when we bump it to 6.3 or newer.
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOTCONFIG="odroid-n2l_defconfig"
BOOTBRANCH_BOARD="tag:v2023.07.02"
BOOTPATCHDIR="v2023.07" # Thus boots USB/NVMe/SCSI first. N2L only has USB.

# U-boot has detection code for the ODROID boards, but NOT for the n2l, at least until 23.10-rc2.
# See https://github.com/u-boot/u-boot/blob/v2023.10-rc2/board/amlogic/odroid-n2/odroid-n2.c
# Thus we need to set BOOT_FDT_FILE explicitly.
BOOT_FDT_FILE="amlogic/meson-g12b-odroid-n2l.dtb"
