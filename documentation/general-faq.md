# What is the root password? How can I login?

Login as **root** and with password **1234**. You will be prompet to change this password at first login.

# How do you add users?

To create a normal user do this:

    $ adduser FooBar

Put user to sudo group:

    $ usermod -aG sudo FooBar


# How to update kernel?

First you need to download a proper pack located at the end of board download section (Kernel, U-boot, DTB). This example is for Cubietruck but it's the same for other boards, just get a kernel for that board.

	$ mkdir 3.19.6
	$ cd 3.19.6
	$ wget http://mirror.igorpecovnik.com/kernel/3.19.6-cubietruck-next.tar
	$ tar xvf 3.19.6-cubietruck-next.tar
	$ dpkg -i *.deb

Reboot into new kernel.

# Aditional step if you update kernel on older image?

If you came from image that doesn't have boot scripts (/boot/boot.scr) you will need to create one - Create /boot/boot.cmd file:
	
	setenv bootargs console=tty1 root=/dev/mmcblk0p1 rootwait consoleblank=0
	if ext4load mmc 0 0x00000000 /boot/.next
	then
	ext4load mmc 0 0x49000000 /boot/dtb/${fdtfile} 	
	ext4load mmc 0 0x46000000 /boot/zImage
	env set fdt_high ffffffff
	bootz 0x46000000 - 0x49000000
	else
	ext4load mmc 0 0x43000000 /boot/script.bin
	ext4load mmc 0 0x48000000 /boot/zImage
	bootz 0x48000000
	fi 
	
and convert it to boot.scr with this command:

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

Reboot into new kernel.

# NAND, SATA & USB install

Required condition:

 * Kernel 3.4.x
 * NAND, SATA or USB storage
 * a partitioned SATA storage
 * booted Debian from SD-Card
 * Login as root

Then start the install script and follow the guide:

    $ cd /root
    $ ./nand-sata-install

# Toogle boot output
Edit and change boot parameters in /boot/boot.cmd:

    - console=ttyS0,115200
    + console=tty1

and convert it to boot.scr with this command:

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

Reboot into new kernel.

# Changing network modes

There are three predefined configurations, you can find them in those files:

	/etc/network/interfaces.hostapd
	/etc/network/interfaces.default
	/etc/network/interfaces.bonding

Preset - **/etc/network/interfaces** is symlinked to **/etc/network/interfaces.default**

1. DEFAULT: your network adapters are connected classical way. 
2. HOSTAPD: your network adapters are bridged together and bridge is connected to the network. This allows you to have your AP connected directly to your network / router.
3. BONDING: your network adapters are bonded in fail safe / "notebook" way.

You can switch configuration with re-linking.

	cd /etc/network
	ln -sf interfaces.x interfaces
(x=default,hostapd,bonding)

# AP configuration

There are two different hostapd servers. One is default, the other is for Realtek. Both have their own basic configuration.

Default binary and configuration:

	/usr/sbin/hostapd
	/etc/hostapd.conf
	
Realtek binary and configuration:

	/usr/sbin/hostapd-rt
	/etc/hostapd.conf-rt

Since is hard to define when to use which you always try both combinations in case of troubles. To start AP automaticly:

1. Edit /etc/init.d/hostapd and add location of your conf file **DAEMON_CONF=/etc/hostapd.conf**
2. Link **/etc/network/interfaces.hostapd** to **/etc/network/interfaces**
3. Reboot
4. Predefined network name: "BOARD NAME" password: 12345678
5. To change parameters, edit /etc/hostapd.conf ... BTW: You can get WPA_PSK (the long blob) from wpa_passphrase YOURNAME YOURPASS

# Alter CPU frequency

Some boards allow to adjust CPU speed.

	nano /etc/init.d/cpufrequtils

change
MAX_SPEED="1200000"
to
MAX_SPEED="960000"
or something else

	service cpufrequtils restart

# Upgrade to simple desktop environment

	apt-get -y install xorg lightdm xfce4 xfce4-goodies tango-icon-theme gnome-icon-theme
	reboot

Check [this site](http://namhuy.net/1085/install-gui-on-debian-7-wheezy.html) for others.

# How to create / write to SD card?

Unzipped images can be written with supplied imagewriter.exe on Windows XP/2003/Win7 or with DD command in Linux/Mac:

	dd bs=1M if=filename.raw of=/dev/sdx

(/dev/sdx = your sd card device)

# There are so many download options. I am confused!

**Debian Wheezy** with kernel 3.4.x, which is usually latest full featured, is recommended download. **It’s rock stable**, most tested and supported. Jessie and Ubuntu Trusty is for people who wants to go with the flow. Both should be fully operational but not recommended for beginners and/or services deployment. Each image can have some extra downloads: 

- (M) means mirror download 
- (R) means root file system changes. If there were some changes to you want to download this file too but it's rear that you'lll need it.