# Rockchip RK3588 octa core 16GB RAM SoC eMMC 4x NVMe 3x USB3 USB2 2.5GbE
BOARD_NAME="NanoPC CM3588 NAS"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="nanopc_cm3588_defconfig" # Enables booting from NVMe. Vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="legacy,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-nanopc-cm3588-nas.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="fat"
DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.15.bin'
BL31_BLOB='rk35/rk3588_bl31_v1.44.elf'
declare -g UEFI_EDK2_BOARD_ID="nanopc-cm3588-nas" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__nanopccm3588nas_udev_naming_audios() {
	display_alert "$BOARD" "Renaming CM3588 audio interfaces to human-readable form" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/

	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/90-naming-audios.rules"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI-0 Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI-1 Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DisplayPort-Over-USB Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-rt5616-sound", ENV{SOUND_DESCRIPTION}="Headphone Out/Mic In"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-IN Audio In"
	EOF

}

# Output from CM3588 syslog with edge kernel 6.8: r8169 0004:41:00.0 enP4p65s0: renamed from eth0
# Note: legacy kernel 5.10 uses driver r8125, edge kernel uses r8169 as of 6.8
function post_family_tweaks__nanopccm3588nas_udev_naming_network_interfaces() {
	display_alert "$BOARD" "Renaming CM3588 LAN interface to eth0" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0004:41:00.0", NAME:="eth0"
	EOF

}
