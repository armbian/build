setenv fdt_filename "${pine64_model}.dtb"
run load_dtb
fatload mmc 0:1 ${kernel_addr} Image
run load_initrd

setenv bootargs "console=ttyS0,115200n8 no_console_suspend earlycon=uart,mmio32,0x01c28000 mac_addr=${ethaddr} root=${root} rootwait panic=10 consoleblank=0 enforcing=0 loglevel=7"

run boot_kernel

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
