# Rockchip RK3566 tablet 4GB LPDDR3 32GB eMMC 800x1280 DSI UWE5621DS Wi-Fi/BT
BOARD_NAME="R10D"
BOARD_VENDOR="torder"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="JasonYANG170"
INTRODUCED="2022"
BOOTCONFIG="generic-rk3568_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
POWER_MANAGEMENT_FEATURES="yes"
BOOT_FDT_FILE="rockchip/rk3566-torder-r10d.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="binman"
SERIALCON="ttyFIQ0:1500000"
PACKAGE_LIST_BOARD="bluez rfkill iproute2"
MODULES_VENDOR="sprdwl_ng sprdbt_tty sc7a20 gsl3673-800x1280 panel_simple pwm_bl"

function post_family_config__torder_r10d_use_mainline_uboot() {
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10/board_torder-r10d"
	declare -g BOOTDELAY=1
	declare -g BOOTENV_FILE="torder-r10d.txt"
	declare -g DDR_BLOB="rk35/rk3568_ddr_780MHz_v1.10.bin"
	declare -g UBOOT_TARGET_MAP="BL31=${SRC}/cache/sources/rkbin-r10d/3e288fe814e059dd06833495f845cab04ac20a5c/bin/rk35/rk3568_bl31_v1.46.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
}

function post_family_tweaks_bsp__torder_r10d_install_bsp_files() {
	: "${destination:?}"
	install -d "${destination}/usr/bin" "${destination}/usr/lib/systemd/system" "${destination}/etc/udev/rules.d"
	install -m 644 "${SRC}/packages/bsp/rockchip/60-media.rules" "${destination}/etc/udev/rules.d/"
	install -m 755 "${SRC}/packages/bsp/rk3399/hciattach_opi" "${destination}/usr/bin/"
	install -m 755 "${SRC}/packages/bsp/torder-r10d/torder-r10d-bluetooth" "${destination}/usr/bin/"
	install -m 755 "${SRC}/packages/bsp/torder-r10d/torder-r10d-wifi-address" "${destination}/usr/bin/"
	install -m 644 "${SRC}/packages/bsp/torder-r10d/70-torder-r10d-wifi.rules" "${destination}/etc/udev/rules.d/"
	install -d "${destination}/usr/lib/firmware"
	ln -s "uwe5621ds/wifi_56630001_3ant.ini" "${destination}/usr/lib/firmware/wifi_56630001_3ant.ini"
	install -m 644 "${SRC}/packages/bsp/torder-r10d/torder-r10d-bluetooth.service" "${destination}/usr/lib/systemd/system/"
	install -m 755 "${SRC}/packages/bsp/torder-r10d/torder-r10d-bluetooth-sleep" "${destination}/usr/bin/"
	install -m 644 "${SRC}/packages/bsp/torder-r10d/torder-r10d-bluetooth-sleep.service" "${destination}/usr/lib/systemd/system/"
	install -d "${destination}/etc/systemd/sleep.conf.d"
	install -m 644 "${SRC}/packages/bsp/torder-r10d/torder-r10d-sleep.conf" "${destination}/etc/systemd/sleep.conf.d/90-torder-r10d.conf"
}

function post_family_tweaks__torder_r10d_enable_bluetooth_services() {
	chroot_sdcard systemctl --no-reload enable torder-r10d-bluetooth.service torder-r10d-bluetooth-sleep.service
}

function fetch_sources_tools__torder_r10d_bl31() {
	fetch_from_repo "https://github.com/rockchip-linux/rkbin" "rkbin-r10d" "commit:3e288fe814e059dd06833495f845cab04ac20a5c" "yes"
}
