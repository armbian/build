#!/usr/bin/env bash

BOARD=orangepi3b
BRANCH=vendor
RELEASE=bookworm
IMAGE_PARTITION_TABLE=msdos

BUILD_DESKTOP=yes
DESKTOP_ENVIRONMENT=xfce
DESKTOP_TIER=minimal
BUILD_MINIMAL=no

KERNEL_CONFIGURE=no
KERNEL_BTF=no
INSTALL_HEADERS=no
EXTRAWIFI=yes
NETWORKING_STACK=network-manager

CPUTHREADS=104
USE_CCACHE=yes
PRIVATE_CCACHE=yes
ARTIFACT_IGNORE_CACHE=no

COMPRESS_OUTPUTIMAGE=sha,img
DSI_OVERLAY_INSTALL=yes
DSI_OVERLAY_NAME=orangepi3b-waveshare-5inch-dsi-safe
FORCE_FDTFILE="rockchip/rk3566-orangepi-3b-v2.1.dtb"

function user_config__opi3b_vendor_bookworm_xfce_max() {
	GOVERNOR=performance
	EXTRA_IMAGE_SUFFIXES+=("-opi3b21-max-v21-safe")

	add_packages_to_image \
		pciutils usbutils nvme-cli i2c-tools rfkill iw wireless-tools \
		bluetooth bluez-tools mesa-utils vulkan-tools vainfo v4l-utils lm-sensors \
		cpufrequtils fio iperf3 sysbench stress-ng
}
