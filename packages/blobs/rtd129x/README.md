# Realtek RTD129x eMMC boot parts

The factory eMMC boot area of a BananaPi BPI-W2, as Banana Pi installs it:
hwsetting (DRAM setup), FSBL, TEE and BL31. Each file is the data of one
part, without its SHA-256 padding and digest. FSBL, TEE and BL31 are
encrypted by Realtek.

`mkbootarea.py` puts them together with a U-Boot into the boot area that
the BPI-W2 SPI loader reads from eMMC byte 0x20000.

# Audio firmware

U-Boot starts it on the audio CPU before Linux. It runs the audio and the
HDMI output. The family installs it as `/boot/bluecore.audio`.

| File | SoC | Source | SHA-256 |
|---|---|---|---|
| `bluecore-rtd1296.audio` | RTD1295/RTD1296 | [BPI-W2-bsp@6e6aefc3](https://github.com/BPI-SINOVOIP/BPI-W2-bsp/blob/6e6aefc35dc50b1b8231cdb03a995d088f29eb21/rtk-pack/rtk/bpi-w2/configs/default/linux/bluecore.audio) | `59252270f05cc55cba0ddeb246bc7c6b20dab9554fa18be4e9595ea549fd9b1c` |
