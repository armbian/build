# What to download?

Each board is fully supported with up to **four basic system** options: 
	
- Debian Wheezy or Jessie 
- Ubuntu Trusty or Xenial

Some boards also have a desktop version Debian Jessie.

# Legacy or Vanilla?

Both kernels are stable and production ready, but you should use them for different purpuses since their basic support differ:

 - legacy: video acceleration, NAND support, connecting displays 
 - vanilla: headless server, light desktop operations 
 
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

7z and zip archives can be uncompressed with [7-Zip](http://www.7-zip.org/) on Windows, [Keka](http://www.kekaosx.com/en/) on Mac and 7z on Linux (apt-get install p7zip-full). RAW images can be written with [Rufus](https://rufus.akeo.ie/) (Win) or DD in Linux/Mac:

	# Linux example: /dev/sdx is your sd card device
	dd bs=1M if=filename.raw of=/dev/sdx
	# OS X example: /dev/[r]diskx is your sd card device:
	diskutil unmountDisk diskx && dd bs=1m if=filename.raw of=/dev/rdiskx && diskutil eject diskx

Image writing takes around 3 minutes on a slow, class 6 SD card.

Important: Make sure you use a **good & reliable** SD card. If you encounter boot troubles or simply as a measure of precaution, check them with [F3](http://oss.digirati.com.br/f3/) or [H2testw](http://www.heise.de/download/h2testw.html).

Also important: SD cards are optimised for sequential reads/writes as it's common in digital cameras. This is what the *speed class* is about. And while you shouldn't buy any card rated less than *class 10* today you should especially take care to choose one that is known to show high random I/O performance since this is way more performance relevant when used with any SBC. 

You won't be wrong picking one of these:

[![Samsung EVO 16GB UHS-I](http://www.armbian.com/wp-content/uploads/2016/03/sdcard-samsung-1.png)](http://www.amazon.com/dp/B00IVPU7KE)
[![Transcend Ultimate 16 GB UHS-I](http://www.armbian.com/wp-content/uploads/2016/03/sdcard-transcend-1.png)](http://www.amazon.com/gp/product/B00BLHWYWS)
[![SanDisk Extreme Pro 16 GB UHS-I](http://www.armbian.com/wp-content/uploads/2016/03/sdcard-sandisk-1.png)](http://www.amazon.com/dp/B008HK1YAA)

Detailed informations regarding SD cards performance:

- [SD card performance with Armbian - Thomas Kaiser](http://forum.armbian.com/index.php/topic/954-sd-card-performance/)
- [Raspberry Pi microSD card performance comparison - Jeff Geerling](http://www.jeffgeerling.com/blogs/jeff-geerling/raspberry-pi-microsd-card)
- [The Best microSD Card - Kimber Streams](http://thewirecutter.com/reviews/best-microsd-card/)

# How to boot?

Insert SD card into a slot and power the board. First boot takes around 3 minutes then it reboots and you will need to wait another one minute to login. This delay is because system updates package list and creates 128Mb emergency SWAP on the SD card.

Normal boot (with DHCP) takes up to 35 seconds with a class 6 SD CARD and cheapest board.

# How to login? 

Login as **root** on console or via SSH and use password **1234**. You will be prompted to change this password at first login. You will then be asked to create a normal user account that is sudo enabled (beware of default QWERTY keyboard settings at this stage).

Desktop images starts into desktop without asking for password. To change this add some display manager:

	apt-get install lightdm

... or edit the contents of file:

	/etc/default/nodm

and change the autologin user.

# How to update?

	apt-get update
	apt-get upgrade

This will not only update distribution packages (Debian/Ubuntu) but also updates Armbian kernel, u-boot and board support package if available. So if you've seen in the list of updated packages the names _u-boot_ or _linux_ the following command is required for changes to take effect:

	reboot

# How to switch kernels or upgrade from other systems?

If you are running **legacy kernel** and you want to switch to **vanilla**, **development** or vice versa, you can do it this way:

		wget -q -O - http://upgrade.armbian.com | bash

You will be prompted to select and confirm some actions. It's possible to upgrade **from any other distribution**. Note that this procedure upgrades only kernel with hardware definitions (bin, dtb, firmware and headers. Operating system and modifications remain as is.

Check [this for manual way](http://www.armbian.com/kernel/) and more info.

[su_youtube_advanced url="https:\/\/youtu.be\/iPAlPW3sv3I" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

# How to troubleshoot?

**Important: If you came here since you can't get Armbian running on your board please keep in mind that in 95 percent of all cases it's either a faulty/fraud/counterfeit SD card or an insufficient power supply that's causing these sorts of _doesn't work_ issues!**

If you broke the system you can try to get in this way. You have to get to u-boot command prompt, using either a serial adapter or monitor and usb keyboard (USB support in u-boot currently not enabled on all H3 boards). 

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

	# Debian --> https://wiki.debian.org/ChangeLanguage
	dpkg-reconfigure locales
	# Ubuntu --> https://help.ubuntu.com/community/Locale
	update-locale LANG=[options] && dpkg-reconfigure locales

console font, codepage:

	dpkg-reconfigure console-setup

time zone: 

	dpkg-reconfigure tzdata
	
screen settings on H3 devices:

	# Example to set resolution to 1920 x 1080, full colour-range and DVI
	h3disp -m 1080p60 -d -c 1

screen resolution on other boards: 

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

Check [this site](http://namhuy.net/1085/install-gui-on-debian-7-wheezy.html) for others and be prepared that some desktop image features currently might not work afterwards (eg. 2D/3D/video HW acceleration, so downgrading a _desktop_ image, removing the `libxfce4util-common` package and doing an `apt-get autoremove` later might be the better idea in such cases)

# How to upgrade Debian from Wheezy to Jessie?

	dpkg -r ramlog	
	cp /etc/apt/sources.list{,.bak}
	sed -i -e 's/ \(old-stable\|wheezy\)/ jessie/ig' /etc/apt/sources.list
	apt-get update
	apt-get --download-only dist-upgrade
	apt-get dist-upgrade


# How to upgrade from Ubuntu Trusty to 16.04 LTS (Xenial Xerus)?

	apt-get install update-manager-core
	do-release-upgrade -d
  	# further to xenial
	apt-get dist-upgrade

# How to toggle boot output?

Edit and change [boot parameters](http://redsymbol.net/linux-kernel-boot-parameters/) in /boot/boot.cmd:

    - console=ttyS0,115200
    + console=tty1

and convert it to boot.scr with this command:

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

Reboot.

Serial console on imx6 boards are ttymxc0 (Hummingboard, Cubox-i) or ttymxc1 (Udoo).

# How to toogle verbose boot?

    touch /boot/.force-verbose # enable

You need to reboot to conduct changes.

	rm /boot/.force-verbose # disable

# How to provide boot logs for inspection?

When computer behaves strange first step is to look into kernel logs. We made a tool that grabs info and paste it to the website.

	sudo armbianmonitor -b
	reboot
	sudo armbianmonitor -u  
Copy and past URL of your log to the forum, mail, ...

# How to build a wireless driver ?

Recreate kernel headers scripts (optional)
	
	cd /usr/src/linux-headers-$(uname -r)
	make scripts

Go back to root directory and fetch sources (working example, use ARCH=arm64 on 64bit system)

	cd 		
	git clone https://github.com/pvaret/rtl8192cu-fixes.git
	cd rtl8192cu-fixes
	make ARCH=arm
Load driver for test
 
	insmod 8192cu.ko

Check dmesg and the last entry will be:

	usbcore: registered new interface driver rtl8192cu

Plug the USB wireless adaptor and issue a command:

	iwconfig wlan0
You should see this:

	wlan0   unassociated  Nickname:"<WIFI@REALTEK>"
			Mode:Auto  Frequency=2.412 GHz  Access Point: Not-Associated   
			Sensitivity:0/0  
			Retry:off   RTS thr:off   Fragment thr:off
			Encryption key:off
			Power Management:off
			Link Quality=0/100  Signal level=0 dBm  Noise level=0 dBm
			Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
			Tx excessive retries:0  Invalid misc:0   Missed beacon:0		  

Check which wireless stations / routers are in range

	iwlist wlan0 scan | grep ESSID

# How to install to eMMC, NAND, SATA & USB?

[su_youtube_advanced url="https:\/\/youtu.be\/6So8MA-qru8" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

Required condition:

NAND:

 * kernel 3.4.x and NAND storage
 * pre-installed system on NAND (stock Android or other Linux)

eMMC/SATA/USB:

 * any kernel
 * onboard eMMC storage or permanently attached SATA or USB storage

Start the install script: 

	nand-sata-install

and follow the guide. You can create up to three scenarios:

 * boot from SD, system on SATA / USB
 * boot from eMMC / NAND, system on eMMC/NAND
 * boot from eMMC / NAND, system on SATA / USB

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

# How to run Docker?

Preinstallation requirements:

- Armian 5.1 or newer with Kernel 3.10 or higher
- Debian Jessie (might work elsewhere with some modifications)
- root access

Execute this as root:

	echo "deb https://packagecloud.io/Hypriot/Schatzkiste/debian/ wheezy main" > /etc/apt/sources.list.d/hypriot.list
	curl https://packagecloud.io/gpg.key | sudo apt-key add -
	apt-get update
	apt-get -y install --no-install-recommends docker-hypriot
	apt-get -y install cgroupfs-mount
	reboot

Test example:

	docker run -d -p 80:80 hypriot/rpi-busybox-httpd

[More info in this forum topic](http://forum.armbian.com/index.php/topic/490-docker-on-armbian/)

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
****
