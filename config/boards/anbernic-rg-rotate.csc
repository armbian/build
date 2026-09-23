# Unisoc T618 (UMS512) octa core 4" 720x720 swivel touch LCD eMMC MicroSD WiFi/BT
BOARD_NAME="RG Rotate"
BOARD_VENDOR="anbernic"
BOARDFAMILY="sprd-ums512"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

BOOT_FDT_FILE="sprd/ums512-rg-rotate.dtb"

# The vendor defconfig this board ships is built with CONFIG_DEBUG_INFO_REDUCED=y.
# armbian_kernel_config__600_enable_ebpf_and_btf_info() otherwise forces DEBUG_INFO,
# DEBUG_INFO_DWARF5, DEBUG_INFO_BTF and DEBUG_INFO_BTF_MODULES on and explicitly turns
# DEBUG_INFO_REDUCED off. BTF_MODULES in particular gives every module a .BTF section,
# i.e. a module-loading path the vendor kernel has never been run with. Keep the debug
# info shape the board was validated at; a build can still override this from the
# command line.
KERNEL_BTF="${KERNEL_BTF:-no}"
IMAGE_PARTITION_TABLE="gpt"

# U-Boot's extlinux scan is hardcoded to mmc 1:2, so /boot has to be a real
# partition 2 rather than a directory on the rootfs.
#
# It being FAT is also what makes /boot/README.flash-bootloader-first.txt useful:
# this board does not boot a freshly written card until its first-stage loader has
# been replaced once, so the procedure has to be readable from the card on another
# machine, before the board is ever started. Same idea as ayn-odin3 putting its
# ABL flashing README in /boot.
BOOTFS_TYPE="fat"

# There is no broken-out UART on this board: the only console is the USB
# gadget (CDC-ACM) on the Type-C port. tty0 is the panel, which fbcon drives
# once DRM is up.
SERIALCON="ttyGS0"
# loglevel=4 keeps KERN_NOTICE and below off the console. The WCN driver
# prints a loopcheck plus an mdbg ring-buffer line every 5 seconds forever
# (WCN BASE: loopcheck / mdbg_ring_write / SLP_MGR: forbid slp), which on a
# handheld whose console is the panel means the screen never stops scrolling
# and dmesg's ring buffer wraps before you can read the boot out of it.
# Nothing is lost: this only gates the console, journald still records
# everything, so "journalctl -k -b" remains complete. Raise it back with
# loglevel=7 (or ignore_loglevel) on the extlinux append line when needed.
# log_buf_len=8M: the WCN driver logs every few seconds for the life of the
# system, so the default ring buffer has wrapped long before anyone can read
# the boot out of dmesg.
SRC_CMDLINE="console=tty0 loglevel=4 log_buf_len=8M"
# No MODULES= entry needed: the kernel config has CONFIG_USB_G_SERIAL=y, so the
# gadget binds at boot on its own (unlike RG DS, where it ships as a module).

# Gamepad helper dependencies, mirroring the other Anbernic handhelds.
PACKAGE_LIST_BOARD+=" python3-evdev python3-libevdev alsa-utils alsa-ucm-conf"

