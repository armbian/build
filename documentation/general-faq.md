# Why there are more download options?

**Debian Wheezy** with kernel 3.4.x, which is usually latest full featured, is recommended download. **It’s rock stable**, most tested and supported. **Jessie and Ubuntu Trusty** is for people who wants to go with the flow. Both should be fully operational but not recommended for beginners and/or services deployment. Each image can have some extra downloads:

- **(M)** means mirror download 
- **(R)** means root file system changes. Sometimes you need to download and install this file too.


# How to prepare SD card?

Unzipped RAW images can be written with supplied imagewriter.exe on Windows XP/2003/Win7 or with DD command in Linux/Mac:

	dd bs=1M if=filename.raw of=/dev/sdx

(/dev/sdx = your sd card device)

# How to login? 

Login as **root** and use password **1234**. You will be prompted to change this password at first login. This is the only pre-installed user.

# How to add users?

To create a normal user do this:

    adduser FooBar

Put user to sudo group:

    usermod -aG sudo FooBar

# How to customize keyboard, time zone, ... ?

keyboard: 

	dpkg-reconfigure keyboard-configuration
	
system language: 

	dpkg-reconfigure locales

time zone: 

	dpkg-reconfigure tzdata
	
screen resolution: 

	nano /boot/boot.cmd 
	# change example:
	# disp.screen0_output_mode=**1920x1080p60**
	# to
	# disp.screen0_output_mode=**1280x720p60**
	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr	

screen resolution interactive - only Allwinner boards with A10 and A20 with kernl 3.4.x:
	
	# Example to set console framebuffer resolution to 1280 x 720
	a10disp changehdmimodeforce 4

# How to alter CPU frequency?

Some boards allow to adjust CPU speed.

	nano /etc/init.d/cpufrequtils

Alter **min_speed** or **max_speed** variable.

	service cpufrequtils restart

# How to upgrade into simple desktop environment?

	apt-get -y install xorg lightdm xfce4 tango-icon-theme gnome-icon-theme
	reboot


