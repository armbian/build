# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

install_mt7601()
{
	local plugin_repo="https://github.com/igorpecovnik/mt7601"
	local plugin_dir="mt7601"

	fetch_from_github "$plugin_repo" "$plugin_dir" "old"

	cd $SOURCES/$plugin_dir

	# DKMS support patch
	rm src/dkms.conf

	patch --batch --silent -N -p1 <<-'EOF'
	diff --git a/src/dkms.conf b/src/dkms.conf
	new file mode 100644
	index 0000000..7563b5a
	--- /dev/null
	+++ b/src/dkms.conf
	@@ -0,0 +1,8 @@
	+PACKAGE_NAME="mt7601-sta-dkms"
	+PACKAGE_VERSION="3.0.0.4"
	+CLEAN="make clean"
	+BUILT_MODULE_NAME[0]="mt7601Usta"
	+BUILT_MODULE_LOCATION[0]="./os/linux/"
	+DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
	+AUTOINSTALL=yes
	+MAKE[0]="make -j4 KERNELVER=\$kernelver"
	diff --git a/src/include/os/rt_linux.h b/src/include/os/rt_linux.h
	index 3726b9e..b8be886 100755
	--- a/src/include/os/rt_linux.h
	+++ b/src/include/os/rt_linux.h
	@@ -279,7 +279,7 @@ typedef struct file* RTMP_OS_FD;
	 
	 typedef struct _OS_FS_INFO_
	 {
	-#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,12,0)
	+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,4,0)
	 	uid_t				fsuid;
	 	gid_t				fsgid;
	 #else
	diff --git a/src/os/linux/rt_linux.c b/src/os/linux/rt_linux.c
	index 1b6a631..c336611 100755
	--- a/src/os/linux/rt_linux.c
	+++ b/src/os/linux/rt_linux.c
	@@ -51,7 +51,7 @@
	 #define RT_CONFIG_IF_OPMODE_ON_STA(__OpMode)
	 #endif
	 
	-ULONG RTDebugLevel = RT_DEBUG_TRACE;
	+ULONG RTDebugLevel = 0;
	 ULONG RTDebugFunc = 0;
	 
	 #ifdef OS_ABL_FUNC_SUPPORT
	EOF

	cd src
	make -s ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" clean >> $DEST/debug/compilation.log 2>&1
	make -s -j4 ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" LINUX_SRC=$SOURCES/$LINUXSOURCEDIR/ >> $DEST/debug/compilation.log 2>&1
	cp os/linux/*.ko $CACHEDIR/sdcard/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	mkdir -p $CACHEDIR/sdcard/etc/Wireless/RT2870STA
	cp RT2870STA.dat $CACHEDIR/sdcard/etc/Wireless/RT2870STA/
	depmod -b $CACHEDIR/sdcard/ $VER-$LINUXFAMILY
	make -s clean >/dev/null
	cd ..
	mkdir -p $CACHEDIR/sdcard/usr/src/
	cp -R src $CACHEDIR/sdcard/usr/src/mt7601-3.0.0.4
	# TODO: Set the module to build automatically via dkms in the future here
}

if [[ $BRANCH == default ]]; then
	display_alert "Installing additional driver" "MT7601U" "info"
	install_mt7601
fi
