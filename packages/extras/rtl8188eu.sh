# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# NOTE: NEeds gcc5 specific fixes like other wireless drivers

install_rtl8188eu()
{
	local plugin_repo="https://github.com/lwfinger/rtl8188eu"
	local plugin_dir="rt8188eu"

	fetch_from_repo "$plugin_repo" "$plugin_dir" "branch:master"
	cd $SRC/cache/sources/$plugin_dir

	make ARCH=$ARCHITECTURE CROSS_COMPILE=$KERNEL_COMPILER clean >> $DEST/debug/compilation.log

	# GCC5 compatibility patch
	patch --batch --silent -p1 -N <<-'EOF'
	diff --git a/include/ieee80211.h b/include/ieee80211.h
	index e283a5f..d07bdb8 100755
	--- a/include/ieee80211.h
	+++ b/include/ieee80211.h
	@@ -1194,18 +1194,18 @@ enum ieee80211_state {
	 (((Addr[2]) & 0xff) == 0xff) && (((Addr[3]) & 0xff) == 0xff) && (((Addr[4]) & 0xff) == 0xff) && \
	 (((Addr[5]) & 0xff) == 0xff))
	 #else
	-extern __inline int is_multicast_mac_addr(const u8 *addr)
	+static __inline int is_multicast_mac_addr(const u8 *addr)
	 {
	         return ((addr[0] != 0xff) && (0x01 & addr[0]));
	 }
	 
	-extern __inline int is_broadcast_mac_addr(const u8 *addr)
	+static __inline int is_broadcast_mac_addr(const u8 *addr)
	 {
	 	return ((addr[0] == 0xff) && (addr[1] == 0xff) && (addr[2] == 0xff) &&   \
	 		(addr[3] == 0xff) && (addr[4] == 0xff) && (addr[5] == 0xff));
	 }
	 
	-extern __inline int is_zero_mac_addr(const u8 *addr)
	+static __inline int is_zero_mac_addr(const u8 *addr)
	 {
	 	return ((addr[0] == 0x00) && (addr[1] == 0x00) && (addr[2] == 0x00) &&   \
	 		(addr[3] == 0x00) && (addr[4] == 0x00) && (addr[5] == 0x00));
	EOF
	# GCC5 compatibility patch end

	make ARCH=$ARCHITECTURE CROSS_COMPILE=$KERNEL_COMPILER KSRC=$SRC/cache/sources/$LINUXSOURCEDIR/ >> $DEST/debug/compilation.log
	cp *.ko $SDCARD/lib/modules/$VER-$LINUXFAMILY/kernel/net/wireless/
	depmod -b $SDCARD/ $VER-$LINUXFAMILY
}

if [[ $BRANCH == default && $ARCHITECTURE == arm ]]; then
	display_alert "Installing additional driver" "RT8188EU" "info"
	install_rtl8188eu
fi
