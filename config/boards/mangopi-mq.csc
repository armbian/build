# Allwinner D1 single core (C906) 512MB/1GB RAM WiFi/BT HDMI
BOARD_NAME="Mangopi-MQ"
BOARD_VENDOR="mangopi"
BOARDFAMILY="d1"
BOARD_MAINTAINER=""
INTRODUCED="2021"
KERNEL_TARGET="edge"
BOOT_FDT_FILE="allwinner/sun20i-d1-mangopi-mq-pro.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG="nezha_defconfig"

enable_extension "mangopi-source-boot"
enable_extension "mangopi-rtc"

enable_extension "grub-riscv64"
enable_extension "mangopi-grub"