# Vendor BSP U-Boot: it carries the sprd DDR/PMIC/panel init and the
# extlinux_diag scan that boots us. Mainline U-Boot has no ums512 support.
function post_family_config__anbernic_rg_rotate_vendor_uboot() {
	display_alert "$BOARD" "vendor BSP U-Boot (ums512_1h10 board, rg_rotate config)" "info"

	# Mirror of beebono/u-boot-ums512, pinned (see the family config for why).
	declare -g BOOTSOURCE="https://github.com/crackerjacques/u-boot-ums512.git"
	declare -g BOOTBRANCH="commit:d1f91089bcb2df300f1e8a92938c1ca84a183e8c"
	# ums512_rg_rotate_defconfig, not the generic ums512_1h10 one: it sets
	# CONFIG_RG_ROTATE=y, which switches SYS_CONFIG_NAME to
	# include/configs/ums512_rg_rotate.h. Only that header defines
	# CONFIG_FS_FAT, and fs/fs.c registers FAT in its fstypes[] table under
	# that symbol alone (CONFIG_CMD_FAT only adds the fatload/fatls commands),
	# so with the 1h10 header the extlinux scan's file_exists(..., FS_TYPE_ANY)
	# can never match the FAT boot partition and the board halts on "No OS
	# found". It also carries CONFIG_CMD_BOOTI (needed to boot a raw arm64
	# Image out of sysboot), CONFIG_CMD_EXT4/FS_GENERIC, CONFIG_SUPPORT_RAW_INITRD,
	# the kernel/ramdisk/fdt/pxefile load addresses that clear the SoC
	# carve-outs, the AW32257 charger this board actually has (the 1h10 one
	# probes a SGM41512 and leaves the charge ops NULL), and it disables
	# CONFIG_ERASE_SPL_AUTO_DOWNLOAD.
	#
	# Note that a wrong defconfig here is not obvious from a boot log:
	# common/cmd_role.c setenv()s bootcmd to "extlinux_scan" unconditionally,
	# so the scan runs either way and only fails later.
	declare -g BOOTCONFIG="ums512_rg_rotate_defconfig"
	declare -g BOOTDIR="u-boot-${BOARD}"
	# Drops -ansi from the u-boot.cfg / u-boot.lds preprocessor rules; the
	# Spreadtrum board headers use // comments, which are fatal under C90.
	declare -g BOOTPATCHDIR="u-boot-ums512"
	# "make_target;patchdir;files". ARCH and DEVICE_TREE ride along as make
	# command-line variables. ARCH is repeated here even though the family hook
	# already adds it for the configure passes: uboot.sh:263 rebuilds
	# ${cross_compile} from scratch right before the build pass, dropping it.
	# ums512_rg_rotate is this board's own tree, not generic ums512_1h10.
	# Build u-boot-dtb.bin explicitly, the way the vendor tree is known to be
	# built, rather than the default "all". The files collected for packaging
	# are the DHTB image from uboot_custom_postprocess and the SPL the family's
	# post_uboot_custom_postprocess hook builds next to it.
	declare -g UBOOT_TARGET_MAP="ARCH=arm DEVICE_TREE=ums512_rg_rotate u-boot-dtb.bin;;uboot_dhtb.img spl.img"
	# Vendor tree builds as ARCH=arm with an aarch64 cross compiler.
	declare -g BOOTSCRIPT=""
}

# Restore the 39-bit VAs the vendor defconfig asks for.
#
# armbian_kernel_config__force_pa_va_48_bits_on_arm64() unconditionally appends
# ARM64_VA_BITS_48 to opts_y for every arm64 build, overriding the
# CONFIG_ARM64_VA_BITS_39=y that config/kernel/linux-sprd-ums512-edge.config (a
# verbatim copy of the kernel tree's arch/arm64/configs/ums512_defconfig) carries.
# olddefconfig then pairs the resulting 48-bit layout with RANDOMIZE_BASE=y to turn
# RANDOMIZE_MODULE_REGION_FULL on, which widens the module region enormously.
#
# custom_kernel_config runs after that hook (see lib/functions/compilation/kernel-config.sh)
# but before armbian_kernel_config_apply_opts_from_arrays, and the arrays are the caller's
# locals - bash dynamic scoping is what lets a hook edit them, the same way the family config
# renumbers bootpart and appends to cross_compile. Editing opts_y is the only thing that
# works here: the apply pass walks opts_n first and opts_y second, so anything added to
# opts_n would just be re-enabled by the ARM64_VA_BITS_48 entry still sitting in opts_y.
function custom_kernel_config__anbernic_rg_rotate_va_bits_39() {
	declare -a kept=()
	declare opt

	# shellcheck disable=SC2154 # opts_y is the caller's local
	for opt in "${opts_y[@]}"; do
		case "${opt}" in
			ARM64_VA_BITS_48 | CONFIG_ARM64_VA_BITS_48) continue ;;
		esac
		kept+=("${opt}")
	done

	kept+=("ARM64_VA_BITS_39")
	opts_y=("${kept[@]}")

	display_alert "$BOARD" "keeping 39-bit VAs from the vendor defconfig" "info"

	# The vendor defconfig also turns on the sysfs firmware-loading fallback.
	# With it, every request_firmware() for a file that is not there hands a
	# uevent to udev and blocks for 60 seconds waiting for userspace to supply
	# the blob. The built-in WCN core and btsprdsdio both ask for firmware from
	# the initramfs, where it is deliberately absent, so each request parked a
	# udev event for a minute and "udevadm settle" in the initramfs scripts
	# (init-top: 120s default, local: 10s, init-bottom) burned through to their
	# timeouts: ~136s of "kernel" time in systemd-analyze, and on Ubuntu a
	# panic, since its init-bottom/udev runs under set -e. Without the fallback
	# a missing blob fails immediately with -ENOENT and udev never hears of it.
	# Direct loads from /lib/firmware (agdsp.bin in the initrd, the WCN blobs on
	# the rootfs) are unaffected.
	# shellcheck disable=SC2154 # opts_n is the caller's local
	opts_n+=("FW_LOADER_USER_HELPER_FALLBACK")
	display_alert "$BOARD" "disabling sysfs firmware-loader fallback" "info"
}

