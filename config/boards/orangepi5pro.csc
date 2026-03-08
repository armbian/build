# Rockchip RK3588S octa core 4/8/16GB RAM SoC GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 5 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_5_pro_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOTCONFIG_SATA="orangepi_5_pro_sata_defconfig"
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-orangepi-5-pro.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"

function post_family_tweaks__orangepi5pro_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi5pro audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_config_branch_vendor__orangepi5pro_uboot_add_sata_target() {
	display_alert "$BOARD" "Configuring ($BOARD) standard and sata uboot target map" "info"
	# Note: whitespace/newlines are significant; BOOT_SUPPORT_SPI & BOOT_SPI_RKSPI_LOADER influence the postprocess step that runs for _every_ target and produces rkspi_loader.img
	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB $BOOTCONFIG spl/u-boot-spl.bin u-boot.dtb u-boot.itb;;idbloader.img u-boot.itb rkspi_loader.img
	BL31=$RKBIN_DIR/$BL31_BLOB $BOOTCONFIG_SATA spl/u-boot-spl.bin u-boot.dtb u-boot.itb;; rkspi_loader_sata.img"
}

function post_uboot_custom_postprocess__create_sata_spi_image() {
	display_alert "$BOARD" "Create rkspi_loader_sata.img" "info"

	dd if=/dev/zero of=rkspi_loader_sata.img bs=1M count=0 seek=16
	/sbin/parted -s rkspi_loader_sata.img mklabel gpt
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart idbloader 64 7167
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart vnvm 7168 7679
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved_space 7680 8063
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved1 8064 8127
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart uboot_env 8128 8191
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart reserved2 8192 16383
	/sbin/parted -s rkspi_loader_sata.img unit s mkpart uboot 16384 32734
	dd if=idbloader.img of=rkspi_loader_sata.img seek=64 conv=notrunc
	dd if=u-boot.itb of=rkspi_loader_sata.img seek=16384 conv=notrunc
}

function post_family_config_branch_edge__orangepi5pro_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	declare -g BOOTCONFIG="orangepi-5-pro-rk3588s_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.07"
	declare -g BOOTPATCHDIR="v2025.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	declare -g INSTALL_HEADERS="yes"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	function write_uboot_platform_mtd() {
		flashcp -v -p "$1/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}

# Install Ethernet Driver during first boot
function pre_customize_image__orangepi5pro_add_phy_driver() {
    local deb_file="tuxedo-yt6801_1.0.28-1_all.deb"
    local service_name="eth-driver-firstboot.service"
    
    display_alert "Setting up Ethernet driver build for first boot" "$BOARD" "info"
    
    # Pre-install dependencies
    chroot_sdcard apt-get update
    chroot_sdcard apt-get install -y dkms build-essential
    
    # Create directory and download .deb (Not installing due to chroot issue with dkms and kernel headers)
    chroot_sdcard mkdir -p /usr/local/share/eth-driver
    chroot_sdcard curl -fL "https://github.com/dante1613/Motorcomm-YT6801/raw/main/tuxedo-yt6801/${deb_file}" -o "/usr/local/share/eth-driver/${deb_file}"
    
    # Make script to Auto-Install Ethernet Driver Only on first boot
    cat << 'EOF' > "${SDCARD}/usr/local/bin/install-eth-driver.sh"
#!/bin/bash
set -e

DEB_FILE="/usr/local/share/eth-driver/tuxedo-yt6801_1.0.28-1_all.deb"
LOG_FILE="/var/log/eth-driver-install.log"

# Wait for dpkg locks to be released
wait_for_dpkg() {
    echo "Checking package manager locks..." >> $LOG_FILE
    
    # Wait for up to 1 minute
    local timeout=60
    local start_time=$(date +%s)
    
    while true; do
        # Check if we've exceeded timeout
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt $timeout ]; then
            echo "Timeout waiting for locks to be released. Continuing anyway..." >> $LOG_FILE
            break
        fi
        
        # Check for dpkg locks
        if lsof /var/lib/dpkg/lock >/dev/null 2>&1 || \
           lsof /var/lib/apt/lists/lock >/dev/null 2>&1 || \
           lsof /var/cache/apt/archives/lock >/dev/null 2>&1 || \
           lsof /var/cache/debconf/config.dat >/dev/null 2>&1; then
            echo "Waiting for package manager locks to be released... ($(date))" >> $LOG_FILE
            sleep 1
            continue
        else
            echo "All package manager locks are available" >> $LOG_FILE
            break
        fi
    done
}

# Install driver package without internet
install_driver() {
    echo "Starting driver install" >> $LOG_FILE
    local max_attempts=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $max_attempts ]; do
        echo "Installation attempt $attempt of $max_attempts" >> $LOG_FILE
        # Always wait for dpkg locks before attempting
        wait_for_dpkg
        
        # Try to install the package
        if dpkg -i $DEB_FILE >> $LOG_FILE 2>&1; then
            echo "Installation successful on attempt $attempt" >> $LOG_FILE
            success=true
            break
        else
            echo "Installation attempt $attempt failed" >> $LOG_FILE
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$success" = true ]; then
        echo "Ethernet driver installed correctly." >> $LOG_FILE
        # Clean up files
        rm -f $DEB_FILE
        # Disable service
        systemctl disable eth-driver-firstboot.service
        return 0
    else
        echo "Failed to install driver after $max_attempts attempts." >> $LOG_FILE
        # Don't exit with error to avoid service failure
        return 0
    fi
}

# Execute installation
install_driver
EOF
    
    # Make executable script
    chmod +x "${SDCARD}/usr/local/bin/install-eth-driver.sh"
    
    # Creating the service
    cat << EOF > "${SDCARD}/etc/systemd/system/${service_name}"
[Unit]
Description=Install YT6801 Ethernet driver on first boot
After=systemd-modules-load.service
Before=network.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/install-eth-driver.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable service for First Boot
    chroot_sdcard systemctl enable "${service_name}"
    
    display_alert "Ethernet driver setup complete" "Will be installed on first boot (offline)" "info"
}

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__orangepi5pro_use_vendor_uboot() {
	BOOTSOURCE='https://github.com/orangepi-xunlong/u-boot-orangepi.git'
	BOOTBRANCH='branch:v2017.09-rk3588'
	BOOTPATCHDIR="legacy"
}
