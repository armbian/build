# i.MX8MP 4xA53, 1-8GB LPDDR4, eMMC, microSD, 2x GbE, WiFi5/BT5, 4x USB3, HDMI
BOARD_NAME="DEBIX Model A"
BOARD_VENDOR="polyhex"
BOARDFAMILY="imx8m"
BOARD_MAINTAINER="HeyMeco"
INTRODUCED="2022"
HAS_VIDEO_OUTPUT="yes"

KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
DEFAULT_CONSOLE="serial"
SERIALCON="ttymxc1"
SRC_CMDLINE="console=ttymxc1,115200 earlycon cma=640M"
BOOT_FDT_FILE="freescale/imx8mp-debix-model-a.dtb"
OVERLAY_PREFIX="imx8mp-debix-model-a"

BOOTBRANCH="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOTCONFIG="imx8mp_debix_model_a_defconfig"

ATFBRANCH="tag:lts-v2.14.9"
ATF_PLAT="imx8mp"
ATF_UART_BASE="0x30890000" # UART2 debug console

# Factory flashing enables eMMC boot0. Boot from the user area instead.
IMX8M_EMMC_BOOT_USER_AREA="yes"

# BCM43455 Bluetooth (BCM4345C0) has no generic patchram name in armbian-firmware.
# btbcm loads the board-specific name first.
function post_family_tweaks_bsp__debix_model_a_bt_firmware() {
	run_host_command_logged mkdir -pv "${destination}/lib/firmware/brcm"
	run_host_command_logged ln -sfv \
		"BCM4345C0_003.001.025.0162.0000_Generic_UART_37_4MHz_wlbga_ref_iLNA_iTR_eLG.hcd" \
		"${destination}/lib/firmware/brcm/BCM4345C0.polyhex,imx8mp-debix-model-a.hcd"
}