Check [this site](http://namhuy.net/1085/install-gui-on-debian-7-wheezy.html) for others.

# How to upgrade from Debian Wheezy to Debian Jessie?

	dpkg -r ramlog	
	cp /etc/apt/sources.list{,.bak}
    sed -i -e 's/ \(stable\|wheezy\)/ jessie/ig' /etc/apt/sources.list
    apt-get update
    apt-get --download-only dist-upgrade
    apt-get dist-upgrade


# How to upgrade from Ubuntu Trusty to Ubuntu Utopic and Vivid?
	
	apt-get install update-manager-core
    do-release-upgrade -d
  	# further to vivid
	apt-get dist-upgrade

# How to toggle boot output?
Edit and change boot parameters in /boot/boot.cmd:

    - console=ttyS0,115200
    + console=tty1

and convert it to boot.scr with this command:

	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

Reboot.

Serial console on imx6 boards are ttymxc0 (Hummingboard, Cubox-i) or ttymxc1 (Udoo)

# How to install to NAND, SATA & USB?

![Installer](http://www.igorpecovnik.com/wp-content/uploads/2015/05/sata-installer.png)

Required condition:

 * kernel 3.4.x (some newer kernels might work too)
 * NAND storage
 * pre-partitioned SATA or USB storage
 * system booted from SD card
 * root privileges

Start the install script: 

    cd /root
    ./nand-sata-install

and follow the guide.

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

# How to setup fixed IP?

By default your main network adapter's IP is assigned by your router DHCP server.

	iface eth0 inet dhcp 

change to - for example:

	iface eth0 inet static
	 	address 192.168.1.100
        netmask 255.255.255.0
		gateway 192.168.1.1

# How to setup wireless access point?

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

# How to update kernel?

First you need to download a proper kernel tar pack located at the end of board download section (Kernel, U-boot, DTB). This example is for Cubietruck but it's the same for all other boards - just grab a kernel pack for board of your choice.

	mkdir 3.19.6
	cd 3.19.6
	wget http://mirror.igorpecovnik.com/kernel/3.19.6-cubietruck-next.tar
	tar xvf 3.19.6-cubietruck-next.tar
	dpkg -i linux-image*.deb

Optional:

	dpkg -i linux-headers*.deb
	
1. Create some temporary directory
2. Go into it
3. Grab a kernel pack
4. Install at least linux-image
5. If pack refuses to install, uninstall it and try again.

Reboot.

Optional work after you boot into new kernel - only if you are planning to compile some kernel drivers. 

	cd /usr/src/linux-headers-$(uname -r)
	make scripts

# Optional steps if you have your system on NAND?

Your first NAND partition is usually mounted under /boot. In this case all you need to do is:

	mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d /boot/zImage /boot/uImage

If you use older image than you might need to mount your first NAND partition (**/dev/nand1**) and copy new uImage there. 

Reboot.

# Optional steps if you update kernel to older SD image?

If you came from image that doesn't have boot scripts (/boot/boot.scr) you will need to create one. 

Create **/boot/boot.cmd** file with this content:
	
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

Reboot.

# How to compile my own kernel or SD image?

You will need to setup proven development environment with [Ubuntu 14.04 LTS x64 server image](http://releases.ubuntu.com/14.04/) and cca. 20G of free space. Install basic system and create this call script:

	nano compile.sh

copy and paste the following code:

	#!/bin/bash	
	# 
	# 	Edit and execute this script - Ubuntu 14.04 x86/64 recommended
	#
	#   Check https://github.com/igorpecovnik/lib for possible updates
	#

	# method
	KERNEL_ONLY="no"                            # build kernel only
	SOURCE_COMPILE="yes"                        # force source compilation
	KERNEL_CONFIGURE="no"                       # change default configuration
	KERNEL_CLEAN="yes"                          # MAKE clean before compilation
	USEALLCORES="yes"                           # Use all CPU cores
	BUILD_DESKTOP="no"                          # desktop with hw acceleration for some boards 
	
	# user 
	DEST_LANG="en_US.UTF-8"                     # sl_SI.UTF-8, en_US.UTF-8
	TZDATA="Europe/Ljubljana"                   # time zone
	ROOTPWD="1234"                              # forced to change @first login
	SDSIZE="1500"                               # SD image size in MB
	AFTERINSTALL=""                             # command before closing image 
	MAINTAINER="Igor Pecovnik"                  # deb signature
	MAINTAINERMAIL="igor.pecovnik@****l.com"    # deb signature
	GPG_PASS=""                                 # set GPG password for non-interactive packing
	
	# advanced
	KERNELTAG="v3.19.7"                         # kernel TAG - valid only for mainline
	UBOOTTAG="v2015.04"							# kernel TAG - valid for all sunxi
	FBTFT="yes"                                 # https://github.com/notro/fbtft 
	EXTERNAL="yes"                              # compile extra drivers
	FORCE="yes"									# ignore manual changes to source

	# source is where we start the script
	SRC=$(pwd)
	# destination
	DEST=$(pwd)/output                                      
	# get updates of the main build libraries
	if [ -d "$SRC/lib" ]; then
    	cd $SRC/lib
		git pull 
	else
    	# download SDK
   		apt-get -y -qq install git
    	git clone https://github.com/igorpecovnik/lib
	fi
	source $SRC/lib/main.sh

Save and exit, than make script executable and run it.

	chmod +x compile.sh
	./compile.sh

This video shows the whole building process (30 minutes).

*https://youtu.be/TE5XDovsCOo?vq=hd720*

You need to choose few options than wait for a while. When done check:

- **output/choosen-destination-version-distro-kernel-version.zip** = zipped RAW image
- **output/kernel** = complete upgrade pack with kernel, modules, headers, firmware, dtbs
- **output/rootfs** = rootfilesystem cache and upgrades only
- **output/u-boot** = deb packed self installed uboot
