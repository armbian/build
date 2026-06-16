#!/usr/bin/env bash

BOARD=orangepi3b
BRANCH=vendor
RELEASE=bookworm
IMAGE_PARTITION_TABLE=msdos

BUILD_DESKTOP=no
BUILD_MINIMAL=yes

KERNEL_CONFIGURE=no
KERNEL_BTF=no
INSTALL_HEADERS=no
EXTRAWIFI=yes
NETWORKING_STACK=network-manager

CPUTHREADS=104
USE_CCACHE=yes
PRIVATE_CCACHE=yes
ARTIFACT_IGNORE_CACHE=yes

COMPRESS_OUTPUTIMAGE=sha,img
DSI_OVERLAY_INSTALL=yes
DSI_OVERLAY_NAMES="orangepi3b-debug-noop orangepi3b-waveshare-5inch-dsi-i2c-only orangepi3b-waveshare-5inch-dsi-host-only orangepi3b-waveshare-5inch-dsi-panel-no-touch orangepi3b-waveshare-5inch-dsi-safe orangepi3b-waveshare-5inch-dsi-panel orangepi3b-waveshare-5inch-dsi-vp0 orangepi3b-waveshare-5inch-dsi-vp1 orangepi3b-waveshare-5inch-dsi-vp0-only"
DEFENCEDOG_NOBLE_DTB_INSTALL=yes
FORCE_FDTFILE="rockchip/rk3566-orangepi-3b-v2.1.dtb"

function user_config__opi3b_vendor_bookworm_cli_debug() {
	GOVERNOR=performance
	EXTRA_IMAGE_SUFFIXES+=("-opi3b21-debug-npu-gpu-dsi-nooops7")

	add_packages_to_image \
		pciutils usbutils nvme-cli i2c-tools rfkill iw wireless-tools \
		bluetooth bluez-tools mesa-utils mesa-utils-bin vulkan-tools vainfo v4l-utils lm-sensors \
		cpufrequtils fio iperf3 sysbench stress-ng python3-pip python3-venv python3-numpy \
		fbset evtest
}

function custom_kernel_config__opi3b_dsi_panel_builtin() {
	kernel_config_modifying_hashes+=("CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=y")
	kernel_config_modifying_hashes+=("CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY=y")
	kernel_config_modifying_hashes+=("CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y")
	kernel_config_modifying_hashes+=("CONFIG_TOUCHSCREEN_RASPITS_FT5426=y")

	[[ -f .config && -x ./scripts/config ]] || return 0

	kernel_config_set_y CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN
	kernel_config_set_y CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY
	kernel_config_set_y CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2
	kernel_config_set_y CONFIG_TOUCHSCREEN_RASPITS_FT5426
}
