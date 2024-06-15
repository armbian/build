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
    # =========================================================================
    # Source overlay environment configuration.
    # =========================================================================
    set -a
    source /tmp/overlay/env
    set +a

    # =========================================================================
    # Copy overlay filesystem & other files to root.
    # =========================================================================
    cp -r /tmp/overlay/rootfs/* /
    cp /tmp/overlay/cert.pem /etc/rauc

    sed -i "s#::HAWKBIT_SERVER_URL::#$HAWKBIT_SERVER_URL#" /etc/rauc/hawkbit.conf
    sed -i "s/::HAWKBIT_GATEWAY_TOKEN::/$HAWKBIT_GATEWAY_TOKEN/" /etc/rauc/hawkbit.conf

    # =========================================================================
    # Install drivers, software packages and update system.
    #
    # - systemd-repart:                 Setting up A/B partition layout.
    # - mali-g610-firmware:             Mali G610 drivers and config.
    # - rockchip-multimedia-config
    # - rauc-service                    Rauc OTA update system.
    # - libubootenv-tool                U-Boot tools needed for rauc-service.
    # - meson                           Build tools needed for rauc-hawkbit-updater.
    # - libcurl4-openssl-dev            
    # - libjson-glib-dev
    # - chromium-browser                GPU-enabled Chromium from rockchip-multimedia-config.
    # - python3-shortuuid               Random ID generator for Hawkbit initial target name.
    # - vim                             Text editor for remote / CLI development.
    # - cmake                           Build tools needed for gnome-monitor-config.
    # - libcairo2-dev
    # - gettext                         Build tools needed for Gnome Hide Top Bar extension.
    # =========================================================================
    export DEBIAN_FRONTEND="noninteractive"
    export APT_LISTCHANGES_FRONTEND="none"
    add-apt-repository -y ppa:jjriek/panfork-mesa
    add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia
    apt-get update -y
    apt-get install -y systemd-repart mali-g610-firmware rockchip-multimedia-config rauc-service libubootenv-tool meson libcurl4-openssl-dev libjson-glib-dev chromium-browser python3-shortuuid vim cmake libcairo2-dev gettext
    apt-get dist-upgrade -y

    # =========================================================================
    # Build and install rauc-hawkbit-updater
    # =========================================================================
    git clone https://github.com/rauc/rauc-hawkbit-updater /tmp/rauc-hawkbit-updater
    cd /tmp/rauc-hawkbit-updater
    meson setup build
    ninja -C build
    cp build/rauc-hawkbit-updater /usr/sbin

    # =========================================================================
    # Build and install gnome-monitor-config
    # =========================================================================
    git clone https://github.com/jadahl/gnome-monitor-config /tmp/gnome-monitor-config
    cd /tmp/gnome-monitor-config
    meson build
    cd build
    meson compile
    cp src/gnome-monitor-config /usr/bin

    # =========================================================================
    # Setup main user
    # =========================================================================
    rm /root/.not_logged_in_yet     # Disable Armbian interactive setup.
    useradd -m -d /home/dmb -s /bin/bash dmb
    echo "dmb:$USER_PASSWORD" | chpasswd
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
    mkdir -p /home/dmb/.config/autostart && cp /tmp/overlay/autostart/* /home/dmb/.config/autostart

    # =========================================================================
    # Build and install Gnome hide top bar
    # =========================================================================
    git clone https://gitlab.gnome.org/tuxor1337/hidetopbar.git /tmp/hidetopbar
    cd /tmp/hidetopbar
    make
    sudo -Hu dmb gnome-extensions install ./hidetopbar.zip

    # =========================================================================
    # Enable desktop manager auto-login.
    # =========================================================================
    mkdir -p /etc/gdm3
    cat <<- EOF > /etc/gdm3/custom.conf
    [daemon]
    AutomaticLoginEnable = true
    AutomaticLogin = dmb
EOF
    ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service

    # =========================================================================
    # Final / Cleanup tasks.
    # =========================================================================
    systemctl enable dmbp-updater    
    systemctl enable dmbp-install-armbian

    # Setup WiFi/Bluetooth drivers for Orange Pi 5B. At this time, Armbian
    # doesn't support the board natively, so must configure this manually.
    echo "overlays=orangepi-5-ap6275p" >> /boot/armbianEnv.txt
    sed -i '/fdtfile/c fdtfile=rockchip/rk3588s-orangepi-5b.dtb' /boot/armbianEnv.txt   # Set Orange Pi 5B device tree
} # Main

Main "$@"
