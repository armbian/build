The Banana Pi M2 Berry is the Allwinner V40 sibling of the Banana Pi M2 Ultra (R40). It shares most of the Ultra's hardware but has no onboard eMMC, so it boots from a microSD card.

**Getting started**

- Flash the image to a good-quality microSD card and use a reliable 5V/2A power supply. Weak supplies are a common cause of boot problems.
- First boot takes a few minutes while the filesystem is resized. Connect Ethernet and find the board in your router's device list, then log in over SSH.

**Hardware notes**

- **LEDs:** two controllable LEDs, `bananapi:green:user` and `bananapi:red:pwr`. Set a trigger with, for example:
  `echo disk-activity > /sys/class/leds/bananapi:green:user/trigger`
- **Ethernet:** Gigabit, interface `end0`.
- **Wi-Fi / Bluetooth:** onboard AP6212 module (BCM43430). Wi-Fi works as `wlan0`. The kernel log shows a missing board-specific firmware file at boot, but the driver falls back to the generic firmware.
- **Bluetooth:** the kernel log shows `failed to write update baudrate (-110)` at boot. This is non-fatal: the chip is detected, its firmware patch loads, and Bluetooth works at the default UART speed.
- **SATA:** available, as on the M2 Ultra.