# Handheld / mobile options the vendor defconfig does not carry.
#
# ums512_defconfig is a generic Android BSP config: everything a phone HAL
# needs is there, but the things a Linux userland on a battery-powered
# handheld expects are not, and none of the armbian_kernel_config__* hooks
# supply them either (those cover cgroups, nftables, tunnels and filesystems).
# Same mechanism as above: opts_y/opts_m/opts_n are the caller's locals.
function custom_kernel_config__anbernic_rg_rotate_handheld() {
	# Suspend diagnostics. Suspend is a core feature on a handheld, this board
	# has no UART, and getting "echo mem" to survive took five separate fixes
	# (see the port notes). PM_DEBUG gives /sys/power/pm_test and
	# pm_print_times, PM_SLEEP_DEBUG the per-device suspend/resume timing and
	# the wakeup_sources accounting needed to find the next blocker in the
	# field. Cost is a few sysfs knobs.
	opts_y+=("PM_DEBUG" "PM_SLEEP_DEBUG")

	# TEO cpuidle governor. The defconfig sets no governor, so CPU_IDLE
	# auto-selects menu. TEO is what current arm64 mobile kernels (Android
	# GKI included) run; it sizes idle-state selection on timer events
	# instead of menu's interactivity heuristics, which on an 8-core big.LITTLE
	# sitting idle at a desktop tends to pick the deeper state more often.
	# Setting TEO makes CPU_IDLE stop selecting menu, so TEO is the only
	# governor built in and no cmdline switch is needed. Drop this line to go
	# back to menu.
	opts_y+=("CPU_IDLE_GOV_TEO")

	# USB HID gadget: lets the handheld present itself as a keyboard/gamepad
	# to a PC over the Type-C port, next to the serial/NCM/mass-storage
	# functions the defconfig already builds into configfs.
	#
	# Built, but not reachable as shipped: the only console on this board is
	# the gadget serial port (there is no UART), so CONFIG_USB_G_SERIAL is
	# built in and holds the single UDC from boot - a configfs gadget can be
	# assembled but not bound. The console is worth more than the gadget by
	# default; someone who wants the gadget can rebuild with USB_G_SERIAL as a
	# module. Host mode is unaffected either way: dr_mode is "otg" with
	# usb-role-switch, so the Type-C role detection still brings up the musb
	# host controller for OTG peripherals.
	opts_y+=("USB_CONFIGFS_F_HID")

	# External controllers over Bluetooth and OTG host, plus USB-C audio
	# dongles. Same set the other Anbernic boards ship. INPUT_JOYSTICK is the
	# menu JOYSTICK_XPAD lives under; HID_PLAYSTATION takes its
	# LEDS_CLASS_MULTICOLOR=m dependency from the defconfig.
	opts_y+=("INPUT_JOYSTICK")
	opts_m+=("HID_SONY" "HID_PLAYSTATION" "HID_NINTENDO" "JOYSTICK_XPAD" "SND_USB_AUDIO")

	# ARMv8 Crypto Extensions AES. The defconfig only builds the NEON
	# bit-sliced AES (CRYPTO_AES_ARM64_BS) plus the CE CCM/GHASH variants, so
	# dm-crypt / fscrypt / IPsec fall back to the slow path and burn battery.
	# SHA-2 and CRC32 need nothing here: on 7.1 their arm64 versions live
	# under lib/ and are picked automatically.
	opts_y+=("CRYPTO_AES_ARM64_CE_BLK")

	# Policy routing. IP_ADVANCED_ROUTER / IP_MULTIPLE_TABLES /
	# IPV6_MULTIPLE_TABLES are absent from the defconfig and default off, which
	# leaves FIB_RULES out and makes "ip rule add" fail with EOPNOTSUPP. That
	# is what wg-quick, NetworkManager's VPN plugins, Tailscale and
	# systemd-networkd's RoutingPolicyRule= all rely on, so without it every
	# VPN on the box is dead even though the tunnel drivers are present.
	opts_y+=("IP_ADVANCED_ROUTER" "IP_MULTIPLE_TABLES" "IPV6_MULTIPLE_TABLES")

	# WireGuard. armbian_kernel_config__select_tunnels() deliberately leaves
	# it out ("already in 101 of 122 configs"); this config is one of the
	# other 21.
	opts_m+=("WIREGUARD")

	# fq_codel as the default qdisc. The defconfig builds no qdisc beyond the
	# TSN/ingress set, so the default is pfifo_fast. The Wi-Fi driver
	# (sc23xx) is a fullmac vendor driver that does not go through mac80211,
	# so it does not get mac80211's built-in per-station fq_codel either:
	# pfifo_fast on Wi-Fi is bufferbloat, i.e. latency spikes under load on
	# a gaming handheld. CAKE is built as a module so it can be picked with
	# tc for tethered or shaped links.
	opts_y+=("NET_SCH_FQ_CODEL" "DEFAULT_FQ_CODEL")
	opts_m+=("NET_SCH_CAKE")

	# USB tethering from a phone. CDC NCM/ECM host support is default-on
	# under USB_USBNET, RNDIS is not, and Android still offers RNDIS on a lot
	# of devices.
	opts_m+=("USB_NET_RNDIS_HOST")

	# Standard TCP hardening and a loss-tolerant congestion control for Wi-Fi.
	opts_y+=("SYN_COOKIES")
	opts_m+=("TCP_CONG_BBR")

	# Built-in code for hardware this board does not have. NFC (NXP NCI over
	# i2c) and DSA switch tagging are Android-BSP leftovers in the defconfig;
	# both are =y so they only cost image size, but nothing here can use them.
	opts_n+=("NFC" "NET_DSA")

	display_alert "$BOARD" "handheld kernel options: PM debug, TEO, HID gadget, controllers, AES-CE, policy routing, WireGuard, fq_codel" "info"
}

