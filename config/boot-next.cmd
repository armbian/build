# Armbian universal u-boot script

# check if we have separate boot partition
# or one root partition
if ext4load mmc 0 0x00000000 /boot/boot.scr
then
  setenv rootdev "/dev/mmcblk0p1"
else
  setenv rootdev "/dev/mmcblk0p2"
fi

# quick way to enable serial console at first boot
if ext4load mmc 0 0x00000000 /boot/.enable_ttyS0 || ext4load mmc 0 0x00000000 .enable_ttyS0 || fatload mmc 0 0x00000000 .enable_ttyS0
then
  setenv extra_serial "console=ttyS0,115200"
fi

# ${extra} allows passing additional parameters to default boot script from u-boot command prompt, i.e.
# setenv extra "init=/bin/bash console=ttyS0,115200"
# boot

setenv bootargs "console=tty1 ${extra_serial} root=${rootdev} rootwait sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 hdmi.audio=EDID:0 disp.screen0_output_mode=1920x1080p60 panic=10 consoleblank=0 enforcing=0 loglevel=1 ${extra}"
#--------------------------------------------------------------------------------------------------------------------------------
# Boot loader script to boot with different boot methods for old and new kernel
#--------------------------------------------------------------------------------------------------------------------------------
if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next || ext4load mmc 0 0x00000000 .next
then
# sunxi mainline kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x49000000 /boot/dtb/${fdtfile} || fatload mmc 0 0x49000000 /dtb/${fdtfile} || ext4load mmc 0 0x49000000 /dtb/${fdtfile}
ext4load mmc 0 0x46000000 /boot/zImage || fatload mmc 0 0x46000000 zImage || ext4load mmc 0 0x46000000 zImage
env set fdt_high ffffffff
bootz 0x46000000 - 0x49000000
#--------------------------------------------------------------------------------------------------------------------------------
else
# sunxi android kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x43000000 /boot/script.bin || fatload mmc 0 0x43000000 script.bin || ext4load mmc 0 0x43000000 script.bin
ext4load mmc 0 0x48000000 /boot/zImage || fatload mmc 0 0x48000000 zImage || ext4load mmc 0 0x48000000 zImage
bootz 0x48000000
#--------------------------------------------------------------------------------------------------------------------------------
fi
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 