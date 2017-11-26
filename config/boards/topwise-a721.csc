# A10 512MB generic Chinese Tablet (LY-F1)
BOARD_NAME="Topwise-A721"
BOARDFAMILY="sun4i"
BOOTCONFIG="Linksprite_pcDuino_defconfig"
MODULES="hci_uart gpio_sunxi rfcomm hidp sunxi-ir bonding spi_sunxi zet6221 ssd253x_ts gt811  sichuang ft5x_ts ump mali mali_drm videobuf-core videobuf-dma-contig gc0308 gt2005 sun4i_csi0 usbnet asix qf9700 mcs7830 8192cu rtl8150 bma250 mma7660 stk8312 dmard06 cdc_ether cdc_eem cdc_subset"
MODULES_NEXT="bonding"
#
KERNEL_TARGET="default"
CLI_TARGET="jessie:next"
DESKTOP_TARGET="xenial:default"