# No Plymouth on this board.
#
# main-config.sh defaults PLYMOUTH=yes, and config-prepare.sh only turns it off
# for BUILD_MINIMAL=yes - so a plain cli_standard build gets a splash screen
# nobody asked for. On a handheld whose only console is the panel, the splash
# just hides the boot messages you actually need during bring-up. The matching
# "splash plymouth.ignore-serial-consoles" comes from MAIN_CMDLINE in
# config/sources/common.conf; strip the two tokens rather than restating the
# whole list, so the rest of it keeps tracking upstream.
function post_family_config__anbernic_rg_rotate_no_plymouth() {
	declare -g PLYMOUTH="no"
	declare -g MAIN_CMDLINE="${MAIN_CMDLINE/ splash/}"
	declare -g MAIN_CMDLINE="${MAIN_CMDLINE/ plymouth.ignore-serial-consoles/}"
	display_alert "$BOARD" "Plymouth disabled" "info"
}

# Vendor WCN / AGDSP firmware.
#
# Four drivers request_firmware() these; without them Wi-Fi, Bluetooth and audio
# are all dead and the boot stalls ~70s waiting on the sysfs fallback:
#
#   agdsp.bin                      drivers/soc/sprd/sprd-audcp-boot.c  (built-in!)
#   wcnmodem.bin                   the marlin3 CP2 image (Wi-Fi + BT)
#   sprd/bt_configure_pskey.ini    drivers/bluetooth/btsprd_hci.c
#   sprd/bt_configure_rf.ini       drivers/bluetooth/btsprd_hci.c
#   sprd/wifi_board_config.ini     drivers/net/wireless/unisoc/sdio.c
#
# They go under /lib/firmware/updates rather than /lib/firmware: the
# armbian-firmware package already owns /lib/firmware/wcnmodem.bin as a symlink to
# the UWE5622 blob (a different chip), and writing through that symlink would
# corrupt the file it points at. The kernel firmware loader searches
# /lib/firmware/updates FIRST, so this overrides cleanly with no dpkg conflict and
# survives an armbian-firmware upgrade.
#
# sprd-audcp-boot is built-in (CONFIG_SPRD_AUDCP_BOOT=y) and probes at ~0.45s,
# long before the rootfs is mounted, so agdsp.bin must also be inside the initrd -
# hence the initramfs-tools hook. This runs after armbian-firmware is installed
# (distro-agnostic.sh) and before update_initramfs (rootfs-to-image.sh), so the
# build's own update-initramfs picks the hook up.
function post_family_tweaks__anbernic_rg_rotate_wcn_firmware() {
	display_alert "$BOARD" "installing sprd WCN/AGDSP firmware" "info"

	declare blobs="${SRC}/packages/blobs/sprd-ums512"
	[[ -d "${blobs}" ]] || exit_with_error "Missing sprd firmware blobs" "${blobs}"

	# Named explicitly, not a glob: every file here has a driver that asks for
	# it by that exact name (see the list above). A blob nobody requests is dead
	# weight in every image, and a glob makes that impossible to notice.
	declare -a fw=(agdsp.bin wcnmodem.bin sprd/bt_configure_pskey.ini
		sprd/bt_configure_rf.ini sprd/wifi_board_config.ini)
	declare f

	run_host_command_logged mkdir -p "${SDCARD}/lib/firmware/updates/sprd"
	for f in "${fw[@]}"; do
		[[ -f "${blobs}/${f}" ]] || exit_with_error "Missing sprd firmware blob" "${blobs}/${f}"
		run_host_command_logged cp -v "${blobs}/${f}" "${SDCARD}/lib/firmware/updates/${f}"
	done

	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/hooks"
	cat <<- 'INITRAMFS_HOOK' > "${SDCARD}/etc/initramfs-tools/hooks/sprd-firmware"
		#!/bin/sh
		PREREQ=""
		prereqs() { echo "$PREREQ"; }
		case "$1" in prereqs) prereqs; exit 0 ;; esac
		. /usr/share/initramfs-tools/hook-functions

		# ONLY agdsp.bin. sprd-audcp-boot is built-in and probes at ~0.45s, before
		# the rootfs is mounted, so its firmware has to be in the initrd.
		#
		# Do NOT add wcnmodem.bin here. The WCN core is built-in too
		# (CONFIG_UNISOC_WCN_BSP=y) and, once agdsp no longer stalls the initcalls for
		# 62s, it probes at ~6s - inside the initramfs, while udev is running. With the
		# firmware reachable it commits to the full marlin bring-up: 3-second
		# at-command timeouts plus an mmc1 SDHCI interrupt storm, which keeps the udev
		# queue busy for over a minute. scripts/init-bottom/udev runs under "set -e",
		# so its "udevadm settle --timeout=60" failing aborts the script before it
		# moves /dev onto the real root, and /init then dies on
		# "can't open /root/dev/console" -> "Kernel panic: Attempted to kill init!".
		# Without the firmware the same code gives up in ~10s
		# ("no find wcnmodem.bin errno:(-2)(ignore!!)") and the boot proceeds; Wi-Fi
		# comes up properly after switch_root, when sc23xx_wlan_sdio loads and finds
		# the firmware on the rootfs.
		for f in /lib/firmware/updates/agdsp.bin; do
			[ -f "$f" ] && copy_file firmware "$f" "$f"
		done
		exit 0
	INITRAMFS_HOOK
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/hooks/sprd-firmware"
}

