# Rockchip RK3576 octa core GbE eMMC USB3 SATA WiFi BT
BOARD_NAME="LCKFB Taishan Pi 3M"
BOARD_VENDOR="lckfb"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="gahingwoo"
INTRODUCED="2026"
BOOTCONFIG="lckfb-tspi-3m-rk3576_defconfig"
KERNEL_TARGET="vendor,edge"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-lckfb-tspi-3m.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
OVERLAY_PREFIX_BOARD="lckfb-tspi-3m"
# screen autodetect probes I2C; the optional EC20 4G module needs ModemManager
PACKAGE_LIST_BOARD="i2c-tools modemmanager alsa-ucm-conf"

# Mainline U-Boot for both branches; the board is not in the vendor U-Boot
function post_family_config__lckfb_taishanpi_3m_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	# Power the mini-PCIe slot for an EC20 4G module by default on the vendor
	# kernel (edge does it in the device tree). A PCIe or SATA card in the
	# slot needs the pcie or sata overlay instead.
	[[ "${BRANCH}" == vendor* ]] && declare -g DEFAULT_OVERLAYS="ec20-4g"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# The vendor kernel has no serdev for the AP6256 Bluetooth on UART6: power
# it up through rfkill and load its firmware with hciattach. Edge uses the
# mainline brcm,bcm4345c5 serdev node instead.
function post_family_tweaks_bsp__lckfb_taishanpi_3m_bluetooth() {
	[[ "${BRANCH}" == vendor* ]] || return 0
	display_alert "$BOARD" "Installing AP6256 Bluetooth service (vendor kernel)" "info"
	mkdir -p "${destination}/lib/systemd/system"
	cat <<- 'EOF_SERVICE' > "${destination}/lib/systemd/system/tspi3m-bluetooth.service"
		[Unit]
		Description=LCKFB TaishanPi 3M Bluetooth (AP6256 on ttyS6)
		After=dev-ttyS6.device
		Before=bluetooth.service

		[Service]
		Type=simple
		ExecStartPre=/usr/sbin/rfkill unblock bluetooth
		ExecStartPre=/bin/sh -c 'for r in /sys/class/rfkill/rfkill*; do [ "$(cat $r/name)" = bt_default ] && echo 1 > $r/state; done; sleep 1'
		ExecStart=/usr/bin/hciattach -n -s 115200 /dev/ttyS6 bcm43xx 1500000
		Restart=on-failure
		RestartSec=5

		[Install]
		WantedBy=multi-user.target
	EOF_SERVICE
}

function post_customize_image__lckfb_taishanpi_3m_bluetooth() {
	[[ "${BRANCH}" == vendor* ]] || return 0
	chroot_sdcard systemctl --no-reload enable tspi3m-bluetooth.service
}

# Board support files (packages/bsp/lckfb-tspi-3m), for both kernels:
# - screen autodetect: probes the touch controller on I2C0 at boot and
#   enables the overlay of the attached official MIPI DSI screen (the
#   overlays have the same names on vendor and edge)
# - ES8388 UCM profiles, one per kernel since the codec drivers differ, and
#   WirePlumber names/priorities for the sound devices
# - EC20 4G module: call audio over USB audio, linked to the speaker and
#   microphone only while a call is active
function post_family_tweaks_bsp__lckfb_taishanpi_3m_board_files() {
	display_alert "$BOARD" "Installing board support files" "info"
	local src="${SRC}/packages/bsp/lckfb-tspi-3m" f mode
	while IFS= read -r -d '' f; do
		mode=644
		[[ -x "${f}" ]] && mode=755
		install -D -m "${mode}" "${f}" "${destination}/${f#"${src}/"}"
	done < <(find "${src}" -type f -print0)
}

function post_customize_image__lckfb_taishanpi_3m_board_services() {
	chroot_sdcard systemctl --no-reload enable lckfb-tspi-3m-screen.service
	chroot_sdcard systemctl --global enable lckfb-tspi-3m-call-audio.service
	# GNOME images: a dialer and an SMS app for the 4G module, and a camera
	# app on the vendor kernel, where the MIPI camera works
	if [[ "${BUILD_DESKTOP}" == "yes" && "${DESKTOP_ENVIRONMENT}" == "gnome" ]]; then
		local apps=(gnome-calls callaudiod chatty)
		[[ "${BRANCH}" == vendor* ]] && apps+=(gnome-snapshot)
		chroot_sdcard_apt_get_install "${apps[@]}"
	fi
}

# MIPI cameras on the vendor kernel: the Rockchip 3A server for picture
# quality, and rk-pw-camera so desktop apps (GNOME Snapshot, browsers) can
# use the ISP, whose multi-planar API PipeWire does not support. Both come
# from the Armbian repository; skip quietly if a package is not there yet.
function post_customize_image__lckfb_taishanpi_3m_camera() {
	[[ "${BRANCH}" == vendor* ]] || return 0
	local pkgs=(camera-engine-rkaiq-rk3576)
	[[ "${BUILD_DESKTOP}" == "yes" ]] && pkgs+=(rk-pw-camera)
	local pkg available=()
	for pkg in "${pkgs[@]}"; do
		if chroot_sdcard apt-cache show "${pkg}" > /dev/null 2>&1; then
			available+=("${pkg}")
		else
			display_alert "$BOARD" "Camera package ${pkg} is not in the repository, skipping" "wrn"
		fi
	done
	((${#available[@]})) || return 0
	display_alert "$BOARD" "Installing camera support: ${available[*]}" "info"
	chroot_sdcard_apt_get_install "${available[@]}"
}

# Phosh does not follow the panel orientation property; tell phoc that the
# 10.1in DSI panel is used in landscape. Only applies when Phosh is installed.
function post_customize_image__lckfb_taishanpi_3m_phosh_landscape() {
	local ini="${SDCARD}/etc/phosh/phoc.ini"
	[[ -f "${ini}" ]] || return 0
	grep -q '^\[output:DSI-1\]' "${ini}" && return 0
	display_alert "$BOARD" "Setting Phosh to landscape on the DSI panel" "info"
	cat <<- 'EOF_PHOC' >> "${ini}"

		# LCKFB TaishanPi 3M 10.1in MIPI panel, used in landscape
		[output:DSI-1]
		rotate = 270
		scale = 1
	EOF_PHOC
}
