# How to build Armbian? #

You will need to setup development environment within [Ubuntu 14.04 LTS x64 server image](http://releases.ubuntu.com/14.04/) and cca. 20G of free space. 

Login as root and run:

	apt-get -y -qq install git
    git clone --depth 1 https://github.com/igorpecovnik/lib
	cp lib/compile.sh .
	nano compile.sh # alter if necessary
	
Make it executable.

	chmod +x compile.sh

Run the script

	./compile.sh

# What is behind the build process?


Build process summary:

- creates development environment on the top of X86/AMD64 Ubuntu 14.04 LTS,
- download proven sources, applies patches and use tested configurations,
- cross-compile universal boot loader (u-boot), kernel and other tools and drivers, 
- pack kernel, uboot, dtb and root customizations into debs,
- debootstrap minimalistic Debian Wheezy, Jessie and Ubuntu Trusty into SD card image,
- install additional packets, apply customizations and shrink image to it's actual size.

Switches clarification:

- **KERNEL_ONLY** - if we want to compile kernel, u-boot, headers and dtbs package only.
- **KERNEL_CONFIGURE** will bring up kernel configurator otherwise kernel will be compiled with script presets located in lib/config/linux-*.config
- **CLEAN_LEVEL** defines what should be cached. This is useful when we are rebuilind images or builind more than one image.
	- 0 = executes make clean and delete previously created deb files [default]
	- 1 = executes make clean
	- 2 = does nothing
	- 3 = provide kernel selection if any present 
	- 4 = delete all output files (rootfs cache, debs) 
- **BUILD_DESKTOP** builds a desktop on the top of the system with hw acceleration for some boards.
- **AFTERINSTALL** is a variable with command executed in a process of building just before closing image to insert some of your custom applications or fixes.
- **FBTFT** is a [driver for small displays](https://github.com/notro/fbtft). Only applicable for old kernels (3.4-3.14)
- **EXTERNAL** compiles custom drivers
- **FORCE** ignore manual changes to source
- **BUILD_ALL** cycle through selected boards and make images

Image compiling example with partial cache:

[su_youtube_advanced url="https:\/\/youtu.be\/zeShf12MNLg" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

## Creating compile environment ##

At first run we are downloading all necessary dependencies. 

## Using board configuration ##

We need to get some predefined variables about selected board. Which kernel & uboot source to use, modules to load, which is the build number, do we need to have a single partition or dual with boot on fat, which extra drivers to compile out of the kernel tree, ...

**Board configuration example:**
    
	REVISION="1.1"											# Version number is altered by board maintainer
	BOOTSIZE="16"											# FAT boot partition in MB, 0 for none
	BOOTLOADER="https://github.com/UDOOboard/uboot-imx"		# Uboot source location
	BOOTSOURCE="u-boot-neo"									# Local folder where to download it
	BOOTCONFIG="udoo_neo_config"							# Which compile config to use
	CPUMIN="198000"											# CPU minimum frequency
	CPUMAX="996000"											# CPU minimum frequency
	MODULES="bonding"										# old kernel modules
	MODULES_NEXT=""											# new kernel modules
	LINUXKERNEL="https://github.com/UDOOboard/linux_kernel"	# kernel source location
	LINUXCONFIG="linux-udoo-neo"							# kernel configuration
	LINUXSOURCE="linux-neo"									# Local folder where to download it
	LINUXFAMILY="udoo"										# boards share kernel

This **isn't ment to be user configurable** but you can alter variables if you know what you are doing.

## Downloading sources ##

When we know where are the sources and where they need to be the download / update process starts. This might take from several minutes to several hours.

## Patching ##

In patching process we are appling patches to sources. The process is defined in:

	lib/patching.sh

## Compiling or choosing from cache ##


- compile from scratch with additional source cleaning and menu config.
- select cached / already made kernel 

## Debootstrap ##

Debootstrap creates fresh Debian / Ubuntu root filesystem templates or use cached under:

	output/cache/rootfs/$DISTRIBUTION.tgz

To recreate those files you need to remove them manually. 

## Kernel install ##

When root filesystem is ready we need to instal kernel image with modules, board definitions, firmwares. Along with this we set the CPU frequency min/max, hostname, modules, network interfaces templates. Here is also the place to install headers and fix + native compile them on the way.

## Distribution fixes ##

Each distributin has it's own way of doing things:

- serial console
- different packets
- configuration locations

## Board fixes ##

Each board has their own tricks: **different device names, firmware loaders, configuration (de)compilers, hardware configurators**

## Desktop installation ##

You can build a desktop withing the image. Consider this feature as experimental. Hardware acceleration on Allwinner boards is working within kernel 3.4.x only.

## External applications ##

This place is reserved for custom applications. There is one example of application - USB redirector.

## Closing image ##

There is an option to add some extra commands just before closing an image which is also automaticaly shrink to it's actual size with some small reserve.

## Directory structure ##

It will be something like this:

    compile.sh				compile execution script
	lib/bin/				blobs, firmwares, static compiled, bootsplash
    lib/config/				kernel, board, u-boot, hostapd, package list
    lib/documentation/		user and developers manual
	lib/patch/				collection of kernel and u-boot patches
	lib/scripts/			firstrun, arm hardware info, firmware loaders
	lib/LICENSE				licence description
	lib/README.md			quick manual
	lib/boards.sh			board specfic installation, kernel install, desktop install
	lib/common.sh			creates environment, compiles, shrink image
	lib/configuration.sh	boards presets - kernel source, config, modules, ...
	lib/deboostrap.sh		basic system template creation
	lib/distributions.sh	system specific installation and fixes
	lib/main.sh				user input and script calls
	lib/patching.sh			board and system dependend kernel & u-boot patch calls
	lib/repo-update.sh		creates and updates your local repository
	lib/repo-show-sh		show packets in your local repository
	lib/upgrade.sh			script to upgrade older images
	sources/				source code for kernel, uboot and other utilities
	output/repository		repository 
	output/cache			cache for root filesystem and headers compilation
	output/debs				deb packeges
	output/images			zip packed RAW image

## Additional info ##

- [Allwinner SBC community](https://linux-sunxi.org/)