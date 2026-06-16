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

CPUTHREADS=100
USE_CCACHE=yes
PRIVATE_CCACHE=yes
ARTIFACT_IGNORE_CACHE=no

COMPRESS_OUTPUTIMAGE=sha,img
DSI_OVERLAY_ENABLE=yes
DSI_OVERLAY_NAME=orangepi3b-waveshare-5inch-dsi-panel
DSI_OVERLAY_NAMES="orangepi3b-waveshare-5inch-dsi-panel"
FORCE_FDTFILE="rockchip/rk3566-orangepi-3b-v2.1.dtb"
FORCE_EXTRAARGS_APPEND="mitigations=off kpti=0 nospectre_v2 nospectre_bhb ssbd=force-off arm64.nobti audit=0 nokaslr apparmor=0 selinux=0 init_on_alloc=0 init_on_free=0 page_alloc.shuffle=0"
OPI3B_TOUCH_DESKTOP_TWEAKS=yes

function user_config__opi3b_vendor_bookworm_xfce_touch() {
	GOVERNOR=performance
	EXTRA_IMAGE_SUFFIXES+=("-opi3b21-fast-xfce-touch-dsi")

	add_packages_to_image \
		pciutils usbutils nvme-cli i2c-tools rfkill iw wireless-tools \
		bluetooth bluez-tools blueman network-manager-gnome \
		mesa-utils mesa-utils-bin vainfo v4l-utils lm-sensors brightnessctl \
		python3-venv python3-pip python3-numpy \
		onboard xinput xinput-calibrator x11-xserver-utils \
		arc-theme papirus-icon-theme fonts-noto-core fonts-noto-mono \
		xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin pavucontrol
}

function custom_kernel_config__opi3b_dsi_panel_touch_builtin() {
	kernel_config_modifying_hashes+=("CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=y")
	kernel_config_modifying_hashes+=("CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY=y")
	kernel_config_modifying_hashes+=("CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y")
	kernel_config_modifying_hashes+=("CONFIG_TOUCHSCREEN_RASPITS_FT5426=y")
	kernel_config_modifying_hashes+=("CONFIG_MALI_MIDGARD=n")
	kernel_config_modifying_hashes+=("CONFIG_MALI_BIFROST=n")
	kernel_config_modifying_hashes+=("CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y")
	kernel_config_modifying_hashes+=("CONFIG_CC_OPTIMIZE_FOR_SIZE=n")
	kernel_config_modifying_hashes+=("CONFIG_RANDOMIZE_BASE=n")
	kernel_config_modifying_hashes+=("CONFIG_SECURITY_SELINUX=n")
	kernel_config_modifying_hashes+=("CONFIG_SECURITY_APPARMOR=n")
	kernel_config_modifying_hashes+=("CONFIG_HARDENED_USERCOPY=n")
	kernel_config_modifying_hashes+=("CONFIG_INIT_ON_ALLOC_DEFAULT_ON=n")
	kernel_config_modifying_hashes+=("CONFIG_INIT_ON_FREE_DEFAULT_ON=n")
	kernel_config_modifying_hashes+=("CONFIG_SHUFFLE_PAGE_ALLOCATOR=n")

	[[ -f .config && -x ./scripts/config ]] || return 0

	kernel_config_set_y CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
	kernel_config_set_n CONFIG_CC_OPTIMIZE_FOR_SIZE
	kernel_config_set_y CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN
	kernel_config_set_y CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY
	kernel_config_set_y CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2
	kernel_config_set_y CONFIG_TOUCHSCREEN_RASPITS_FT5426
	kernel_config_set_n CONFIG_MALI_MIDGARD
	kernel_config_set_n CONFIG_MALI_BIFROST
	kernel_config_set_n CONFIG_RANDOMIZE_BASE
	kernel_config_set_n CONFIG_SECURITY_SELINUX
	kernel_config_set_n CONFIG_SECURITY_APPARMOR
	kernel_config_set_n CONFIG_HARDENED_USERCOPY
	kernel_config_set_n CONFIG_INIT_ON_ALLOC_DEFAULT_ON
	kernel_config_set_n CONFIG_INIT_ON_FREE_DEFAULT_ON
	kernel_config_set_n CONFIG_SHUFFLE_PAGE_ALLOCATOR
}