# Keep the WCN (Wi-Fi/BT) driver out of the initrd.
#
# initramfs-tools defaults to MODULES=most, which pulls all of drivers/net into
# the initrd - including sc23xx_wlan_sdio. udev then probes it inside the
# initramfs, where marlin's power-up sequence burns a minute-plus on atcmd
# timeouts (WCN BASE error: wcn_send_atcmd,Timeout(3 sec) ... / WCN MEM_PD error)
# and never lets the udev queue drain:
#
#   Timed out while waiting for udev queue to empty.
#   /init: line 389: can't open /root/dev/console: no such file
#   Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
#
# i.e. the wedged udev takes the /dev move to the real root down with it and the
# board never boots. Nothing in the root path needs a module anyway - MMC,
# MMC_BLOCK, MMC_SDHCI, MMC_SDHCI_SPRD and EXT4_FS are all built-in - so MODULES=dep
# resolves to an empty module set. It also shrinks the initrd, which matters here:
# the vendor U-Boot reads the SD at ~2.5 MiB/s, so a 15 MiB uInitrd costs 6s of
# boot before the kernel even starts.
#
# conf.d/ is sourced after initramfs.conf, so this overrides the default without
# editing a file initramfs-tools owns.
function post_family_tweaks__anbernic_rg_rotate_initramfs_modules() {
	display_alert "$BOARD" "initrd: MODULES=dep (keep WCN out of early boot)" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/conf.d"
	cat <<- 'INITRAMFS_CONF' > "${SDCARD}/etc/initramfs-tools/conf.d/rg-rotate.conf"
		MODULES=dep
	INITRAMFS_CONF
}

