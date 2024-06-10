#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
        noble)
            # MAIN DMB PRO CUSTOMIZATION CODE

            # 1. Copy overlay files.
            cp -r /tmp/overlay/rootfs/* /
            cp /tmp/overlay/cert.pem /etc/rauc

            # 2. Install necessary packages.
            export DEBIAN_FRONTEND="noninteractive"
            export APT_LISTCHANGES_FRONTEND="none"
            add-apt-repository -y ppa:jjriek/panfork-mesa                   # Mali G610 GPU drivers
            add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia   # Mali G610 GPU-supported software
            apt-get update -y
            apt-get install -q -y systemd-repart                            # Used for setting up A/B partition layout
            apt install -y mali-g610-firmware rockchip-multimedia-config    # Mali G610 drivers and config
            apt install -y rauc-service                                     # Rauc OTA update tool
            apt install -y libubootenv-tool                                 # U-Boot environment manipulation tools
            apt dist-upgrade -y

            # 3. Setup administrator user
	        rm /root/.not_logged_in_yet     # Disable Armbian interactive setup.
            useradd -m -d /home/dmb -s /bin/bash dmb
            echo dmb:$(cat /tmp/overlay/password) | chpasswd
			for new_group in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh render; do
				usermod -aG "${new_group}" dmb 2> /dev/null
			done
            export LANG=C LC_ALL="en_US.UTF-8"
            locale-gen en_US.UTF-8
            {
			    echo "export LANG=en_US.UTF-8"
			    echo "export LANGUAGE=en_US"
		    } >> /home/dmb/.bashrc
		    {
			    echo "export LANG=en_US.UTF-8"
			    echo "export LANGUAGE=en_US"
		    } >> /home/dmb/.xsessionrc

            # 4. Enable Gnome/GDM auto-login.
		    mkdir -p /etc/gdm3
		    cat <<- EOF > /etc/gdm3/custom.conf
            [daemon]
            AutomaticLoginEnable = true
            AutomaticLogin = dmb
EOF
            ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service

            # 5. Final tasks
            systemctl enable auto-install-armbian                                               # Auto install/update bootloader
            echo "overlays=orangepi-5-ap6275p" >> /boot/armbianEnv.txt                          # Enable Orange Pi WiFi/Bluetooth drivers
            sed -i '/fdtfile/c fdtfile=rockchip/rk3588s-orangepi-5b.dtb' /boot/armbianEnv.txt   # Set Orange Pi 5B device tree

            # MAIN DMB PRO CUSTOMIZATION CODE
            ;;
		stretch)
			# your code here
			# InstallOpenMediaVault # uncomment to get an OMV 4 image
			;;
		buster)
			# your code here
			;;
		bullseye)
			# your code here
			;;
		bionic)
			# your code here
			;;
		focal)
			# your code here
			;;
	esac
} # Main

Main "$@"
