# Rockchip RK3576 octa core 4-16GM 2x GbE eMMC HDMI WiFi USB3 3x M.2 (B/E/M-Key)

BOARD_NAME="Photonicat2"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOOTCONFIG="photonicat2-rk3576_defconfig"
KERNEL_TARGET="edge"
FULL_DESKTOP="no"
BOOT_FDT_FILE="rockchip/rk3576-photonicat2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
ENABLE_EXTENSIONS="radxa-aic8800"
AIC8800_TYPE="usb"