# Make the initramfs survive a stuck udev queue.
#
# Ubuntu's udev ships scripts/init-bottom/udev as "#!/bin/sh -e" with a bare
# "udevadm settle --timeout=60". On this board the udev queue does not drain
# in time during early boot (the built-in WCN core, CONFIG_UNISOC_WCN_BSP=y, is
# busy on mmc1 at that point), so settle returns non-zero, "set -e" aborts the
# script before it reaches "mount -o move /dev ${rootmnt}/dev", and /init then
# dies at line 389 on:
#
#   /init: line 389: can't open /root/dev/console: no such file
#   Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100
#
# Debian trixie images booted through the same stall, so the queue itself is a
# separate (slow-boot) problem; this only stops it from being fatal. Everything
# below the settle is upstream's script verbatim. initramfs-tools takes a script
# under /etc/initramfs-tools/scripts/ over the /usr/share copy of the same name.
function post_family_tweaks__anbernic_rg_rotate_initramfs_udev() {
	display_alert "$BOARD" "initrd: bounded udevadm settle in init-top/init-bottom" "info"
	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/scripts/init-bottom"
	cat <<- 'INIT_BOTTOM_UDEV' > "${SDCARD}/etc/initramfs-tools/scripts/init-bottom/udev"
		#!/bin/sh
		# Board override of /usr/share/initramfs-tools/scripts/init-bottom/udev:
		# no "set -e", and a short, non-fatal settle. See the Armbian board config.

		PREREQS=""

		prereqs() { echo "$PREREQS"; }

		case "$1" in
		    prereqs)
		    prereqs
		    exit 0
		    ;;
		esac

		# Stop udevd, we'll miss a few events while we run init, but we catch up.
		# Do not let a still-busy queue abort this script: /dev MUST be moved
		# below, or /init cannot open ${rootmnt}/dev/console and the kernel panics.
		if ! udevadm settle --timeout=0 > /dev/null 2>&1; then
		    echo "udev queue not empty; continuing anyway" > /dev/kmsg
		fi
		udevadm control --exit || true

		# move the /dev tmpfs to the rootfs; fall back to util-linux mount that does
		# not understand -o move
		mount -n -o move /dev "${rootmnt:?}/dev" || mount -n --move /dev "${rootmnt}/dev"

		# create a temporary symlink to the final /dev for other initramfs scripts
		if command -v nuke >/dev/null; then
		    nuke /dev
		else
		    # shellcheck disable=SC2114
		    rm -rf /dev
		fi
		ln -s "${rootmnt}/dev" /dev
	INIT_BOTTOM_UDEV
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/scripts/init-bottom/udev"

	# Same story one script earlier: init-top/udev ends with a bare
	# "udevadm settle", i.e. the 120-second default. The queue does not drain
	# on this board, so the initramfs sat there for the full timeout before it
	# even looked at the root filesystem - 120 of the 137 seconds systemd
	# attributes to "kernel":
	#
	#   udev started        ~6.5s
	#   EXT4-fs (mmcblk0p3): mounted filesystem   126.8s
	#
	# Nothing here needs a settled queue: MODULES=dep leaves the initrd with no
	# modules at all, the root device node comes from devtmpfs, and scripts/local
	# does its own wait_for_udev plus a retry loop when resolving root=UUID=.
	#
	# The queue never drains on this board - the built-in WCN BSP (UNISOC_WCN_BSP,
	# SC23XX, SC2355, SDIOHAL) keeps events outstanding for the whole initramfs -
	# so a bounded settle just spends its whole budget every boot. At --timeout=10
	# that was 10s here plus another 10s in init-bottom, i.e. 20 of the 26.5s
	# systemd attributed to "kernel":
	#
	#   udev started                                ~6s
	#   Timed out while waiting for udev queue ...   16s   (init-top, 10s budget)
	#   udev queue still busy after 10s ...          26s   (init-bottom, 10s budget)
	#
	# Making the WCN Wi-Fi and Bluetooth drivers modules did not change this, so
	# stop paying for a wait nothing depends on: --timeout=0 checks the queue and
	# returns immediately. If something did turn out to need it, the root would not
	# be found and the board would not boot - a loud, immediate failure rather than
	# a subtle one. Everything else is upstream's script verbatim.
	run_host_command_logged mkdir -p "${SDCARD}/etc/initramfs-tools/scripts/init-top"
	cat <<- 'INIT_TOP_UDEV' > "${SDCARD}/etc/initramfs-tools/scripts/init-top/udev"
		#!/bin/sh -e
		# Board override of /usr/share/initramfs-tools/scripts/init-top/udev:
		# the settle below is bounded. See the Armbian board config.

		PREREQS=""

		prereqs() { echo "$PREREQS"; }

		case "$1" in
		    prereqs)
		    prereqs
		    exit 0
		    ;;
		esac

		if [ -w /sys/kernel/uevent_helper ]; then
			echo > /sys/kernel/uevent_helper
		fi

		if [ "${quiet:-n}" = "y" ]; then
			log_level=notice
		else
			log_level=info
		fi

		SYSTEMD_LOG_LEVEL=$log_level /usr/lib/systemd/systemd-udevd --daemon --resolve-names=never

		udevadm trigger --type=subsystems --action=add
		udevadm trigger --type=devices --action=add
		# --timeout=0 only samples the queue, so this costs nothing; silence it
		# because udevadm prints its own error on a non-empty queue and this
		# board's console is the panel.
		udevadm settle --timeout=0 > /dev/null 2>&1 || true

		# Leave udev running to process events that come in out-of-band (like USB
		# connections)
	INIT_TOP_UDEV
	run_host_command_logged chmod +x "${SDCARD}/etc/initramfs-tools/scripts/init-top/udev"
}

