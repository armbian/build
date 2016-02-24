# Armbian H3 mini FAQ

**OS images with legacy Kernel (3.4.110)**

Armbian supports starting with release 5.04 all available H3 based Orange Pi boards (also [One](http://forum.armbian.com/index.php/topic/724-quick-review-of-orange-pi-one/) and Lite when available). Compared to the preliminary releases the following has been fixed:

- HDMI/DVI works (bug in boot.cmd settings)
- Reboot issues fixed (bug in fex settings)
- 1-Wire useable (we chose to stay compatible to loboris' images so the data pin is 37 by default. You can change this in the [fex file](https://github.com/igorpecovnik/lib/blob/6d995e31583e5361c758b401ea44634d406ac3da/config/orangepiplus.fex#L1284-L1286)
- changing display resolution and choosing between HDMI and DVI now possible with the included _h3disp_ tool (should also work in the [stand-alone version](http://forum.armbian.com/index.php/topic/617-wip-orange-pi-one-support-for-the-upcoming-orange-pi-one/?p=5480) with Debian based OS images from loboris/Xunlong)
- Ethernet issues fixed (combination of kernel and fex fixes)
- USB-to-SATA bridge on the Orange Pi Plus works
- stability problems on Orange Pi One fixed (due to undervoltage based on wrong fex settings)
- problems with 2 USB ports on the PC fixed (wrong kernel config)
- already useable as stable headless/server board

***Important to know***

- [User documentation](http://www.armbian.com/documentation/)
- [Geek documentation](http://www.armbian.com/using-armbian-tools/)
- 1st boot takes longer (up to 5 minutes). Please do not interrupt while the red LED is blinking, the board reboots automatically one time
- CPU frequency settings are 648-1200 MHz on OPi One/Lite and 480-1296 MHz on the other boards (cpufreq governor is _interactive_ therefore the board only increases CPU speed and consumption when needed)
- These are still test images regarding everything beyond headless/server usage
- In case you experience instabilities, think about installing [RPi-Monitor for H3](http://forum.armbian.com/index.php/topic/617-wip-orange-pi-one-support-for-the-upcoming-orange-pi-one/?p=5076) to get an idea whether you suffer from overheating

***Areas that need testing***

- SPI
- I2C
- GPIO in general
- GPU acceleration (needs _boot.cmd_ adjustments and at least _mali_ module loaded)
- Wi-Fi on OPi Plus, Plus 2 and 2
- USB wireless dongles

***What you can do to improve the situation***

- improve software support for Orange Pi One by [testing DRAM reliability](http://forum.armbian.com/index.php/topic/617-wip-orange-pi-one-support-for-the-upcoming-orange-pi-one/?p=5455)!
- get back to us with [feedback regarding our OS images](http://forum.armbian.com/index.php/topic/617-wip-orange-pi-one-support-for-the-upcoming-orange-pi-one/?view=getlastpost)
- fork our repo, fix things and send pull requests

***Known to *not* work yet***

- camera support. We included [@lex' patches](http://www.orangepi.org/orangepibbsen/forum.php?mod=redirect&goto=findpost&ptid=443&pid=7263) but miss [phelum's basic patches](http://www.orangepi.org/orangepibbsen/forum.php?mod=redirect&goto=findpost&ptid=70&pid=2905). Fixes welcome
- HW accelerated video decoding. Fixes welcome (anyone willing to port the stuff from the [H3 OpenELEC port](https://github.com/jernejsk/OpenELEC-OPi2)?)

**OS images with vanilla Kernel (4.x)**


