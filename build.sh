#!/bin/bash

# Remove stale apt lock files left by previous failed/interrupted builds
sudo find .tmp -name "rootfs-*" -maxdepth 1 -type d 2>/dev/null | while read -r rootfs; do
	sudo rm -fv \
		"${rootfs}/var/cache/apt/archives/lock" \
		"${rootfs}/var/lib/apt/lists/lock" \
		"${rootfs}/var/lib/dpkg/lock" \
		"${rootfs}/var/lib/dpkg/lock-frontend"
done
sudo rm -fv cache/aptcache/noble-arm64/lock cache/aptcache/lists/noble-arm64/lock

# Build (unset COLUMNS to avoid ValueError in patching.py)
unset COLUMNS
./compile.sh build \
  PREFER_DOCKER=no \
  BOARD=orangepi5-ultra  \
  BRANCH=vendor \
  BUILD_MINIMAL=yes \
  KERNEL_CONFIGURE=no \
  INSTALL_HEADERS=yes \
  INCLUDE_HOME_DIR=yes \
  RELEASE=noble

# Flash the latest image to /dev/sda
# sudo dd if="output/images/Armbian-unofficial_26.02.0-trunk_Orangepi5-ultra_noble_vendor_6.1.115_minimal.img" of=/dev/sda bs=4M status=progress conv=fsync && sudo sync