# USB-gadget serial console login: this board has no physical UART, so the
# ttyGS0 getty is the only way in before the panel comes up.
#
# The drop-in is not optional. systemd-executor sets up the unit's terminal in
# the forked child before execve(), and it holds an exclusive BSD lock on
# /dev/console while it does so. ttyGS0 is a USB gadget port: with no host
# attached the child parks in the TTY setup and never reaches exec, so the
# console lock is held for the life of the boot:
#
#   $ cat /proc/locks
#   2: FLOCK ADVISORY WRITE 1198 00:07:13 0 EOF        <- (agetty), pre-exec
#   2: ->  FLOCK ADVISORY WRITE  1 00:07:13 0 EOF      <- systemd, blocked
#
#   $ lslocks
#   systemd      1 FLOCK WRITE*  /dev/console
#   (agetty)  1198 FLOCK WRITE   /dev/console
#
# Nothing notices until PID 1 itself wants the console - which happens the
# first time getty@tty1 is stopped or replaced, i.e. exactly when
# armbian-firstlogin finishes on the panel. PID 1 then blocks forever in
# flock(LOCK_EX):
#
#   /proc/1/syscall: 32 0x2c 0x2 ...   (32 = flock, fd 44 = /dev/console)
#   /proc/1/stack:   locks_lock_inode_wait <- __do_sys_flock
#
# and every request that needs PID 1 times out: dbus activation
# ("Failed to activate service 'org.freedesktop.timedate1': timed out"),
# logind session scopes ("Varlink call io.systemd.Login.CreateSession failed"),
# and systemctl itself ("Transport endpoint is not connected"). Already-running
# processes keep going, so the panel and X look fine while the first boot is
# quietly unable to create the user account.
#
# Clearing TTYPath keeps the executor away from the terminal entirely and lets
# agetty open ttyGS0 itself - it uses O_NONBLOCK, and --local-line sets CLOCAL,
# so it waits for the host without holding anything. Verified on hardware:
# "lslocks | grep console" comes back empty, ps shows a real exec'd agetty
# rather than the "(agetty)" stub, and stopping getty@tty1 no longer wedges
# PID 1.
function post_family_tweaks__anbernic_rg_rotate_console() {
	display_alert "$BOARD" "enabling ttyGS0 console" "info"
	mkdir -p "${SDCARD}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/serial-getty@.service \
		"${SDCARD}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

	display_alert "$BOARD" "ttyGS0: keeping systemd-executor off the gadget TTY" "info"
	run_host_command_logged mkdir -p \
		"${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d"
	cat <<- 'GADGET_TTY' > "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d/10-gadget-nonblocking.conf"
		# See the Armbian board config for why this exists: without it,
		# systemd-executor blocks in the pre-exec TTY setup of this unit while
		# holding the exclusive flock on /dev/console, and PID 1 deadlocks on
		# that lock the first time it needs the console.
		[Service]
		TTYPath=
		TTYReset=no
		TTYVHangup=no
		StandardInput=null
		StandardOutput=journal
		StandardError=journal
		ExecStart=
		ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud --local-line 115200,57600,38400,9600 ttyGS0 $TERM
	GADGET_TTY
}

# Speaker routing.
#
# The card comes up silent: the DAC -> HPL/HPR -> headphone-pin path and the
# AGDSP's VBC profile are all off at their defaults. The recipe below is the
# idle -> playing delta captured from stock Android (docs/stock_mixer_{idle,
# during}.txt in beebono/rg-rotate-linux) plus "DSP VBC Profile Select", which
# stock already has set while idle.
#
# This is a script rather than an asound.state because alsactl cannot carry it.
# Several of the controls take a write but read back 0 - they are commands to
# the DSP, not stored state - so "alsactl store" records zeros and a restore
# reproduces silence:
#
#   DSP VBC Profile Select   written 961216512 -> cget values=0
#   DAC Gain DAC Playback    written 3         -> cget values=0
#   HPL Gain HPL Playback    written 4         -> cget values=0
#
# Speaker output goes through the codec's headphone mixers, not the SC2730
# class-D SPK pin, so SPKL Gain / SPKL Mixer stay off deliberately. The
# external AW87391 PA is driven over i2c2 from inside aw87390.c and exposes no
# mixer control here, which is why nothing below touches it.
# Gamepad-to-keyboard remap (bsp-cli payload).
function post_family_tweaks__anbernic_rg_rotate_helpers() {
	display_alert "$BOARD" "enabling rotate-pad2key" "info"

	# There is no keyboard, no mouse and no broken-out UART on this board:
	# the only inputs are the gamepad GPIOs and the touchscreen. Without the
	# remap running by default a desktop session cannot be driven at all, so
	# unlike on a machine with a keyboard this is enabled out of the box.
	# rotate-pad2key-toggle turns it off again for games, and is on the
	# applications menu.
	run_host_command_logged mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	run_host_command_logged ln -sf /etc/systemd/system/rotate-pad2key.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rotate-pad2key.service"
}

