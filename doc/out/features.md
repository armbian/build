# Hidden_options

| Feature |  desc | example | src_reference | status |
| :-----: | :---: | :---: | :-----: | :---------: |
| ARMBIAN_MIRROR | Overrides automated mirror selection | null | [references](null) |  active | 
| AUFS | Include support for AUFS | null | [references](null) |  active | 
| BOOTSIZE | Sets size (in megabytes) for separate /boot filesystem | null | [references](null) |  active | 
| BTRFS_COMPRESSION | Selects btrfs filesystem compression method and compression level | null | [references](null) |  active | 
| BUILD_KSRC | Creates kernel source packages while building | null | [references](null) |  active | 
| COMPRESS_OUTPUTIMAGE | Specifies how to create compressed archive with image file and GPG signature for redistribution | null | [references](null) |  active | 
| CONSOLE_AUTOLOGIN | Automatically login as root for local consoles | null | [references](null) |  active | 
| DISABLE_IPV6 | Controls whether to disable IPv6 | null | [references](null) |  active | 
| DOWNLOAD_MIRROR | Selects download mirror for toolchain and debian/ubuntu packages | null | [references](null) |  active | 
| EXPERT | Show development features and boards regardless of status in interactive mode | null | [references](null) |  active | 
| EXT | Executes extension during the build | null | [references](null) |  active | 
| EXTRAWIFI | Includes several drivers for WiFi adapters | null | [references](null) |  active | 
| FIXED_IMAGE_SIZE | Creates image file of specified size (in megabytes) | null | [references](null) |  active | 
| FORCE_BOOTSCRIPT_UPDATE | Forces bootscript to get updated during bsp package upgrade | null | [references](null) |  active | 
| FORCE_USE_RAMDISK | Overrides autodetect for using tmpfs in new debootstrap and image creation process | null | [references](null) |  active | 
| GITHUB_MIRROR | Selects download mirror for GitHub hosted repository | null | [references](null) |  active | 
| IMAGE_XZ_COMPRESSION_RATIO | Specifies images compression levels when using xz compressor | null | [references](null) |  active | 
| INCLUDE_HOME_DIR | Includes directories created inside /home in final image | null | [references](null) |  active | 
| INSTALL_KSRC | Pre-installs kernel sources on the image | null | [references](null) |  active | 
| MAINLINE_MIRROR | Selects mainline mirror of linux-stable.git | null | [references](null) |  active | 
| NAMESERVER | Specifies the DNS resolver used inside the build chroot | null | [references](null) |  active | 
| NO_APT_CACHER | Disables usage of APT cache | null | [references](null) |  active | 
| NO_HOST_RELEASE_CHECK | Overrides the check for a supported host system | null | [references](null) |  active | 
| OFFLINE_WORK | Controls whether to skip downloading and updating sources | null | [references](null) |  active | 
| PRIVATE_CCACHE | Controls whether to use $DEST/ccache as ccache home directory | null | [references](null) |  active | 
| PROGRESS_DISPLAY | Specifies the way to display output of verbose processes | null | [references](null) |  active | 
| PROGRESS_LOG_TO_FILE | Controls whether to duplicate output to log files | null | [references](null) |  active | 
| REGIONAL_MIRROR | Selects mirrors based on regional setting | null | [references](null) |  active | 
| ROOTFS_TYPE | Creates image with different root filesystems instead of default ext4 | null | [references](null) |  active | 
| ROOT_FS_CREATE_ONLY | Forces local cache creation | null | [references](null) |  active | 
| SEVENZIP | Creates .7z archive with extreme compression ratio instead of .zip | null | [references](null) |  active | 
| SKIP_BOOTSPLASH | Uses kernel bootsplash | null | [references](null) |  active | 
| SKIP_EXTERNAL_TOOLCHAINS | Controls whether to download and use Linaro toolchains | null | [references](null) |  active | 
| SYNC_CLOCK | Controls whether to sync system clock on builder before starting image creation process | null | [references](null) |  active | 
| UBOOT_MIRROR | Selects mainline mirror of u-boot.git | null | [references](null) |  active | 
| USERPATCHES_PATH | Sets alternate path for location of userpatches folder | null | [references](null) |  active | 
| USE_CCACHE | Controls whether to use a C compiler cache | null | [references](null) |  active | 
| USE_GITHUB_UBOOT_MIRROR | Controls whether to use unofficial Github mirror for downloading mainline U-Boot sources | null | [references](null) |  active | 
| USE_MAINLINE_GOOGLE_MIRROR | Controls whether to use googlesource.com mirror for downloading mainline kernel sources | null | [references](null) |  active | 
| USE_TORRENT | Uses torrent to download toolchains and rootfs | null | [references](null) |  active | 
| WIREGUARD | Includes Wireguard for kernels before it got upstreamed to mainline | null | [references](null) |  active | 
# Main_options

| Feature |  desc | example | src_reference | status |
| :-----: | :---: | :---: | :-----: | :---------: |
| BSPFREEZE | Controls whether to freeze armbian packages when building images | null | [references](null) |  active | 
| BUILD_ALL | Controls whether to cycle through all available board and kernel configurations | null | [references](null) |  active | 
| BUILD_DESKTOP | Controls whether to build image with minimal desktop environment | null | [references](null) |  active | 
| BUILD_MINIMAL | Controls whether to build bare CLI image suitable for application deployment | null | [references](null) |  active | 
| BUILD_ONLY | Defines what artifacts should be built | ./compile.sh BUILD_ONLY=u-boot,kernel,armbian-config | [references](xx) |  active | 
| CARD_DEVICE | Sets the device of the SD card | null | [references](null) |  active | 
| CLEAN_LEVEL | Defines what should be cleaned | null | [references](null) |  active | 
| CREATE_PATCHES | Controls whether to prompt for making changes to source code for U-Boot and kernel | null | [references](null) |  active | 
| CRYPTROOT_ENABLE | Enables LUKS encrypted rootfs | null | [references](null) |  active | 
| EXT | Executes extension during the build | null | [references](null) |  active | 
| EXTERNAL | Controls whether to compile and install extra applications and firmware | null | [references](null) |  active | 
| EXTERNAL_NEW | Controls whether to install extra applications from repository or compile them in chroot | null | [references](null) |  active | 
| INSTALL_HEADERS | Controls whether to install kernel headers | null | [references](null) |  active | 
| KERNEL_CONFIGURE | Controls kernel configuration | null | [references](null) |  active | 
| KERNEL_KEEP_CONFIG | Controls whether to use kernel config file from previous compilation | null | [references](null) |  active | 
| KERNEL_ONLY | Compiles only kernel, U-Boot, and other packages for installation on existing Armbian system | null | [references](null) |  deprecated | 
| LIB_TAG | Sets the branch to compile from | null | [references](null) |  active | 
| REPOSITORY_INSTALL | List of core packages which will be installed from repository | null | [references](null) |  active | 
