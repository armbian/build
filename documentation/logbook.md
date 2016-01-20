# Release history

**v5.00 / x.y.2015** NOT RELEASED YET!

- Vanilla kernel for Allwinner based boards upgraded to 4.4
- Allwinner audio driver playback and capture on kernel 4.4, [UAS](http://linux-sunxi.org/USB/UAS), USB OTG, battery readings,  
- added Marvel Armada kernel 3.10.94, 4.3.3, 4.4 and patches for changing mPCI to SATA
- added Cubox / Hummingboard kernel 4.4
- firstrun does autoreboot only if needed: wheezy and some legacy kernels.
- [added motd](http://forum.armbian.com/index.php/topic/602-new-motd-for-ubuntudebian/#entry4223) to /etc/updated.motd ... redesign, added battery info for Allwinner boards, bugfix, coloring
- fixed temperature reading on Cubox / Hummingboard legacy kernel
- fixed FB turbo building on Allwinner
- fixed USB boot, added PWM on Vanilla
- readded USB sound
- added [A13 Olimex SOM](https://www.olimex.com/Products/SOM/A13/A13-SOM-512/)

**v4.81 / 28.12.2015**

- complete build script rework
- new development kernel package linux-image-dev-sunxi (4.4RC6) for Allwinner boards
- added Lemaker Guitar, kernel 3.10.55
- added Odroid XU3/4, kernel 3.10.94 and Vanilla 4.2.8
- Vanilla kernel for Allwinner based boards upgraded to 4.3.3
- Udoo vanilla upgraded to 4.2.8, legacy to 3.14.58
- cubox / hummingboard upgraded to 3.14.58, added Vanilla kernel 4.4
- fixed Jessie RTC bug, systemd default on Jessie images

**v4.70 / 30.11.2015**

- Bugfix update(apt-get update && apt-get upgrade)
- small changes and fixes

**v4.6 / 24.11.2015** 

- Update only (apt-get update && apt-get upgrade)
- Vanilla kernel for Allwinner based boards upgraded to 4.2.6
- Legacy kernel for Allwinner based boards upgraded to 3.4.110
- added new board: Udoo Neo
- added USB printer, CAN, CMA, ZSWAP, USB video class, CDROM fs, sensor classs, … to Allwinner Vanilla kernel
- nand-sata-install scripts rewrite. Now it’s possible to install to any partition.
- fixed nand install for Allwinner A10 based boards: Cubieboard 1 / Lime A10
- universal upgrade script bugfix / rewrite.
- 8 channel HDMI support for legacy Allwinner kernel
- unattended upgrade fixed
- sunxi tools fixed
- added two new options to build script: keep kernel config and use_ccache
- added kernel version to motd

**v4.5 / 14.10.2015**

- vanilla kernel upgraded to 4.2.3 for Allwinner based boards
- legacy kernel for Allwinner compiled from new sources (linux-sunxi)
- udoo vanilla upgraded to 4.2.3
- cubox / hummingboard upgraded to 3.14.54
- changed kernel naming: A10 = linux-image-sun4i, A20 = linux-image-sun7i
- new boards: Banana M2, Orange+(A31S), Cubieboard 1, Cubieboard 2 Dual SD, Lime A10
- fixed Udoo legacy wireless problems
- fixed Jessie boot problems by disabling systemd. It’s possible to re-enable within boot scripts
- added ramlog to Jessie because we don’t have systemd anymore
- changed wireless driver for Cubietruck and Banana PRO (now it’s ap6210)
- added ZRAM to vanilla kernel
- fixed dvbsky modules

and a bunch of small fixes.

**v4.4 / 1.10.2015**

Images:

- vanilla kernel upgrade to 4.2.2 (Allwinner, Udoo Quad),
- legacy kernel upgraded to 3.4.109 (Allwinner),
- added I2C support and bunch of multimedia modules (DVB) (vanilla Allwinner),
- Udoo quad images with fixed legacy kernel 3.14.28,
- Cubox and Hummingboard kernel upgrade to 3.14.53,
- brcmfmac driver fixes for vanilla kernel (Banana PRO / Cubietruck)
- performance tweak: choosing a closest Debian mirror (Debian images)
- added Astrometa DVB firmware and dvb-tools
- added Nikkov SPDIF / I2S recent patch (legacy Allwinner)
- added patch for rtl8192cu: Add missing case in rtl92cu_get_hw_reg (Lamobo R1)
- bigger NAND boot partition on install
- install script bug fixes

Script:

- force apt-get update on older rootfs cache,
- image harden manipulation security,
- packages NAND/FAT/same version install faling fixed,
- image shrinking function rework,
- better packages installation install checking,
- added Debian keys to suppress warnings in debootstrap process,
- added fancy progress bars,
- added whiptail downloading prior to usage (bugfix).

**v4.3 / 17.9.2015**

- kernel 4.2 for Allwinner based boards
- kernel 4.2 for Udoo Quad
- walk-around if ethernet is not detected on some boards due to RTC not set(?)
- update is done (semi) automatic if you are using Armbian 4.2. You only need to issue command: apt-get update && apt-get upgrade. If you are coming from older system, check Documentation
- U-boot on R1 is now updated to latest stable version (2015.07)
- Fixed AW SOM. Working with latest u-boot but you need to build image by yourself.
- Enabled whole USB net and HID section in kernel for Allwinner boards v4.2
- Fixed upgrade script – only some minor bugs remains.
- Fixes to build script that it’s working under Ubuntu 15.04
- Adding Bananapi Wireless driver (ap6210) back to legacy kernel
- Udoo official kernel (3.14.28) not updated due too many troubles.

**v4.2 / 1.9.2015**

Images:

- Upgraded NAND / SATA installer. Possible to install to SATA/NAND boot in one step.
- Easy kernel switching between old 3.4 and 4.x
- Automatic kernel updating (to disable comment armbian repo /etc/apt/sources.list)
- Allwinner boards share one 4.x kernel and two 3.4
- All boards share the same revision number
- One minimal Ubuntu Desktop per board (Wicd, Firefox, Word)
- u-boot v2015.07 for most boards
- Aufs file system support
- kernel 4.1.6 and 3.4.108
- Added Orangepi Mini, Cubieboard 1 (4.x only), Udoo with official kernel
- Repository for Wheezy, Jessie and Trusty
- enabled USB audio in kernel 4.x
- kernel headers fixed. No need to rebuild when you update the kernel.
- fixed boot scripts that can load from FAT partition too
- removed Cubox binnary repository because of troubles
- Docker support (kernel 4.x). Already here for a while / forget to mention.
- nodm change default login

Build script:

- changed structure: sources now in folder sources, output is what we produce, deb in one folder
- expanded desktop part
- possible to build all images at once, create package repository
- SD card initial size is 4Gb, variable transfered into configuration.sh
- Avaliable board list is now created from file configuration.sh
- Fixed image shrinking problem
- Patching part rework
- Using first FAT boot partition now fixes boot scripts
- Uboot TAG moved to configuration.sh and differs for some boards
- new variables for source branches. Only too remove errors when checking out

**v4.1 / 5.8.2015**

- Added desktop image
- U-Boot 2015.07 with many new features
- Added auto system update via repository apt.armbian.com
- Root password change is initialized at first boot.
- 3.4.108 kernel fixes, 4.1.4 Allwinner Security System

**v4.0 / 12.7.2015**

- Fixed stability issues, temperature display in 4.x
- Kernel upgrades to 3.4.108 and 4.1.2

**v3.9 / 11.6.2015**

- Bugfix release
- Kernel 4.0.5 traffic control support
- SATA / USB install fixed on kernel 4.x
- Added 256Mb emergency swap area, created automatically @first boot

**v3.8 / 21.5.2015**

- Bugfix release: Cubietruck images successfully booted on Cubietruck. I waited for automatic reboot than tested remote login.
- Kernel 4.0.4 added support for power on/off button
- Both: Jessie fixed, Ethernet init fixed (uboot)
- armbian.com introduction

**v3.7 / 14.5.2015**

- Kernel 4.0.3 some new functionality
- Kernel 3.4.107 added sunxi display manager to change FB on demand
- Both: Ubuntu and jessie install errors fixed, removed busybox-syslogd and changed to default logger due to problems in Jessie and Ubuntu, apt-get upgrade fixed, documentations update, Uboot fixed to 2015.4 – no more from dev branch
- Build script rework - image size shrink to actual size, possible to have fat boot partition on SD card, several script bug fixes

**v3.6 / 29.4.2015**

- Kernel 3.19.6
- Kernel 3.4.107 with better BT loading solution

**v3.5 / 18.4.2015**

- Kernel 3.19.4: fixed AP mode, fixed USB, added 8192CU module
- Common: apt-get upgrade ready but not enabled yet, serial console fixed, fixed hostapd under jessie, easy kernel switching, latest patched hostapd for best performance – normal and for realtek adaptors, auto IO scheduler script
- Build script: everything packed as DEB

**v3.4 / 28.3.2015**

- Kernel 3.19.3: docker support, apple hid, pmp, nfsd, sata peformance fix
- Kernel 3.4.106: pmp, a20_tp - soc temp sensor
- Common: console setup fixed, headers bugfix, nand install fix
- Build script: kernel build only, custom packets install, hardware accelerated desktop build as option

**v3.3 / 28.2.2015**

- Kernel 3.19.0: many new functionality and fixes.
- Bugfixes: CT wireless works in all kernels

**v3.2 / 24.1.2015**

- Possible to compile external modules on both kernels
- Kernel 3.19.0 RC5
- Bugfixes: install script, headers, bashrc, spi

**v3.1 / 16.1.2015**

- Kernel 3.19.0 RC4
- Added Cubieboard 1 images
- Dualboot for CB2 and CT dropped due to u-boot change. Now separate images.
- New user friendly SATA + USB installer, also on mainline

**v3.0 / 29.12.2014**

- Kernel 3.18.1 for mainline image
- Added Ubuntu Trusty (14.04 LTS) image
- Bugfixes: auto packages update

**v2.9 / 3.12.2014**

- Kernel 3.4.105 with new MALI driver and other fixes
- Added: Jessie image
- Major build script rewrite - much faster image building
- Fixed: failed MIN/MAX settings

**v2.8 / 17.10.2014**

- Added: ondemand governor, fhandle, squashfs and btrfs
- Removed: bootsplash, lvm, version numbering in issue
- Fixed: custom scripts, Jessie upgrade
- Disabled: BT firmware loading, enable back with: insserv brcm40183-patch
- Added working driver for RT 8188C, 8192C

**v2.7 / 1.10.2014**

- Kernel 3.4.104
- Automatic Debian system updates
- VGA output is now default but if HDMI is attached at first boot than it switch to HDMI for good. After first restart!
- Fixed NAND install script. /boot is mounted by default. Kernel upgrade is now the same as on SD systems.
 Cubieboard2 - disabled Cubietruck dedicated scripts (BT firmware, LED disable)
- Added network bonding and configuration for "notebook" mode (/etc/network/interfaces.bonding)
- IR receiver is preconfigured with default driver and LG remote (/etc/lirc/lircd.conf), advanced driver is present but disabled
- Added SPI and LVM functionality
- Added Debian logo boot splash image
- Added build essentials package

**v2.6 / 22.8.2014**

- Kernel 3.4.103 and 3.17.0-RC1
- Added GPIO patch (only for 3.4.103)

**v2.5 / 2.8.2014**

- Kernel 3.4.101 and 3.16.0-RC4
- major build script rewrite     

**v2.4 / 11.7.2014**

- Kernel 3.4.98
- default root password (1234) expires at first login
- build script rewrite, now 100% non-interactive process, time zone as config option       
- bug fixes: removed non-existing links in /lib/modules     

**v2.3 / 2.7.2014**

- Kernel 3.4.96
- cpuinfo serial number added
- bug fixes: stability issues - downclocked to factory defaults, root SSH login enabled in Jessie, dedicated core for eth0 fix 
- disp_vsync kernel patch     

**v2.2 / 26.6.2014**

- Kernel 3.4.94
- Added Jessie distro image
- Updated hostapd, bashrc, build script
- bug fixes: disabled upgrade and best mirror search @firstboot, bluetooth enabler fix
- MD5 hash image protection

**v2.1 / 13.6.2014**

- Kernel 3.4.93
- Onboard Bluetooth finally works
- Small performance fix
- Allwinner Security System cryptographic accelerator

**v2.0 / 2.6.2014**

- Kernel 3.4.91 with many fixes
- Cubieboard 2 stability issues fix
- eth0 interrupts are using dedicated core
- Global bashrc /etc/bash.bashrc
- Verbose output and package upgrade @ first run

**v1.9 / 27.4.2014**

- Kernel headers included
- Clustering support
- Advanced IR driver with RAW RX and TX
- Bluetooth ready (working only with supported USB devices)
- Bugfixes: VLAN, login script, build script
- New packages: lirc, bluetooth

**v1.8 / 27.3.2014**

- Kernel 3.4.79
- Alsa I2S patch + basic ALSA utils
- Performance tweaks: CPU O.C. to 1.2Ghz, IO scheduler NOOP for SD, CFQ for sda, journal data writeback enabled
- Avaliable memory = 2000MB
- Minimized console output at boot
- MAC address from chip ID, manual optional
- Latest (Access point) hostapd, 2.1 final release
- Login script shows current CPU temp, hard drive temp & actual free memory
- Fastest Debian mirror auto selection @first boot
- New packages: alsa-utils netselect-apt sysfsutils hddtemp bc

**v1.7 / 26.2.2014**

- Flash media performance tweaks, reduced writings, tmp & logging to RAM with ramlog app – sync logs on shutdown
- SATA install script
- Dynamic MOTD: Cubieboard / Cubietruck
- Disabled Debian logo at startup
- New packages: figlet toilet screen hdparm libfuse2 ntfs-3g bash-completion

**v1.6 / 9.2.2014**

- Added support for Cubieboard 2
- Build script creates separate images for VGA and HDMI
- NAND install script added support for Cubieboard 2

**v1.52 / 7.2.2014**

- Various kernel tweaks, more modules enabled
- Root filesystem can be moved to USB drive
- Bugfixes: NAND install script

**v1.5 / 22.1.2014**

- Hotspot Wifi Access Point / Hostapd 2.1
- Bugfixes: MAC creation script, SSH keys creation, removed double packages, …
- Graphics desktop environment upgrade ready

**v1.4 / 12.1.2014**

- Patwood’s kernel 3.4.75+ with many features
- Optimized CPU frequency scaling 480-1010Mhz with interactive governor
- NAND install script included
- Cubietruck MOTD
- USB redirector – for sharing USB over TCP/IP

**v1.3 / 3.1.2014**

- CPU frequency scaling 30-1000Mhz
- Patch for gpio

**v1.23 / 1.1.2014**

- added HDMI version
- added sunxi-tools
- build.sh transfered to Github repository
- disabled LED blinking

**v1.2 / 26.12.2013**

- changed kernel and hardware config repository
- kernel 3.4.61+
- wi-fi working
- updated manual how-to

**v1.0 / 24.12.2013**

- total memory available is 2G (disabled memory for GPU by default)
- gigabit ethernet is fully operational
- sata driver enabled
- root filesystem autoresize
- MAC address fixed at first boot
- Kernel 3.4.75
- root password=1234
- Bugs: wifi and BT not working