# rotate-wcn-nosleep ships but is NOT enabled. It writes "at+debug=1" through
# the sprdwcn sysfs knob to keep the Wi-Fi CP2 out of deep sleep, which costs
# measurably more than it buys on a battery device.
#
# What it buys: the first 1-2 s of outbound traffic after an idle period is
# otherwise lost or delayed (ping seq 1 gone, seq 2 at 1.2-2.2 s, then normal).
# That is all it buys. The board dropping off the LAN entirely after a few
# minutes idle looked like the same bug and is not - it was the firmware never
# being told the interface's IPv4 address, so it delivered no broadcast to the
# host and a peer's ARP request was never answered. That is fixed properly, in
# general-sc23xx-wlan-notify-the-firmware-of-the-ipv4-address.patch.
#
# What it costs, measured on hardware (backlight off, associated and idle,
# three runs of 2 minutes per state, interleaved 1/0/1 to cancel baseline
# drift): about 10 mA on top of a ~114 mA idle draw. Against this board's
# 1900 mAh battery that is 16.6 h of standby down to 15.3 h, so roughly 8%,
# for a 1-2 s latency nicety.
#
# So it is left to the user:
#
#   systemctl enable --now rotate-wcn-nosleep.service
#
# The service is a oneshot; the udev rule and the system-sleep hook that ship
# with it re-apply the setting on wlan0 re-add and after resume, since a CP2
# reboot loses it. See the script header for the rest.

function post_family_tweaks__anbernic_rg_rotate_audio() {
	display_alert "$BOARD" "enabling speaker routing" "info"

	# The card exposes twelve DSP front ends and no plain "analog out", so with
	# no UCM profile the ALSA card-profile fallback probes front:0 /
	# surround40:0 and so on, finds none of them, and PipeWire is left with a
	# Dummy sink only. Speaker playback is device 3, FE_ST_FAST - the DSP/MCDT
	# fast playback front end. Device 0 (FE_ST_NORMAL_AP01), the AP-direct VBC
	# FIFO path, is NOT usable here: its converter runs at half the rate the
	# FIFO is drained at, so it plays an octave low with a click on every
	# period boundary.
	#
	# The UCM profile, the WirePlumber constraints, the boot-time mixer setup,
	# rotate-audio-prime and rotate-audio-test all ship in the bsp-cli
	# package. rotate-audio-prime needs pw-cat, which comes with PipeWire and
	# so is there on a desktop image; it checks and does nothing if PipeWire
	# is not installed, which is the right answer for a CLI image that has no
	# session to prime. The profile is
	# installed under four names because alsa-lib resolves the directory from
	# whatever the caller opened the card with: alsaucm and aplay use the card
	# id (sprdphonesc2730), PipeWire's ACP lands on the long name
	# (sprdphone-sc2730), and ucm.conf's ${CardDriver} lookups see the driver
	# string - which is "sprdphone-sc2730" truncated to sprdphone-sc273,
	# because struct snd_card::driver is 16 bytes. That last one is reached
	# through both ucm2/ and ucm2/conf.d/ depending on the If.V2Name branch.
	#
	# alsa-restore replays the controls alsactl can read; rotate-audio runs
	# after it and sets the DSP-side ones it cannot.
	#
	# rotate-audio.service is pulled in from the card's own uevent
	# (80-rotate-audio.rules) as well as by multi-user.target: card
	# registration waits on the AGDSP and on deferred probe, so it can land
	# after multi-user.target is reached, and the unit's ConditionPathExists
	# would then skip it for good - a failed condition is never retried.
	#
	# rotate-audio-prime, a user unit in the same package, deals with the
	# audio DSP swallowing one VBC scene start per boot. The start that goes
	# missing is the one PipeWire issues when it resumes the sink, and it is
	# specific to that stream - opening hw:0,3 directly does not stand in for
	# it - so whatever the user plays first is what loses it and the board
	# looks like it has no sound. Opening pavucontrol clears it, because
	# pavucontrol attaches a monitor stream to draw its level meters, which
	# resumes the sink and spends the bad start without anyone noticing. The
	# unit does that deliberately at session start, with silence.
	run_host_command_logged mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	run_host_command_logged ln -sf /etc/systemd/system/rotate-audio.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/rotate-audio.service"
}
