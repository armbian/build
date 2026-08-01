# PHYTEC phyBOARD-Rigel AM67x quad core 4GB LPDDR4 eMMC OSPI GBE USB3 HDMI

BOARD_NAME="PHYTEC phyBOARD-Rigel AM67x"
BOARD_VENDOR="phytec"
BOARDFAMILY="k3"
BOARD_MAINTAINER="Grippy98"
INTRODUCED="2026"
BOOT_SOC="j722s"
BOOTCONFIG="phycore_am67x_a53_defconfig"
BOOTFS_TYPE="fat"
BOOT_FDT_FILE="ti/k3-am6754-phyboard-rigel.dtb"
PACKAGE_LIST_BOARD="v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad libgles2"
TIBOOT3_BOOTCONFIG="phycore_am67x_r5_defconfig"
TIBOOT3_FILE="tiboot3-am67x-hs-fs-phycore-som.bin"
DEFAULT_CONSOLE="serial"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
SERIALCON="ttyS2"
SRC_EXTLINUX="yes"
NAME_INITRD="initrd.img"
SRC_CMDLINE="rootwait console=ttyS2,115200n8 earlycon=ns16550a,mmio32,0x02800000 loglevel=7"
ATF_PLAT="k3"
ATF_BOARD="lite"
OPTEE_ARGS=""
OPTEE_PLATFORM="k3-am62x"
# TI Rogue driver builds J722S with the AM62P GPU system.
TI_DEBPKGS_FALLBACK_SUITES=("noble" "jammy")
TI_PACKAGES+=(
	"ti-img-rogue-driver-am62p-dkms"
	"ti-img-rogue-umlibs-am62p"
	"ti-img-rogue-tools-am62p"
	"ti-img-rogue-firmware-am62p"
	"gstreamer1.0-tools"
	"gstreamer1.0-plugins-good"
	"gstreamer1.0-plugins-bad"
	"gstreamer1.0-plugins-base"
)
if [[ "${RELEASE}" == "bookworm" || "${RELEASE}" == "jammy" ]]; then
	TI_PACKAGES+=("mesa-vulkan-drivers" "libgl1-mesa-dri")
fi

function post_family_config_branch_vendor__phycore_am67x_sources() {
	display_alert "$BOARD" "Using PHYTEC AM67x vendor kernel and U-Boot" "info"

	declare -g KERNELSOURCE="https://github.com/phytec/linux-phytec-ti"
	declare -g KERNEL_MAJOR_MINOR="6.12"
	declare -g KERNELBRANCH="tag:v6.12.57-11.02.11-phy6"
	declare -g KERNEL_DESCRIPTION="PHYTEC phyCORE-AM67x vendor kernel"
	declare -g LINUXCONFIG="linux-k3-phytec-vendor"
	declare -g KERNELPATCHDIR="archive/k3-phytec-6.12"

	declare -g BOOTSOURCE="https://github.com/phytec/u-boot-phytec-ti"
	declare -g BOOTBRANCH="tag:v2025.01-11.02.11-phy6"
	declare -g BOOTPATCHDIR="u-boot-phytec-k3"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g BOOTDELAY=1

	declare -g ATFSOURCE="https://github.com/TexasInstruments/arm-trusted-firmware"
	declare -g ATFBRANCH="tag:11.02.08"
	declare -g OPTEE_BRANCH="tag:4.6.0"
	declare -g TI_LINUX_FIRMWARE_BRANCH="tag:11.02.11"
}

function custom_kernel_config__phycore_am67x_vendor_defconfig() {
	[[ "${BOARD}" == "phycore-am67x" && -f .config ]] || return 0

	local vendor_defconfig="arch/arm64/configs/phytec_ti_defconfig"
	[[ -f "${vendor_defconfig}" ]] || exit_with_error "Missing PHYTEC kernel defconfig" "${vendor_defconfig}"

	local overlay_config="${SRC}/config/kernel/${LINUXCONFIG}.config"
	if [[ -f "${USERPATCHES_PATH}/${LINUXCONFIG}.config" ]]; then
		overlay_config="${USERPATCHES_PATH}/${LINUXCONFIG}.config"
	elif [[ -f "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" ]]; then
		overlay_config="${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config"
	fi

	display_alert "$BOARD" "Seeding kernel config from PHYTEC defconfig" "info"
	cp -f "${vendor_defconfig}" .config
	grep -E '^(CONFIG_[A-Za-z0-9_]+[= ]|# CONFIG_[A-Za-z0-9_]+ is not set)' "${overlay_config}" >> .config || true
	kernel_config_modifying_hashes+=("KERNEL_BASE_DEFCONFIG=${vendor_defconfig}")
}

function post_family_tweaks_bsp__phycore_am67x_raw_initrd_hook() {
	display_alert "$BOARD" "Installing raw initrd update hook" "info"

	run_host_command_logged mkdir -p "${destination}/etc/initramfs/post-update.d"
	run_host_command_logged cat <<- 'PHYCORE_AM67X_RAW_INITRD' > "${destination}/etc/initramfs/post-update.d/98-phycore-am67x-raw-initrd"
		#!/bin/bash -e

		exec </dev/null >&2

		initrd_file=$2
		target=/boot/initrd.img

		if [[ -f "${initrd_file}" ]]; then
			cp "${initrd_file}" "${target}"
			sync -f "${target}" || true
		fi

		exit 0
	PHYCORE_AM67X_RAW_INITRD
	run_host_command_logged chmod a+x "${destination}/etc/initramfs/post-update.d/98-phycore-am67x-raw-initrd"
}

function pre_umount_final_image__phycore_am67x_raw_extlinux_initrd() {
	display_alert "$BOARD" "Pointing extlinux at raw initrd" "info"

	local raw_initrd
	raw_initrd="$(find "${MOUNT}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort | tail -n 1)"
	if [[ -z "${raw_initrd}" ]]; then
		exit_with_error "No raw initrd found for ${BOARD}" "${MOUNT}/boot/initrd.img-*"
	fi

	cp -f "${raw_initrd}" "${MOUNT}/boot/initrd.img"
	sync -f "${MOUNT}/boot/initrd.img" || true

	if [[ -f "${MOUNT}/boot/extlinux/extlinux.conf" ]]; then
		sed -i 's#^  initrd .*$#  initrd /initrd.img#' "${MOUNT}/boot/extlinux/extlinux.conf"
	fi
}
