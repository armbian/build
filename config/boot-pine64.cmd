setenv fdt_filename "${pine64_model}.dtb"
setenv kernel_filename Image

setenv bootargs "console=ttyS0,115200n8 no_console_suspend earlycon=uart,mmio32,0x01c28000 mac_addr=${ethaddr} root=${root} rootwait panic=10 consoleblank=0 enforcing=0 loglevel=2"

run load_dtb load_kernel load_initrd boot_kernel

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
