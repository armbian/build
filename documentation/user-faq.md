# What to download?

Each board is fully supported with up to **three basic system** options: 
	
- Debian Wheezy
- Debian Jessie 
- Ubuntu Trusty

Some boards also have a desktop version of Ubuntu or Jessie.

# Legacy or Vanilla?

Both kernels are stable and production ready, but you should use them for different purpuses since their basic support differ:

 * for headless server or light desktop operations use vanilla kernel
 * for using video acceleration, NAND, ... you should stick to legacy

# How to check download authenticity?

All our images are digitally signed and therefore it's possible to check theirs authentication. You need to unzip the download package and issue those commands (Linux):

	# download my public key from the database
	gpg --keyserver pgp.mit.edu --recv-key 9F0E78D5
	gpg --verify Armbian_4.83_Armada_Debian_jessie_3.10.94.raw.asc
	
	# proper respond
	gpg: Signature made sob 09 jan 2016 15:01:03 CET using RSA key ID 9F0E78D5
	gpg: Good signature from "Igor Pecovnik (Ljubljana, Slovenia) <igor.++++++++++++@gmail.com>"	
	
	# wrong repond. Not genuine Armbian image!
	gpg: Signature made Sun 03 Jan 2016 11:46:25 AM CET using RSA key ID 9F0E78D5
	gpg: BAD signature from "Igor Pecovnik (Ljubljana, Slovenia) <igor.++++++++++++@gmail.com>"

It is safe to ignore WARNING: This key is not certified with a trusted signature!

# How to prepare SD card?

