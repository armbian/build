#!/bin/bash
# Hidden_options

    ["id,ARMBIAN_MIRROR"]="ARMBIAN_MIRROR"
    ["author,ARMBIAN_MIRROR"]="null"
    ["src_reference,ARMBIAN_MIRROR"]="null"
    ["desc,ARMBIAN_MIRROR"]="Overrides automated mirror selection"
    ["example,ARMBIAN_MIRROR"]="null"
    ["status,ARMBIAN_MIRROR"]="active"
    ["doc_link,ARMBIAN_MIRROR"]=""


    ["id,AUFS"]="AUFS"
    ["author,AUFS"]="null"
    ["src_reference,AUFS"]="null"
    ["desc,AUFS"]="Include support for AUFS"
    ["example,AUFS"]="null"
    ["status,AUFS"]="active"
    ["doc_link,AUFS"]=""


    ["id,BOOTSIZE"]="BOOTSIZE"
    ["author,BOOTSIZE"]="null"
    ["src_reference,BOOTSIZE"]="null"
    ["desc,BOOTSIZE"]="Sets size (in megabytes) for separate /boot filesystem"
    ["example,BOOTSIZE"]="null"
    ["status,BOOTSIZE"]="active"
    ["doc_link,BOOTSIZE"]=""


    ["id,BTRFS_COMPRESSION"]="BTRFS_COMPRESSION"
    ["author,BTRFS_COMPRESSION"]="null"
    ["src_reference,BTRFS_COMPRESSION"]="null"
    ["desc,BTRFS_COMPRESSION"]="Selects btrfs filesystem compression method and compression level"
    ["example,BTRFS_COMPRESSION"]="null"
    ["status,BTRFS_COMPRESSION"]="active"
    ["doc_link,BTRFS_COMPRESSION"]=""


    ["id,BUILD_KSRC"]="BUILD_KSRC"
    ["author,BUILD_KSRC"]="null"
    ["src_reference,BUILD_KSRC"]="null"
    ["desc,BUILD_KSRC"]="Creates kernel source packages while building"
    ["example,BUILD_KSRC"]="null"
    ["status,BUILD_KSRC"]="active"
    ["doc_link,BUILD_KSRC"]=""


    ["id,COMPRESS_OUTPUTIMAGE"]="COMPRESS_OUTPUTIMAGE"
    ["author,COMPRESS_OUTPUTIMAGE"]="null"
    ["src_reference,COMPRESS_OUTPUTIMAGE"]="null"
    ["desc,COMPRESS_OUTPUTIMAGE"]="Specifies how to create compressed archive with image file and GPG signature for redistribution"
    ["example,COMPRESS_OUTPUTIMAGE"]="null"
    ["status,COMPRESS_OUTPUTIMAGE"]="active"
    ["doc_link,COMPRESS_OUTPUTIMAGE"]=""


    ["id,CONSOLE_AUTOLOGIN"]="CONSOLE_AUTOLOGIN"
    ["author,CONSOLE_AUTOLOGIN"]="null"
    ["src_reference,CONSOLE_AUTOLOGIN"]="null"
    ["desc,CONSOLE_AUTOLOGIN"]="Automatically login as root for local consoles"
    ["example,CONSOLE_AUTOLOGIN"]="null"
    ["status,CONSOLE_AUTOLOGIN"]="active"
    ["doc_link,CONSOLE_AUTOLOGIN"]=""


    ["id,DISABLE_IPV6"]="DISABLE_IPV6"
    ["author,DISABLE_IPV6"]="null"
    ["src_reference,DISABLE_IPV6"]="null"
    ["desc,DISABLE_IPV6"]="Controls whether to disable IPv6"
    ["example,DISABLE_IPV6"]="null"
    ["status,DISABLE_IPV6"]="active"
    ["doc_link,DISABLE_IPV6"]=""


    ["id,DOWNLOAD_MIRROR"]="DOWNLOAD_MIRROR"
    ["author,DOWNLOAD_MIRROR"]="null"
    ["src_reference,DOWNLOAD_MIRROR"]="null"
    ["desc,DOWNLOAD_MIRROR"]="Selects download mirror for toolchain and debian/ubuntu packages"
    ["example,DOWNLOAD_MIRROR"]="null"
    ["status,DOWNLOAD_MIRROR"]="active"
    ["doc_link,DOWNLOAD_MIRROR"]=""


    ["id,EXPERT"]="EXPERT"
    ["author,EXPERT"]="null"
    ["src_reference,EXPERT"]="null"
    ["desc,EXPERT"]="Show development features and boards regardless of status in interactive mode"
    ["example,EXPERT"]="null"
    ["status,EXPERT"]="active"
    ["doc_link,EXPERT"]=""


    ["id,EXT"]="EXT"
    ["author,EXT"]="null"
    ["src_reference,EXT"]="null"
    ["desc,EXT"]="Executes extension during the build"
    ["example,EXT"]="null"
    ["status,EXT"]="active"
    ["doc_link,EXT"]=""


    ["id,EXTRAWIFI"]="EXTRAWIFI"
    ["author,EXTRAWIFI"]="null"
    ["src_reference,EXTRAWIFI"]="null"
    ["desc,EXTRAWIFI"]="Includes several drivers for WiFi adapters"
    ["example,EXTRAWIFI"]="null"
    ["status,EXTRAWIFI"]="active"
    ["doc_link,EXTRAWIFI"]=""


    ["id,FIXED_IMAGE_SIZE"]="FIXED_IMAGE_SIZE"
    ["author,FIXED_IMAGE_SIZE"]="null"
    ["src_reference,FIXED_IMAGE_SIZE"]="null"
    ["desc,FIXED_IMAGE_SIZE"]="Creates image file of specified size (in megabytes)"
    ["example,FIXED_IMAGE_SIZE"]="null"
    ["status,FIXED_IMAGE_SIZE"]="active"
    ["doc_link,FIXED_IMAGE_SIZE"]=""


    ["id,FORCE_BOOTSCRIPT_UPDATE"]="FORCE_BOOTSCRIPT_UPDATE"
    ["author,FORCE_BOOTSCRIPT_UPDATE"]="null"
    ["src_reference,FORCE_BOOTSCRIPT_UPDATE"]="null"
    ["desc,FORCE_BOOTSCRIPT_UPDATE"]="Forces bootscript to get updated during bsp package upgrade"
    ["example,FORCE_BOOTSCRIPT_UPDATE"]="null"
    ["status,FORCE_BOOTSCRIPT_UPDATE"]="active"
    ["doc_link,FORCE_BOOTSCRIPT_UPDATE"]=""


    ["id,FORCE_USE_RAMDISK"]="FORCE_USE_RAMDISK"
    ["author,FORCE_USE_RAMDISK"]="null"
    ["src_reference,FORCE_USE_RAMDISK"]="null"
    ["desc,FORCE_USE_RAMDISK"]="Overrides autodetect for using tmpfs in new debootstrap and image creation process"
    ["example,FORCE_USE_RAMDISK"]="null"
    ["status,FORCE_USE_RAMDISK"]="active"
    ["doc_link,FORCE_USE_RAMDISK"]=""


    ["id,GITHUB_MIRROR"]="GITHUB_MIRROR"
    ["author,GITHUB_MIRROR"]="null"
    ["src_reference,GITHUB_MIRROR"]="null"
    ["desc,GITHUB_MIRROR"]="Selects download mirror for GitHub hosted repository"
    ["example,GITHUB_MIRROR"]="null"
    ["status,GITHUB_MIRROR"]="active"
    ["doc_link,GITHUB_MIRROR"]=""


    ["id,IMAGE_XZ_COMPRESSION_RATIO"]="IMAGE_XZ_COMPRESSION_RATIO"
    ["author,IMAGE_XZ_COMPRESSION_RATIO"]="null"
    ["src_reference,IMAGE_XZ_COMPRESSION_RATIO"]="null"
    ["desc,IMAGE_XZ_COMPRESSION_RATIO"]="Specifies images compression levels when using xz compressor"
    ["example,IMAGE_XZ_COMPRESSION_RATIO"]="null"
    ["status,IMAGE_XZ_COMPRESSION_RATIO"]="active"
    ["doc_link,IMAGE_XZ_COMPRESSION_RATIO"]=""


    ["id,INCLUDE_HOME_DIR"]="INCLUDE_HOME_DIR"
    ["author,INCLUDE_HOME_DIR"]="null"
    ["src_reference,INCLUDE_HOME_DIR"]="null"
    ["desc,INCLUDE_HOME_DIR"]="Includes directories created inside /home in final image"
    ["example,INCLUDE_HOME_DIR"]="null"
    ["status,INCLUDE_HOME_DIR"]="active"
    ["doc_link,INCLUDE_HOME_DIR"]=""


    ["id,INSTALL_KSRC"]="INSTALL_KSRC"
    ["author,INSTALL_KSRC"]="null"
    ["src_reference,INSTALL_KSRC"]="null"
    ["desc,INSTALL_KSRC"]="Pre-installs kernel sources on the image"
    ["example,INSTALL_KSRC"]="null"
    ["status,INSTALL_KSRC"]="active"
    ["doc_link,INSTALL_KSRC"]=""


    ["id,MAINLINE_MIRROR"]="MAINLINE_MIRROR"
    ["author,MAINLINE_MIRROR"]="null"
    ["src_reference,MAINLINE_MIRROR"]="null"
    ["desc,MAINLINE_MIRROR"]="Selects mainline mirror of linux-stable.git"
    ["example,MAINLINE_MIRROR"]="null"
    ["status,MAINLINE_MIRROR"]="active"
    ["doc_link,MAINLINE_MIRROR"]=""


    ["id,NAMESERVER"]="NAMESERVER"
    ["author,NAMESERVER"]="null"
    ["src_reference,NAMESERVER"]="null"
    ["desc,NAMESERVER"]="Specifies the DNS resolver used inside the build chroot"
    ["example,NAMESERVER"]="null"
    ["status,NAMESERVER"]="active"
    ["doc_link,NAMESERVER"]=""


    ["id,NO_APT_CACHER"]="NO_APT_CACHER"
    ["author,NO_APT_CACHER"]="null"
    ["src_reference,NO_APT_CACHER"]="null"
    ["desc,NO_APT_CACHER"]="Disables usage of APT cache"
    ["example,NO_APT_CACHER"]="null"
    ["status,NO_APT_CACHER"]="active"
    ["doc_link,NO_APT_CACHER"]=""


    ["id,NO_HOST_RELEASE_CHECK"]="NO_HOST_RELEASE_CHECK"
    ["author,NO_HOST_RELEASE_CHECK"]="null"
    ["src_reference,NO_HOST_RELEASE_CHECK"]="null"
    ["desc,NO_HOST_RELEASE_CHECK"]="Overrides the check for a supported host system"
    ["example,NO_HOST_RELEASE_CHECK"]="null"
    ["status,NO_HOST_RELEASE_CHECK"]="active"
    ["doc_link,NO_HOST_RELEASE_CHECK"]=""


    ["id,OFFLINE_WORK"]="OFFLINE_WORK"
    ["author,OFFLINE_WORK"]="null"
    ["src_reference,OFFLINE_WORK"]="null"
    ["desc,OFFLINE_WORK"]="Controls whether to skip downloading and updating sources"
    ["example,OFFLINE_WORK"]="null"
    ["status,OFFLINE_WORK"]="active"
    ["doc_link,OFFLINE_WORK"]=""


    ["id,PRIVATE_CCACHE"]="PRIVATE_CCACHE"
    ["author,PRIVATE_CCACHE"]="null"
    ["src_reference,PRIVATE_CCACHE"]="null"
    ["desc,PRIVATE_CCACHE"]="Controls whether to use $DEST/ccache as ccache home directory"
    ["example,PRIVATE_CCACHE"]="null"
    ["status,PRIVATE_CCACHE"]="active"
    ["doc_link,PRIVATE_CCACHE"]=""


    ["id,PROGRESS_DISPLAY"]="PROGRESS_DISPLAY"
    ["author,PROGRESS_DISPLAY"]="null"
    ["src_reference,PROGRESS_DISPLAY"]="null"
    ["desc,PROGRESS_DISPLAY"]="Specifies the way to display output of verbose processes"
    ["example,PROGRESS_DISPLAY"]="null"
    ["status,PROGRESS_DISPLAY"]="active"
    ["doc_link,PROGRESS_DISPLAY"]=""


    ["id,PROGRESS_LOG_TO_FILE"]="PROGRESS_LOG_TO_FILE"
    ["author,PROGRESS_LOG_TO_FILE"]="null"
    ["src_reference,PROGRESS_LOG_TO_FILE"]="null"
    ["desc,PROGRESS_LOG_TO_FILE"]="Controls whether to duplicate output to log files"
    ["example,PROGRESS_LOG_TO_FILE"]="null"
    ["status,PROGRESS_LOG_TO_FILE"]="active"
    ["doc_link,PROGRESS_LOG_TO_FILE"]=""


    ["id,REGIONAL_MIRROR"]="REGIONAL_MIRROR"
    ["author,REGIONAL_MIRROR"]="null"
    ["src_reference,REGIONAL_MIRROR"]="null"
    ["desc,REGIONAL_MIRROR"]="Selects mirrors based on regional setting"
    ["example,REGIONAL_MIRROR"]="null"
    ["status,REGIONAL_MIRROR"]="active"
    ["doc_link,REGIONAL_MIRROR"]=""


    ["id,ROOTFS_TYPE"]="ROOTFS_TYPE"
    ["author,ROOTFS_TYPE"]="null"
    ["src_reference,ROOTFS_TYPE"]="null"
    ["desc,ROOTFS_TYPE"]="Creates image with different root filesystems instead of default ext4"
    ["example,ROOTFS_TYPE"]="null"
    ["status,ROOTFS_TYPE"]="active"
    ["doc_link,ROOTFS_TYPE"]=""


    ["id,ROOT_FS_CREATE_ONLY"]="ROOT_FS_CREATE_ONLY"
    ["author,ROOT_FS_CREATE_ONLY"]="null"
    ["src_reference,ROOT_FS_CREATE_ONLY"]="null"
    ["desc,ROOT_FS_CREATE_ONLY"]="Forces local cache creation"
    ["example,ROOT_FS_CREATE_ONLY"]="null"
    ["status,ROOT_FS_CREATE_ONLY"]="active"
    ["doc_link,ROOT_FS_CREATE_ONLY"]=""


    ["id,SEVENZIP"]="SEVENZIP"
    ["author,SEVENZIP"]="null"
    ["src_reference,SEVENZIP"]="null"
    ["desc,SEVENZIP"]="Creates .7z archive with extreme compression ratio instead of .zip"
    ["example,SEVENZIP"]="null"
    ["status,SEVENZIP"]="active"
    ["doc_link,SEVENZIP"]=""


    ["id,SKIP_BOOTSPLASH"]="SKIP_BOOTSPLASH"
    ["author,SKIP_BOOTSPLASH"]="null"
    ["src_reference,SKIP_BOOTSPLASH"]="null"
    ["desc,SKIP_BOOTSPLASH"]="Uses kernel bootsplash"
    ["example,SKIP_BOOTSPLASH"]="null"
    ["status,SKIP_BOOTSPLASH"]="active"
    ["doc_link,SKIP_BOOTSPLASH"]=""


    ["id,SKIP_EXTERNAL_TOOLCHAINS"]="SKIP_EXTERNAL_TOOLCHAINS"
    ["author,SKIP_EXTERNAL_TOOLCHAINS"]="null"
    ["src_reference,SKIP_EXTERNAL_TOOLCHAINS"]="null"
    ["desc,SKIP_EXTERNAL_TOOLCHAINS"]="Controls whether to download and use Linaro toolchains"
    ["example,SKIP_EXTERNAL_TOOLCHAINS"]="null"
    ["status,SKIP_EXTERNAL_TOOLCHAINS"]="active"
    ["doc_link,SKIP_EXTERNAL_TOOLCHAINS"]=""


    ["id,SYNC_CLOCK"]="SYNC_CLOCK"
    ["author,SYNC_CLOCK"]="null"
    ["src_reference,SYNC_CLOCK"]="null"
    ["desc,SYNC_CLOCK"]="Controls whether to sync system clock on builder before starting image creation process"
    ["example,SYNC_CLOCK"]="null"
    ["status,SYNC_CLOCK"]="active"
    ["doc_link,SYNC_CLOCK"]=""


    ["id,UBOOT_MIRROR"]="UBOOT_MIRROR"
    ["author,UBOOT_MIRROR"]="null"
    ["src_reference,UBOOT_MIRROR"]="null"
    ["desc,UBOOT_MIRROR"]="Selects mainline mirror of u-boot.git"
    ["example,UBOOT_MIRROR"]="null"
    ["status,UBOOT_MIRROR"]="active"
    ["doc_link,UBOOT_MIRROR"]=""


    ["id,USERPATCHES_PATH"]="USERPATCHES_PATH"
    ["author,USERPATCHES_PATH"]="null"
    ["src_reference,USERPATCHES_PATH"]="null"
    ["desc,USERPATCHES_PATH"]="Sets alternate path for location of userpatches folder"
    ["example,USERPATCHES_PATH"]="null"
    ["status,USERPATCHES_PATH"]="active"
    ["doc_link,USERPATCHES_PATH"]=""


    ["id,USE_CCACHE"]="USE_CCACHE"
    ["author,USE_CCACHE"]="null"
    ["src_reference,USE_CCACHE"]="null"
    ["desc,USE_CCACHE"]="Controls whether to use a C compiler cache"
    ["example,USE_CCACHE"]="null"
    ["status,USE_CCACHE"]="active"
    ["doc_link,USE_CCACHE"]=""


    ["id,USE_GITHUB_UBOOT_MIRROR"]="USE_GITHUB_UBOOT_MIRROR"
    ["author,USE_GITHUB_UBOOT_MIRROR"]="null"
    ["src_reference,USE_GITHUB_UBOOT_MIRROR"]="null"
    ["desc,USE_GITHUB_UBOOT_MIRROR"]="Controls whether to use unofficial Github mirror for downloading mainline U-Boot sources"
    ["example,USE_GITHUB_UBOOT_MIRROR"]="null"
    ["status,USE_GITHUB_UBOOT_MIRROR"]="active"
    ["doc_link,USE_GITHUB_UBOOT_MIRROR"]=""


    ["id,USE_MAINLINE_GOOGLE_MIRROR"]="USE_MAINLINE_GOOGLE_MIRROR"
    ["author,USE_MAINLINE_GOOGLE_MIRROR"]="null"
    ["src_reference,USE_MAINLINE_GOOGLE_MIRROR"]="null"
    ["desc,USE_MAINLINE_GOOGLE_MIRROR"]="Controls whether to use googlesource.com mirror for downloading mainline kernel sources"
    ["example,USE_MAINLINE_GOOGLE_MIRROR"]="null"
    ["status,USE_MAINLINE_GOOGLE_MIRROR"]="active"
    ["doc_link,USE_MAINLINE_GOOGLE_MIRROR"]=""


    ["id,USE_TORRENT"]="USE_TORRENT"
    ["author,USE_TORRENT"]="null"
    ["src_reference,USE_TORRENT"]="null"
    ["desc,USE_TORRENT"]="Uses torrent to download toolchains and rootfs"
    ["example,USE_TORRENT"]="null"
    ["status,USE_TORRENT"]="active"
    ["doc_link,USE_TORRENT"]=""


    ["id,WIREGUARD"]="WIREGUARD"
    ["author,WIREGUARD"]="null"
    ["src_reference,WIREGUARD"]="null"
    ["desc,WIREGUARD"]="Includes Wireguard for kernels before it got upstreamed to mainline"
    ["example,WIREGUARD"]="null"
    ["status,WIREGUARD"]="active"
    ["doc_link,WIREGUARD"]=""

