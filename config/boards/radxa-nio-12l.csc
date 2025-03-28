# Mediatek MT8395 quad core 4GB 8GB 16GB
BOARD_NAME="Radxa Nio 12L"
BOARDFAMILY="genio"
BOARD_MAINTAINER="HeyMeco"
KERNEL_TARGET="collabora,vendor"
KERNEL_TEST_TARGET="collabora"
BOOT_FDT_FILE="mediatek/mt8395-radxa-nio-12l.dtb"
enable_extension "grub-with-dtb"
HAS_VIDEO_OUTPUT="yes"

# Post-config function for vendor branch
function post_family_config__nio12l_vendor_setup() {
	if [[ "${BRANCH}" == "vendor" ]]; then
		display_alert "Setting up Genio-Firmware package for ${BOARD}" "${RELEASE}///${BOARD}" "info"
		add_packages_to_image "linux-firmware-mediatek-genio" "ubuntu-dev-tools" "ubuntu-desktop"
	fi
}

# Post-config function for collabora branch
function post_family_config__nio12l_collabora_setup() {
	if [[ "${BRANCH}" == "collabora" ]]; then
		display_alert "Setting up Firmware-Full for ${BOARD}" "${RELEASE}///${BOARD}" "info"
		declare -g BOARD_FIRMWARE_INSTALL="-full"
	fi
}
