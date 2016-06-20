Enable Hardware Features
========================

Some boards require some manual configuration to turn on/off certain features

In some cases, the procedure is "less than obvious", so we document some basic examples here.

# Generic howto for Allwinner devices

## Legacy or Vanilla kernel ?

Many Armbian images come in two flavours : Legacy (using an older kernel version) and Vanilla (up-to-date kernel). Depending on kernel version, the procedure to enable/disable features is not the same :
 * Legacy kernel : FEX
 * Vanilla kernel : DT (Device Tree)

## What flavour am I using ?

Best way to know is by checking your kernel version :

```
root@bananapipro:~# uname -a
Linux bananapipro 4.5.2-sunxi #11 SMP Thu Apr 28 21:53:25 CEST 2016 armv7l GNU/Linux
```

In this example the kernel version is 4.5.2 so you can use DT to tweak some settings. If you get a kernel version 3.X then you'll be certainly using FEX.

# H3 based Orange Pi, legacy kernel

## Enable serial /dev/ttyS3 on pins 8 and 10 of the 40 pin header

Update the FEX configuration (which is compiled into a .bin) located at /boot/script.bin

Decompile .bin to .fex
```
cd /boot
bin2fex script.bin > custom.fex
rm script.bin # only removes symbolic link
```

Edit .fex file
```
[uart3]
uart_used = 1 ; Change from 0 to 1
uart_port = 3
uart_type = 2 ; In this case we have a 2 pin UART
uart_tx = port:PA13<3><1><default><default>
uart_rx = port:PA14<3><1><default><default>
```

Compile .fex to .bin
```
fex2bin custom.fex > script.bin
```

Reboot

Notice that /dev/ttyS3 appears. That is your new UART device.

****
