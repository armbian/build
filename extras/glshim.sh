#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2016 Dmitry Grigoryev
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

compile_glshim()
{
	display_alert "Building deb" "glshim" "info"

	local tmpdir="$CACHEDIR/sdcard/root/glshim"

	mkdir -p $tmpdir

	if [[ -d $tmpdir/glshim ]]; then
		cd $tmpdir/glshim
		display_alert "Updating sources" "glshim" "info"
		git checkout -f -q master
		git pull -q
	else
		display_alert "Downloading sources" "glshim" "info"
		# TODO: Replace with fetch_from_github
		git clone -q https://github.com/ptitSeb/glshim $tmpdir/glshim
	fi

	pack_to_deb()
	{
		cd $tmpdir
		mkdir libglshim-${RELEASE}_${REVISION}_${ARCH}
		cd libglshim-${RELEASE}_${REVISION}_${ARCH}

		mkdir -p usr/lib
		cp $tmpdir/glshim/lib/libGL.so.1 usr/lib

		# resolve dependencies
		#mkdir $tmpdir/debian
		#echo Source: debian > $tmpdir/debian/control
		#echo libGL 1 armbian-glshim-${RELEASE}_${REVISION}_${ARCH} \| libgl1 > $tmpdir/debian/shlibs.local
		#chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/glshim; dpkg-shlibdeps libglshim-${RELEASE}_${REVISION}_${ARCH}/usr/lib/libGL.so.1" >> $DEST/debug/glshim-build.log 2>&1
		#if [[ ! -f ../debian/substvars ]]; then
		#	exit_with_error "Error resolving dependencies" "glshim"
		#fi
		# Depends: $(sed s/shlibs\:Depends=// ../debian/substvars)

		# set up control file and scripts
		mkdir DEBIAN
		cat <<-END > DEBIAN/control
Package: libglshim
Version: $REVISION-$RELEASE
Architecture: $ARCH
Maintainer: $MAINTAINER <$MAINTAINERMAIL>
Installed-Size: 1
Section: libs
Replaces: libgl1-mesa-glx
Provides: libgl1
Depends: libc6 (>= 2.8), libdrm2 (>= 2.3.1), libexpat1 (>= 2.0.1), libglapi-mesa, libx11-6 (>= 2:1.4.99.1), libx11-xcb1, libxcb-dri2-0 (>= 1.8), libxcb-dri3-0, libxcb-glx0 (>= 1.8), libxcb-present0, libxcb-sync1, libxcb1 (>= 1.9.2), libxdamage1 (>= 1:1.1), libxext6, libxfixes3, libxshmfence1, libxxf86vm1, libudev1, sunxi-mali-r3p0, fbturbo
Recommends: libgl1-mesa-dri
Conflicts: libgl1
Priority: optional
Description: Wrapper library emulating OpenGL using GLES
		END
		cat <<-END > DEBIAN/postinst
#!/bin/sh
set -e
if [ "\$1" = "configure" ]; then
	ldconfig
fi
		END
		chmod a+x DEBIAN/postinst
		cat <<-END > DEBIAN/postrm
#!/bin/sh
set -e
if [ "\$1" = "remove" ]; then
	ldconfig
fi
		END
		chmod a+x DEBIAN/postrm

		# add dev stuff
		ln -s libGL.so.1 usr/lib/libGL.so
		mkdir -p usr/share/pkgconfig
		cat <<-END > usr/share/pkgconfig/gl.pc
prefix=/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: gl
Description: glshim OpenGL via GLES library
Version: $REVISION
Libs: -L\${libdir} -lGL
Libs.private: -lm -lpthread -ldl
Cflags: -I\${includedir} 
		END

		find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
		cd ..
		dpkg -b libglshim-${RELEASE}_${REVISION}_${ARCH} >/dev/null
		mv *.deb $DEST/debs
		cd $CACHEDIR
		rm -rf $tmpdir
	}

	compiling()
	{
		#chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y install libx11-dev libxext-dev xutils-dev libdrm-dev x11proto-xf86dri-dev libxfixes-dev" >> $DEST/debug/glshim-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/glshim/glshim; cmake .; make clean" >> $DEST/debug/glshim-build.log 2>&1
		chroot $CACHEDIR/sdcard /bin/bash -c "cd /root/glshim/glshim; make $CTHREADS GL" >> $DEST/debug/glshim-build.log 2>&1
		#chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y remove libx11-dev libxext-dev xutils-dev libdrm-dev x11proto-xf86dri-dev libxfixes-dev" >> $DEST/debug/glshim-build.log 2>&1
		if [[ $? -ne 0 || ! -f $tmpdir/glshim/lib/libGL.so.1 ]]; then
			cd $CACHEDIR
			#rm -rf $tmpdir
			exit_with_error "Error building" "glshim"
		fi
		chmod 644 $tmpdir/glshim/lib/libGL.so.1
	}

	patching()
	{
		display_alert "Patching glshim" "$1"
	}

	checkout()
	{
		cd $tmpdir/glshim
		if [[ $1 == stable ]]; then
			git checkout -f -q "master" >> $DEST/debug/glshim-build.log 2>&1
		else
			git checkout -f -q >> $DEST/debug/glshim-build.log 2>&1
		fi
	}

	checkout "stable"
	local apver=1.0
	display_alert "Compiling glshim" "v$apver" "info"
	#patching "xxx"
	compiling
	pack_to_deb
}

#[[ ! -f $DEST/debs/libglshim-${RELEASE}_${REVISION}_${ARCH}.deb ]] && compile_glshim
compile_glshim

display_alert "Installing" "libglshim-${RELEASE}_${REVISION}_${ARCH}.deb" "info"
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg --purge --force-depends libgl1-mesa-glx" >> $DEST/debug/install.log
chroot $CACHEDIR/sdcard /bin/bash -c "dpkg -i /tmp/libglshim-${RELEASE}_${REVISION}_${ARCH}.deb" >> $DEST/debug/install.log
#chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -f -y install" >> $DEST/debug/install.log
