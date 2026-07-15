# Allwinner H3 quad core 512MB RAM SoC Wi-Fi/BT
#
# FRAGILE / KNOWN ISSUE (u-boot v2026.07 sunxi bump): hangs deterministically
# mid-Linux-boot (same spot every time, around serial-console handoff). Ruled out:
# DRAM clock (672/408/360 all hang identically), power, CPU freq cap, single-core.
# Builds on the stock upstream defconfig (no Armbian DRAM override). Needs a deeper
# look (serial-console/FDT handoff or a board DT/cpufreq quirk) before it can be
# considered working again.
BOARD_NAME="Orange Pi Zero Plus 2"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
INTRODUCED="2017"
BOOTCONFIG="orangepi_zero_plus2_h3_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
DEFAULT_OVERLAYS="usbhost2 usbhost3"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
