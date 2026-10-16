# Realtek RTD129x eMMC boot parts

The factory eMMC boot area of a BananaPi BPI-W2, as Banana Pi installs it:
hwsetting (DRAM setup), FSBL, TEE and BL31. Each file is the data of one
part, without its SHA-256 padding and digest. FSBL, TEE and BL31 are
encrypted by Realtek.

`mkbootarea.py` puts them together with a U-Boot into the boot area that
the BPI-W2 SPI loader reads from eMMC byte 0x20000.
