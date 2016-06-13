# How to contribute to the code?

1. [Fork](http://help.github.com/forking/) the project
2. Make one or more well commented and clean commits to the repository. 
3. Perform a [pull request](http://help.github.com/pull-requests/) in github's web interface.

If it is a new feature request, don't start the coding first. Remember to [open an issue](https://guides.github.com/features/issues/) to discuss the new feature.

If you are struggling, check [this detailed step by step guide on contributing](https://www.exchangecore.com/blog/contributing-concrete5-github/).

# How to build Armbian image or custom kernel?

You will need to setup development environment within [Ubuntu 14.04 LTS x64 server image](http://releases.ubuntu.com/14.04/) and cca. 20G of free space. 

Login as root and run:

	apt-get -y -qq install git
    git clone --depth 1 https://github.com/igorpecovnik/lib
	cp lib/compile.sh .
	nano compile.sh # alter if necessary

Run the script

	./compile.sh

# Build options clarification
- **KERNEL_ONLY** (yes|no):
    - set to "yes" to compile only kernel, u-boot and other packages for installing on existing Armbian system
    - set to "no" to build complete OS image for writing to SD card
- **KERNEL_CONFIGURE** (yes|no):
    - set to "yes" to configure kernel (add or remove modules or features). Kernel configuration menu will be brought up before compilation
    - set to "no" to compile kernel without changing default or custom provided configuration
- **CLEAN_LEVEL** (comma-separated list): defines what should be cleaned. Default value is `"make,debs"` - clean sources and remove all packages. Changing this option can be useful when rebuilding images or building more than one image
    - "make" = execute `make clean` for selected kernel and u-boot sources,
	- "images" = delete `output/images` (complete OS images),
	- "debs" = delete packages in `output/debs` for current branch and device family,
	- "alldebs" = delete all packages in `output/debs`,
	- "cache" = delete `output/cache` (rootfs cache),
	- "sources" = delete `sources` (all downloaded sources)
- **KERNEL\_KEEP\_CONFIG** (yes|no):
    - set to "yes" to use kernel config file from previous compilation for the same branch, device family and version
    - set to "no" to use default or user-provided config file
- **BUILD_DESKTOP** (yes|no):
    - set to "yes" to build image with minimal desktop environment
    - set to "no" to build image with console interface only
- **EXTERNAL** (yes|no):
    - set to "yes" to compile and install some extra applications and drivers (only for **default** kernel branch):
        - [USB redirector](http://www.incentivespro.com)
        - Realtek RT8192 wireless driver
        - Mediatek MT7601U wireless - driver
        - Sunxi display control
        - hostapd from sources
- **DEBUG_MODE** (yes|no)
	- set to "yes" will prompt you right before the compilation starts to make changes to the source code. Separate for u-boot and kernel. It will also create a patch out of this. If you want that this patch is included in the normal run, you need to copy it to appropriate directory
	- set to "no" compilation will run uninterrupted 
- **FORCE_CHECKOUT** (yes|no):
    - set to "yes" to force overwrite any changed or manually patched kernel, u-boot and other sources
    - set to "no" to keep all changes to sources
- **BUILD_ALL** (yes|no): cycle through all available board and kernel configurations and make images for all combinations

### Hidden options to minimize user input for build automation:
- **BOARD** (string): you can set name of board manually to skip dialog prompt
- **BRANCH** (default|next|dev): you can set kernel and u-boot branch manually to skip dialog prompt; some options may not be available for all devices
- **RELEASE** (wheezy|jessie|trusty|xenial): you can set OS release manually to skip dialog prompt; use this option with `KERNEL_ONLY=yes` to create board support package

### Hidden options for advanced users (default values are marked **bold**):
- **USE_CCACHE** (**yes**|no): use a C compiler cache to speed up the build process
- **PROGRESS_DISPLAY** (none|plain|**dialog**): way to display output of verbose processes - compilation, packaging, debootstrap
- **PROGRESS_LOG_TO_FILE** (yes|**no**): duplicate output, affected by previous option, to log files `output/debug/*.log`
- **USE_MAINLINE_GOOGLE_MIRROR** (yes|**no**): use `googlesource.com` mirror for downloading mainline kernel sources, may be faster than `git.kernel.org` depending on your location
- **EXTENDED_DEBOOTSTRAP** (**yes**|no): use new debootstrap and image creation process
- **FORCE_USE_RAMDISK** (yes|no): overrides autodetect for using tmpfs in new debootstrap and image creation process. Takes effect only if `EXTENDED_DEBOOTSTRAP` is set to "yes"
- **FIXED_IMAGE_SIZE** (integer): create image file of this size (in megabytes) instead of minimal. Takes effect only if `EXTENDED_DEBOOTSTRAP` is set to "yes"
- **COMPRESS_OUTPUTIMAGE** (yes|**no**): create compressed archive with image file and GPG signature for redistribution
- **SEVENZIP** (yes|**no**): create .7z archive with extreme compression ratio instead of .zip
- **ROOTFS_TYPE** (**ext4**|f2fs|btrfs|nfs|fel): create image with different root filesystems instead of default ext4. Requires setting FIXED_IMAGE_SIZE to actual size of your SD card for F2FS and BTRFS. Takes effect only if `EXTENDED_DEBOOTSTRAP` is set to "yes"

### Supplying options via command line parameters
Instead of editing compile.sh to set options, you can set them by supplying command line parameters to compile.sh
Example:

    ./compile.sh BRANCH=next BOARD=cubietruck KERNEL_ONLY=yes PROGRESS_DISPLAY=plain RELEASE=jessie

Note: Option `BUILD_ALL` cannot be set to "yes" via command line parameter.

## User provided patches
You can add your own patches outside build script. Place your patches inside appropriate directory, for kernel or u-boot. There are no limitations except all patches must have file name extension `.patch`. User patches directory structure mirrors directory structure of `lib/patch`. Look for the hint at the beginning of patching process to select proper directory for patches. Example:

    [ o.k. ] Started patching process for [ kernel sunxi-dev 4.4.0-rc6 ]
    [ o.k. ] Looking for user patches in [ userpatches/kernel/sunxi-dev ]

Patch with same file name in `userpatches` directory tree substitutes one in `lib/patch`. To _replace_ a patch provided by Armbian maintainers, copy it from `lib/patch` to corresponding directory in `userpatches` and edit it to your needs. To _disable_ a patch, create empty file in corresponding directory in `userpatches`.

## User provided kernel config
If file `userpatches/linux-$KERNELFAMILY-$KERNELBRANCH.config` exists, it will be used instead of default one from `lib/config`. Look for the hint at the beginning of kernel compilation process to select proper config file name. Example:

    [ o.k. ] Compiling dev kernel [ @host ]
    [ o.k. ] Using kernel config file [ lib/config/linux-sunxi-dev.config ]

## User provided image customization script
You can run additional commands to customize created image. Edit file:

    userpatches/customize-image.sh

and place your code here. You may test values of variables noted in the file to use different commands for different configurations. Those commands will be executed in a chroot environment just before closing image.

To add files to image easily, put them in `userpatches/overlay` and access them in `/tmp/overlay` from `customize-image.sh`

## Partitioning of the SD card

In case you define `$FIXED_IMAGE_SIZE` at build time the partition containing the rootfs will be made of this size. Default behaviour when this is not defined and `$ROOTFS_TYPE` is set to _ext4_ is to shrink the partition to minimum size at build time and expand it to the card's maximum capacity at boot time (leaving an unpartitioned spare area of ~5% when the size is 4GB or less to help the SD card's controller with wear leveling and garbage collection on old/slow cards).

You can prevent the partition expansion from within `customize-image.sh` by a `touch /root/.no_rootfs_resize` or configure the resize operation by either a percentage or a sector count using `/root/.rootfs_resize` (`50%` will use only half of the card's size if the image size doesn't exceed this or `3887103s` for example will use sector 3887103 as partition end. Values without either `%` or `s` will be ignored)

# What is behind the build process?

Build process summary:
- creates development environment on the top of X86/AMD64 Ubuntu 14.04 LTS,
- downloads proven sources, applies patches and uses tested configurations,
- cross-compiles universal boot loader (u-boot), kernel and other tools and drivers,
- packs kernel, uboot, dtb and root customizations into debs,
- debootstraps minimalistic Debian Wheezy, Jessie and Ubuntu Trusty into SD card image,
- installs additional packets, applies customizations and shrinks image to its actual size.

Image compiling example with partial cache:

[su_youtube_advanced url="https:\/\/youtu.be\/zeShf12MNLg" controls="yes" showinfo="no" loop="yes" rel="no" modestbranding="yes"]

## Creating compile environment ##

At first run we are downloading all necessary dependencies. 

## Using board configuration ##

We need to get some predefined variables about selected board. Which kernel & uboot source to use, modules to load, which is the build number, do we need to have a single partition or dual with boot on fat, which extra drivers to compile out of the kernel tree, ...

**Board configuration example:**
    
	BOOTSIZE="16"											# FAT boot partition in MB, 0 for none
	BOOTCONFIG="udoo_neo_config"							# Which compile config to use		
	LINUXFAMILY="udoo"										# boards share kernel

Note that in this case, all main config options (kernel and uboot source) are covered within FAMILY. Check [configuration.sh](https://github.com/igorpecovnik/lib/blob/master/configuration.sh) for more config options.

This **isn't ment to be user configurable** but you can alter variables if you know what you are doing.

## Downloading sources ##

When we know where are the sources and where they need to be the download / update process starts. This might take from several minutes to several hours.

## Patching ##

In patching process we are appling patches to sources. The process is defined in:

	lib/patch/kernel/sun7i-default
	lib/patch/kernel/sunxi-dev	
	...
	lib/patch/u-boot/u-boot-default
	lib/patch/u-boot/u-boot-neo-default
	...

Patch rules for subdirectories are: **KERNEL_FAMILY-BRANCH** for kernel and **U-BOOT-SOURCE-BRANCH** for U-boot.

## Debootstrap ##

Debootstrap creates fresh Debian / Ubuntu root filesystem templates or use cached under:

	output/cache/rootfs/$DISTRIBUTION.tgz

To recreate those files you need to remove them manually. 

## Kernel install ##

When root filesystem is ready we need to install kernel image with modules, board definitions, firmwares. Along with this we set the CPU frequency min/max, hostname, modules, network interfaces templates. Here is also the place to install headers and fix + native compile them on the way.

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
	lib/debootstrap.sh		basic system template creation
	lib/distributions.sh	system specific installation and fixes
	lib/main.sh				user input and script calls
	lib/makeboarddeb.sh		creates board support package .deb
	lib/repo-update.sh		creates and updates your local repository
	lib/repo-show-sh		show packets in your local repository
	lib/upgrade.sh			script to upgrade older images
	sources/				source code for kernel, uboot and other utilities
	output/repository		repository 
	output/cache			cache for root filesystem and headers compilation
	output/debs				deb packeges
	output/images			zip packed RAW image
	userpatches/kernel		put your kernel patches here
	userpatches/u-boot		put your u-boot patches here
	userpatches/			put your kernel config here


## Additional info ##

- [Allwinner SBC community](https://linux-sunxi.org/)