# Main_options

    ["id,BSPFREEZE"]="BSPFREEZE"
    ["author,BSPFREEZE"]="null"
    ["src_reference,BSPFREEZE"]="null"
    ["desc,BSPFREEZE"]="Controls whether to freeze armbian packages when building images"
    ["example,BSPFREEZE"]="null"
    ["status,BSPFREEZE"]="active"
    ["doc_link,BSPFREEZE"]=""


    ["id,BUILD_ALL"]="BUILD_ALL"
    ["author,BUILD_ALL"]="null"
    ["src_reference,BUILD_ALL"]="null"
    ["desc,BUILD_ALL"]="Controls whether to cycle through all available board and kernel configurations"
    ["example,BUILD_ALL"]="null"
    ["status,BUILD_ALL"]="active"
    ["doc_link,BUILD_ALL"]=""


    ["id,BUILD_DESKTOP"]="BUILD_DESKTOP"
    ["author,BUILD_DESKTOP"]="null"
    ["src_reference,BUILD_DESKTOP"]="null"
    ["desc,BUILD_DESKTOP"]="Controls whether to build image with minimal desktop environment"
    ["example,BUILD_DESKTOP"]="null"
    ["status,BUILD_DESKTOP"]="active"
    ["doc_link,BUILD_DESKTOP"]=""


    ["id,BUILD_MINIMAL"]="BUILD_MINIMAL"
    ["author,BUILD_MINIMAL"]="null"
    ["src_reference,BUILD_MINIMAL"]="null"
    ["desc,BUILD_MINIMAL"]="Controls whether to build bare CLI image suitable for application deployment"
    ["example,BUILD_MINIMAL"]="null"
    ["status,BUILD_MINIMAL"]="active"
    ["doc_link,BUILD_MINIMAL"]=""


    ["id,BUILD_ONLY"]="BUILD_ONLY"
    ["author,BUILD_ONLY"]="xx"
    ["src_reference,BUILD_ONLY"]="xx"
    ["desc,BUILD_ONLY"]="Defines what artifacts should be built"
    ["example,BUILD_ONLY"]="./compile.sh BUILD_ONLY=u-boot,kernel,armbian-config"
    ["status,BUILD_ONLY"]="active"
    ["doc_link,BUILD_ONLY"]=""


    ["id,CARD_DEVICE"]="CARD_DEVICE"
    ["author,CARD_DEVICE"]="null"
    ["src_reference,CARD_DEVICE"]="null"
    ["desc,CARD_DEVICE"]="Sets the device of the SD card"
    ["example,CARD_DEVICE"]="null"
    ["status,CARD_DEVICE"]="active"
    ["doc_link,CARD_DEVICE"]=""


    ["id,CLEAN_LEVEL"]="CLEAN_LEVEL"
    ["author,CLEAN_LEVEL"]="null"
    ["src_reference,CLEAN_LEVEL"]="null"
    ["desc,CLEAN_LEVEL"]="Defines what should be cleaned"
    ["example,CLEAN_LEVEL"]="null"
    ["status,CLEAN_LEVEL"]="active"
    ["doc_link,CLEAN_LEVEL"]=""


    ["id,CREATE_PATCHES"]="CREATE_PATCHES"
    ["author,CREATE_PATCHES"]="null"
    ["src_reference,CREATE_PATCHES"]="null"
    ["desc,CREATE_PATCHES"]="Controls whether to prompt for making changes to source code for U-Boot and kernel"
    ["example,CREATE_PATCHES"]="null"
    ["status,CREATE_PATCHES"]="active"
    ["doc_link,CREATE_PATCHES"]=""


    ["id,CRYPTROOT_ENABLE"]="CRYPTROOT_ENABLE"
    ["author,CRYPTROOT_ENABLE"]="null"
    ["src_reference,CRYPTROOT_ENABLE"]="null"
    ["desc,CRYPTROOT_ENABLE"]="Enables LUKS encrypted rootfs"
    ["example,CRYPTROOT_ENABLE"]="null"
    ["status,CRYPTROOT_ENABLE"]="active"
    ["doc_link,CRYPTROOT_ENABLE"]=""


    ["id,EXT"]="EXT"
    ["author,EXT"]="null"
    ["src_reference,EXT"]="null"
    ["desc,EXT"]="Executes extension during the build"
    ["example,EXT"]="null"
    ["status,EXT"]="active"
    ["doc_link,EXT"]=""


    ["id,EXTERNAL"]="EXTERNAL"
    ["author,EXTERNAL"]="null"
    ["src_reference,EXTERNAL"]="null"
    ["desc,EXTERNAL"]="Controls whether to compile and install extra applications and firmware"
    ["example,EXTERNAL"]="null"
    ["status,EXTERNAL"]="active"
    ["doc_link,EXTERNAL"]=""


    ["id,EXTERNAL_NEW"]="EXTERNAL_NEW"
    ["author,EXTERNAL_NEW"]="null"
    ["src_reference,EXTERNAL_NEW"]="null"
    ["desc,EXTERNAL_NEW"]="Controls whether to install extra applications from repository or compile them in chroot"
    ["example,EXTERNAL_NEW"]="null"
    ["status,EXTERNAL_NEW"]="active"
    ["doc_link,EXTERNAL_NEW"]=""


    ["id,INSTALL_HEADERS"]="INSTALL_HEADERS"
    ["author,INSTALL_HEADERS"]="null"
    ["src_reference,INSTALL_HEADERS"]="null"
    ["desc,INSTALL_HEADERS"]="Controls whether to install kernel headers"
    ["example,INSTALL_HEADERS"]="null"
    ["status,INSTALL_HEADERS"]="active"
    ["doc_link,INSTALL_HEADERS"]=""


    ["id,KERNEL_CONFIGURE"]="KERNEL_CONFIGURE"
    ["author,KERNEL_CONFIGURE"]="null"
    ["src_reference,KERNEL_CONFIGURE"]="null"
    ["desc,KERNEL_CONFIGURE"]="Controls kernel configuration"
    ["example,KERNEL_CONFIGURE"]="null"
    ["status,KERNEL_CONFIGURE"]="active"
    ["doc_link,KERNEL_CONFIGURE"]=""


    ["id,KERNEL_KEEP_CONFIG"]="KERNEL_KEEP_CONFIG"
    ["author,KERNEL_KEEP_CONFIG"]="null"
    ["src_reference,KERNEL_KEEP_CONFIG"]="null"
    ["desc,KERNEL_KEEP_CONFIG"]="Controls whether to use kernel config file from previous compilation"
    ["example,KERNEL_KEEP_CONFIG"]="null"
    ["status,KERNEL_KEEP_CONFIG"]="active"
    ["doc_link,KERNEL_KEEP_CONFIG"]=""


    ["id,KERNEL_ONLY"]="KERNEL_ONLY"
    ["author,KERNEL_ONLY"]="null"
    ["src_reference,KERNEL_ONLY"]="null"
    ["desc,KERNEL_ONLY"]="Compiles only kernel, U-Boot, and other packages for installation on existing Armbian system"
    ["example,KERNEL_ONLY"]="null"
    ["status,KERNEL_ONLY"]="deprecated"
    ["doc_link,KERNEL_ONLY"]=""


    ["id,LIB_TAG"]="LIB_TAG"
    ["author,LIB_TAG"]="null"
    ["src_reference,LIB_TAG"]="null"
    ["desc,LIB_TAG"]="Sets the branch to compile from"
    ["example,LIB_TAG"]="null"
    ["status,LIB_TAG"]="active"
    ["doc_link,LIB_TAG"]=""


    ["id,REPOSITORY_INSTALL"]="REPOSITORY_INSTALL"
    ["author,REPOSITORY_INSTALL"]="null"
    ["src_reference,REPOSITORY_INSTALL"]="null"
    ["desc,REPOSITORY_INSTALL"]="List of core packages which will be installed from repository"
    ["example,REPOSITORY_INSTALL"]="null"
    ["status,REPOSITORY_INSTALL"]="active"
    ["doc_link,REPOSITORY_INSTALL"]=""

