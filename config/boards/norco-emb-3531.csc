# Rockchip RK3399 2GB DDR3 16GB eMMC GBE USB3 RTL8188ETV WiFi PCIe x4 slot
BOARD_NAME="NORCO EMB-3531"
BOARD_VENDOR="norco"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="retro98boy"
BOOTCONFIG="emb-3531-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_CURRENT="extcon-usbc-virtual-pd"
MODULES_EDGE="extcon-usbc-virtual-pd"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-emb-3531.dtb"
BOOTBRANCH_BOARD="tag:v2026.01"
BOOTPATCHDIR="v2026.01"
BOOT_SCENARIO="binman"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS2,1500000 console=tty0"

PACKAGE_LIST_BOARD="alsa-ucm-conf" # Contain ALSA UCM top-level configuration file

function post_family_tweaks_bsp__norco-emb-3531() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	# Use ALSA UCM via CLI:
	# alsactl init hw:emb3531 && alsaucm -c hw:emb3531 set _verb "HiFi" set _enadev "Headphones" set _enadev "Speakers"
	# aplay -D plughw:emb3531,0 /usr/share/sounds/alsa/Front_Center.wav

	install -Dm644 "${SRC}/packages/bsp/norco-emb-3531/emb-3531-HiFi.conf" \
		"${destination}/usr/share/alsa/ucm2/Rockchip/emb-3531/emb-3531-HiFi.conf"
	install -Dm644 "${SRC}/packages/bsp/norco-emb-3531/emb-3531.conf" \
		"${destination}/usr/share/alsa/ucm2/Rockchip/emb-3531/emb-3531.conf"

	if [ ! -d "${destination}/usr/share/alsa/ucm2/conf.d/simple-card" ]; then
		mkdir -p "${destination}/usr/share/alsa/ucm2/conf.d/simple-card"
	fi
	ln -sfv /usr/share/alsa/ucm2/Rockchip/emb-3531/emb-3531.conf \
		"${destination}/usr/share/alsa/ucm2/conf.d/simple-card/emb-3531.conf"
}
