# Allwinner A733 (sun60iw2) octa-core 2-16GB LPDDR5, GbE, PCIe, USB, WiFi6/BT (USB AIC8800)
#
# TODO: DWC3 USB2 hub / AIC8800 enumeration is still being validated.
# Ethernet, SD boot, UART and the eMMC module are working.
BOARD_NAME="Cubie A7A"
BOARD_VENDOR="radxa"
BOARDFAMILY="sun60iw2-dev"
BOARD_MAINTAINER="juanesf"
INTRODUCED="2026"
KERNEL_TARGET="dev"
KERNEL_TEST_TARGET="dev"
IMAGE_PARTITION_TABLE="msdos"
HAS_VIDEO_OUTPUT="no" # no mainline HDMI driver yet

BOOTCONFIG_DEV="radxa_cubie_a7a_defconfig"
BOOT_FDT_FILE="allwinner/sun60i-a733-cubie-a7a.dtb"

# WiFi/BT is an AIC8800D80 connected over USB (not SDIO).
MODULES="aic_load_fw_usb aic8800_fdrv_usb aic_btusb_usb"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
AIC8800_TYPE="usb"
enable_extension "radxa-aic8800"

# The kernel's parallel dtbs_install target can race while creating the
# vendor subdirectory. Pre-create it to keep the install step deterministic.
# The kernel's parallel dtbs_install target uses "install -D" for every DTB.
# With -j24 two jobs can try to mkdir the same vendor directory at once and
# install(1) fails with "cannot create directory .../dtbs/<vendor>". Pre-create
# every first-level dts directory so install only ever creates files, never
# directories. Applies to mainline 7.4 as well as the old 7.2 vendor tree.
function kernel_make_config__cubie_a7a_precreate_dtbs_dirs() {
	[[ -n "${kernel_dest_install_dir:-}" ]] || return 0

	local dts_root="${kernel_work_dir:-${SRC}/cache/sources/${LINUXSOURCEDIR}}/arch/arm64/boot/dts"
	local dest="${kernel_dest_install_dir}/dtbs"
	local d

	mkdir -p "${dest}"
	if [[ -d "${dts_root}" ]]; then
		for d in "${dts_root}"/*/; do
			[[ -d "${d}" ]] || continue
			mkdir -p "${dest}/$(basename "${d}")"
		done
	fi
	mkdir -p "${dest}/allwinner/overlay"
}
