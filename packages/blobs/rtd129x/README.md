# Realtek RTD129x eMMC boot parts

The eMMC boot area parts of a BananaPi BPI-W2: hwsetting (DRAM setup),
FSBL, TEE and BL31. Each file is the data of one part, without its SHA-256
padding and digest. FSBL, TEE and BL31 come from the factory eMMC boot area
and are encrypted by Realtek.

`hwsetting.bin` is generated from Realtek's
`RTD1296_hwsetting_BOOT_4DDR4_4Gb_s1866.config` (chip type 0002) with the
`generate_config` tool from the BPI-W2 BSP
(`u-boot-rtk/examples/flash_writer/tools/hw_setting_maker`). It is the same
file as the hwsetting in the BPI-W2 SPI NOR loader.
The BPI-W2 has four DDR4 chips on two DRAM controllers. A hwsetting for one
controller decodes only 1 GiB: the upper 1 GiB then aliases the lower one.

`mkbootarea.py` puts them together with a U-Boot into the boot area that
the BPI-W2 SPI loader reads from eMMC byte 0x20000.
