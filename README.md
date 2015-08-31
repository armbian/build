# What is Armbian? #

Universal operating system for a selection of ARM single board computers. It's more or less pure **Debian / Ubuntu** with dedicated kernel and small modifications to operating system.

Currently supported boards / kernels:

	- Cubieboard 1,2,3				3.4.x and mainline
	- BananaPi / PRO / R1			3.4.x and mainline
	- Cubox, Hummingboard			3.14.x and mainline
	- Linksprite Pcduino3 nano		3.4.x and mainline
	- Olimex Lime, Lime 2, Micro 	3.4.x and mainline
	- Orange Pi, mini				3.4.x and mainline
	- Udoo quad						3.14.x and 4.0.8
	- Udoo Neo						3.14.x

## General workflow: ##

1. Download host tools and sources
3. Patch, compile and debootstrap to image
4. Update repository [optional]

## Features: ##
- Debian Wheezy, Jessie or Ubuntu Trusty based.
- CLI and one - Jessie or Trusty - lightweight XFCE based desktop per board with HW acceleration (where avaliable). Preinstalled Wicd,  Firefox, LibreOffice Writer, Thunderbird. No login manager - autologin to root. (Change: /etc/defaults/nodm)
- Community backed kernel with large hardware support and headers. 
- Board / wireless firmware included where needed.
- Build ready – possible to compile external modules.
- Kernel, u-boot and customizations are (auto)upgrading within system.
- Distributions upgrade ready.
- hostapd ready with optimized configuration and [manually build binaries](https://github.com/igorpecovnik/hostapd)
- ethernet adapter with DHCP and SSH server ready on default port (22) with regenerated keys @ first boot
- SD image is big as actual size (around 1G) and auto resized to maximum size @first boot
- XFCE desktop version with autologin and upgrade ready, some with hardware acceleration.
- SATA & USB install script included (/root)
- serial console enabled
- root password is 1234. You will be prompted to change it at first login
- enabled automatic security updating and ready for kernel apt-get updating
- login script shows board MOTD with current board temp (if avaliable), hard drive temp, ambient temp from Temper(if avaliable) and battery charge ratio (if avaliable) & actual free memory
- Performance tweaks:
	- /tmp & /log = RAM, ramlog app saves logs to disk daily and on shut-down (ramlog is only in Wheezy, others have default logger)
	- automatic IO scheduler. (check /etc/init.d/armhwinfo)
	- journal data writeback enabled. (/etc/fstab)
	- commit=600 to flush data to the disk every 10 minutes (/etc/fstab)
	- eth0 interrupts are using dedicated core (some boards)


## How much for Armbian? ##

- The operating system is free, 
- Upgrade is free,
- Technical support is free.

It's your call. 

[![Paypal donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=CUYH2KR36YB7W)

Thank you!

## Where to download images? ##

[http://www.armbian.com](http://www.armbian.com "Armbian universal operating system")

Armbian is avaliable as SD card image.

## How to build Armbian? ##

Please check this [manual](https://github.com/igorpecovnik/lib/blob/next/documentation/geek-faq.md).


## Support ##


- [Using Armbian FAQ](https://github.com/igorpecovnik/lib/blob/next/documentation/user-faq.md)
- [Forums on http://forum.armbian.com/](http://forum.armbian.com/ "Armbian support forum")
- [Allwinner SBC community](https://linux-sunxi.org/)