Unzipped .raw images can be written with supplied imagewriter.exe on Windows XP/2003/Win7, with [Rufus](https://rufus.akeo.ie) on Windows 8.x / 10 or with DD command in Linux/Mac:

	dd bs=1M if=filename.raw of=/dev/sdx
	# /dev/sdx is your sd card device

Image writting takes around 3 minutes on a slow, class 6 SD card.

Make sure you use **good & reliable** SD card. If you encounter boot troubles, check them with [F3](http://oss.digirati.com.br/f3/) or [H2testw](http://www.heise.de/download/h2testw.html).

# How to boot?

Insert SD card into a slot and power the board. First boot takes around 3 minutes then it reboots and you will need to wait another one minute to login. This delay is because system updates package list and creates 128Mb emergency SWAP on the SD card.

Normal boot (with DHCP) takes up to 35 seconds with a class 6 SD CARD and cheapest board.

# How to login? 

Login as **root** on console or via SSH and use password **1234**. You will be prompted to change this password at first login. This is the only pre-installed user.

Desktop images starts into desktop without asking for password. To change this add some display manager:

	apt-get install lightdm

... or edit the contents of file:

	/etc/default/nodm

and change the autologin user.

# How to update kernel?

	apt-get update
	apt-get upgrade
	reboot

Working on Armbian 4.2 and newer.

# How to upgrade kernel?

If you are running **legacy kernel** and you want to switch to **vanilla**, **development** or vice versa, you can do it this way:
	
	wget -q -O - http://upgrade.armbian.com | bash

You will be prompted to select and confirm some actions. It's possible to upgrade **from any other distribution**. Note that this procedure upgrades only kernel with hardware definitions (bin, dtb, firmware and headers. Operating system and modifications remain as is.

Check [this for manual way](http://www.armbian.com/kernel/) and more info.

[su_youtube_advanced url="https:\/\/youtu.be\/iPAlPW3sv3I" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

# How to troubleshoot?

If you broke the system you can try to get in this way. You have to get to u-boot command prompt, using either a serial adapter or monitor and usb keyboard. 

After switching power on or rebooting, when u-boot loads up, press some key on the keyboard (or send some key presses via terminal) to abort default boot sequence and get to the command prompt:

	U-Boot SPL 2015.07-dirty (Oct 01 2015 - 15:05:21)
	...
	Hit any key to stop autoboot:  0
	sunxi#

Enter these commands, replacing root device path if necessary. Select setenv line with ttyS0 for serial, tty1 for keyboard+monitor (these are for booting with mainline kernel, check boot.cmd for your device for commands related to legacy kernel):

	setenv bootargs init=/bin/bash root=/dev/mmcblk0p1 rootwait console=ttyS0,115200
	# or
	setenv bootargs init=/bin/bash root=/dev/mmcblk0p1 rootwait console=tty1

	ext4load mmc 0 0x49000000 /boot/dtb/${fdtfile}
	ext4load mmc 0 0x46000000 /boot/zImage
	env set fdt_high ffffffff
	bootz 0x46000000 - 0x49000000

System should eventually boot to bash shell:

	root@(none):/#

Now you can try to fix your broken system.


- [Fix a Jessie systemd problem due to upgrade from 3.4 to 4.x](https://github.com/igorpecovnik/lib/issues/111)

# How to unbrick the system?

When something goes terribly wrong and you are not able to boot the system, this is the way to proceed. You need some linux machine, where you can mount the failed SD card. With this procedure you will reinstall the u-boot, kernel and hardware settings. In most cases this should be enought to unbrick the board. It's recommended to issue a filesystem check before mounting:

	fsck /dev/sdX -f

Than mount the SD card and download those files (This example is only for Banana R1): 

	http://apt.armbian.com/pool/main/l/linux-trusty-root-next-lamobo-r1/linux-trusty-root-next-lamobo-r1_4.5_armhf.deb
	http://apt.armbian.com/pool/main/l/linux-upstream/linux-image-next-sunxi_4.5_armhf.deb
	http://apt.armbian.com/pool/main/l/linux-upstream/linux-firmware-image-next-sunxi_4.5_armhf.deb
	http://apt.armbian.com/pool/main/l/linux-upstream/linux-dtb-next-sunxi_4.5_armhf.deb

This is just an example for: **Ubuntu Trusty, Lamobo R1, Vanilla kernel** (next). Alter packages naming according to [this](http://forum.armbian.com/index.php/topic/211-kernel-update-procedure-has-been-changed/).

Mount SD card and extract all those deb files to it's mount point.

	dpkg -x DEB_FILE /mnt 

Go to /mnt/boot and link (or copy) **vmlinuz-4.x.x-sunxi** kernel file to **zImage**.

Unmount SD card, move it to the board and power on.

# How to add users?

To create a normal user do this:

	adduser MyNewUsername

Put user to sudo group:

	usermod -aG sudo MyNewUsername

# How to customize keyboard, time zone?

keyboard: 

	dpkg-reconfigure keyboard-configuration
	
system language: 

	dpkg-reconfigure locales

console font, codepage:

	dpkg-reconfigure console-setup

time zone: 

	dpkg-reconfigure tzdata
	
screen resolution: 

	nano /boot/boot.cmd 

	# example:
	# change example from 
	# disp.screen0_output_mode=1920x1080p60 
	# to 
	# disp.screen0_output_mode=1280x720p60

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr	

screen resolution interactive - only Allwinner boards with A10 and A20 with legacy kernel:
	
	# Example to set console framebuffer resolution to 1280 x 720
	a10disp changehdmimodeforce 4

Other modes:	

	0 480i
	1 576i
	2 480p
	3 576p
	4 720p 50Hz
	5 720p 60Hz
	6 1080i 50 Hz
	7 1080i 60 Hz
	8 1080p 24 Hz
	9 1080p 50 Hz
	10 1080p 60 Hz
	
# How to alter CPU frequency?

Some boards allow to adjust CPU speed.

	nano /etc/default/cpufrequtils

Alter **min_speed** or **max_speed** variable.

	service cpufrequtils restart

# How to upgrade into simple desktop environment?

	apt-get -y install xorg lightdm xfce4 tango-icon-theme gnome-icon-theme
	reboot


Check [this site](http://namhuy.net/1085/install-gui-on-debian-7-wheezy.html) for others.

# How to upgrade Debian from Wheezy to Jessie?

	dpkg -r ramlog	
	cp /etc/apt/sources.list{,.bak}
	sed -i -e 's/ \(old-stable\|wheezy\)/ jessie/ig' /etc/apt/sources.list
	apt-get update
	apt-get --download-only dist-upgrade
	apt-get dist-upgrade


# How to upgrade from Ubuntu Trusty to next LTS?

... when available.
	
	apt-get install update-manager-core
    do-release-upgrade -d
  	# further to vivid
	apt-get dist-upgrade

# How to toggle boot output?
Edit and change [boot parameters](http://redsymbol.net/linux-kernel-boot-parameters/) in /boot/boot.cmd:

    - console=ttyS0,115200
    + console=tty1

and convert it to boot.scr with this command:

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

Reboot.

Serial console on imx6 boards are ttymxc0 (Hummingboard, Cubox-i) or ttymxc1 (Udoo).

# How to install to NAND, SATA & USB?

[su_youtube_advanced url="https:\/\/youtu.be\/6So8MA-qru8" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

Required condition:

NAND:

 * kernel 3.4.x and NAND storage
 * pre-installed system on NAND (stock Android or other Linux)

SATA/USB:

 * any kernel
 * pre-partitioned SATA or USB storage

Start the install script: 

	nand-sata-install

and follow the guide. You can create up to three scenarios:

 * boot from SD, system on SATA / USB
 * boot from NAND, system on NAND
 * boot from NAND, system on SATA / USB

# How to change network configuration?

There are five predefined configurations, you can find them in those files:

	/etc/network/interfaces.default
	/etc/network/interfaces.hostapd	
	/etc/network/interfaces.bonding
	/etc/network/interfaces.r1
	/etc/network/interfaces.r1switch

By default **/etc/network/interfaces** is symlinked to **/etc/network/interfaces.default**

1. DEFAULT: your network adapters are connected classical way. 
2. HOSTAPD: your network adapters are bridged together and bridge is connected to the network. This allows you to have your AP connected directly to your router.
3. BONDING: your network adapters are bonded in fail safe / "notebook" way.
4. Router configuration for Lamobo R1 / Banana R1.
5. Switch configuration for Lamobo R1 / Banana R1.

You can switch configuration with re-linking.

	cd /etc/network
	ln -sf interfaces.x interfaces
(x = default,hostapd,bonding,r1)

Than check / alter your interfaces:

	nano /etc/network/interfaces

# How to set fixed IP?

By default your main network adapter's IP is assigned by your router DHCP server.

	iface eth0 inet dhcp 

change to - for example:

	iface eth0 inet static
	 	address 192.168.1.100
        netmask 255.255.255.0
		gateway 192.168.1.1

# How to set wireless access point?

There are two different hostap daemons. One is **default** and the other one is for some **Realtek** wifi cards. Both have their own basic configurations and both are patched to gain maximum performances.

Sources: [https://github.com/igorpecovnik/hostapd](https://github.com/igorpecovnik/hostapd "https://github.com/igorpecovnik/hostapd")

Default binary and configuration location:

	/usr/sbin/hostapd
	/etc/hostapd.conf
	
Realtek binary and configuration location:

	/usr/sbin/hostapd-rt
	/etc/hostapd.conf-rt

Since its hard to define when to use which you always try both combinations in case of troubles. To start AP automatically:

1. Edit /etc/init.d/hostapd and add/alter location of your conf file **DAEMON_CONF=/etc/hostapd.conf** and binary **DAEMON_SBIN=/usr/sbin/hostapd**
2. Link **/etc/network/interfaces.hostapd** to **/etc/network/interfaces**
3. Reboot
4. Predefined network name: "BOARD NAME" password: 12345678
5. To change parameters, edit /etc/hostapd.conf BTW: You can get WPAPSK the long blob from wpa_passphrase YOURNAME YOURPASS

# How to connect IR remote?

Required conditions: 

- IR hardware
- loaded driver

Get your [remote configuration](http://lirc.sourceforge.net/remotes/) (lircd.conf) or [learn](http://kodi.wiki/view/HOW-TO:Setup_Lirc#Learning_Commands). You are going to need the list of all possible commands which you can map to your IR remote keys:
	
	irrecord --list-namespace

To start with learning process you need to delete old config:
		
	rm /etc/lircd.conf 

Than start the process with:

	irrecord --driver=default --device=/dev/lirc0 /etc/lircd.conf

And finally start your service when done with learning:

	service lirc start

Test your remote:

	irw /dev/lircd
