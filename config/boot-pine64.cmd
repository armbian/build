if fatload mmc 0:1 .next; then
	setenv fdt_filename "dtb/allwinner/sun50i-a64-${pine64_model}.dtb"
	setenv bootargs "console=ttyS0,115200 root=${root} rootwait panic=10 consoleblank=0 enforcing=0 loglevel=2"
else
	setenv fdt_filename "${pine64_model}.dtb"
	setenv bootargs "console=ttyS0,115200n8 no_console_suspend earlycon=uart,mmio32,0x01c28000 mac_addr=${ethaddr} root=${root} rootwait panic=10 consoleblank=0 enforcing=0 loglevel=2"
fi

setenv kernel_filename Image

run load_dtb load_kernel load_initrd boot_kernel

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
