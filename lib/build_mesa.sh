# Copyright (c) 2019 Zhang Ning <zhangn1985@XXX.com>
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# build_mesa

build_mesa()
{
	# install libdrm-dev 2.4.99 from debian sid
	echo "deb http://${DEBIAN_MIRROR} sid main" >  $SDCARD/etc/apt/sources.list.d/sid.list
	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt update"
	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt -yqq install libdrm-dev -t sid"

	# TODO use apt preference to lower priority of sid, not remove it.
	rm $SDCARD/etc/apt/sources.list.d/sid.list
	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt update"

	#install other mesa build deps
	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c	"DEBIAN_FRONTEND=noninteractive\
	apt -yqq install meson quilt  glslang-tools pkg-config libx11-dev libxxf86vm-dev\
	libexpat1-dev libsensors-dev libxfixes-dev libxdamage-dev libxext-dev\
	libva-dev libvdpau-dev libvulkan-dev x11proto-dev linux-libc-dev\
	libx11-xcb-dev libxcb-dri2-0-dev libxcb-glx0-dev libxcb-xfixes0-dev libxcb-dri3-dev\
	libxcb-present-dev libxcb-randr0-dev libxcb-sync-dev libxrandr-dev\
	libxshmfence-dev python3 python3-mako python3-setuptools flex bison\
	llvm-7-dev libelf-dev libwayland-dev libwayland-egl-backend-dev libclang-7-dev\
	libclc-dev wayland-protocols zlib1g-dev" 

	# download mesa master source code.
	fetch_from_repo "https://gitlab.freedesktop.org/mesa/mesa.git" "mesa" "branch:master" "yes"

	# build dummy mesa packages
	for i in $SRC/packages/mesa-dummy/*.ctl; do
		equivs-build $i
	done

	mkdir -p "${DEST}/debs/${RELEASE}/mesa/$ARCH"
	mv *.deb "${DEST}/debs/${RELEASE}/mesa/$ARCH"

	mkdir -p $SRC/cache/sources/mesa/dummy

	mount $SRC/cache/sources/mesa $SDCARD/mnt -o bind
	mount "${DEST}/debs/${RELEASE}/mesa/$ARCH" $SDCARD/mnt/dummy -o bind

	cat <<-EOF > "${SDCARD}"/mnt/build_mesa.sh
	#!/bin/sh
	dpkg -i /mnt/dummy/*.deb
	mkdir -p /mnt/master/build
	cd /mnt/master/build
	meson ..
	meson --reconfigure -Dprefix=/usr/ -Dshared-glapi=true -Dgallium-xvmc=false -Dgallium-omx=disabled\
	                   -Db_ndebug=true -Dglx-direct=true -Dgbm=true	-Ddri3=true	-Dplatforms="x11,surfaceless,wayland,drm" -Dgles1=true -Dgles2=true \
	                   -Dllvm=true -Dosmesa=gallium -Dgallium-drivers="kmsro, lima, swrast" -Degl=true
	ninja
	ninja install
	EOF

	chmod +x "${SDCARD}"/mnt/build_mesa.sh

	LC_ALL=C LANG=C chroot "${SDCARD}" /bin/bash -c /mnt/build_mesa.sh

	umount $SDCARD/mnt/dummy
	umount $SDCARD/mnt
}


