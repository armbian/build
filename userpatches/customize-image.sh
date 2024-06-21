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
    # Pre-initialization steps.
    # =========================================================================
    # Source overlay environment configuration.
    set -a
    source /tmp/overlay/env
    set +a

    # Generate locales.
    export LANG=C LC_ALL="en_US.UTF-8"
    locale-gen en_US.UTF-8

    # Update hostname.
    echo "dmbpro" > /etc/hostname

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
    # - php-xml                         Packages needed for Laravel application.
    # - php-dom
    # - php-sqlite3
    # - composer
    # - npm
    # - apache2                         Web server.
    # - libapache2-mod-php
    # =========================================================================
    export DEBIAN_FRONTEND="noninteractive"
    export APT_LISTCHANGES_FRONTEND="none"
    add-apt-repository -y ppa:jjriek/panfork-mesa
    add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia
    apt-get update -y
    apt-get install -y systemd-repart mali-g610-firmware rockchip-multimedia-config rauc-service libubootenv-tool meson libcurl4-openssl-dev libjson-glib-dev chromium-browser python3-shortuuid vim cmake libcairo2-dev gettext php-xml php-dom php-sqlite3 composer apache2 libapache2-mod-php npm
    apt-get dist-upgrade -y

    # =========================================================================
    # Copy overlay filesystem & other files to root.
    # =========================================================================
    cp -r /tmp/overlay/rootfs/* /
    cp /tmp/overlay/cert.pem /etc/rauc

    sed -i "s#::HAWKBIT_SERVER_URL::#$HAWKBIT_SERVER_URL#" /etc/rauc/hawkbit.conf
    sed -i "s/::HAWKBIT_GATEWAY_TOKEN::/$HAWKBIT_GATEWAY_TOKEN/" /etc/rauc/hawkbit.conf

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
    useradd -m -d /home/dmbuser -s /bin/bash dmbuser
    echo "dmbuser:$APP_USER_PASSWORD" | chpasswd
	for new_group in netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh render; do
		usermod -aG "${new_group}" dmbuser 2> /dev/null
	done
    {
	    echo "export LANG=en_US.UTF-8"
	    echo "export LANGUAGE=en_US"
    } >> /home/dmbuser/.bashrc
    {
	    echo "export LANG=en_US.UTF-8"
	    echo "export LANGUAGE=en_US"
    } >> /home/dmbuser/.xsessionrc
    mkdir -p /home/dmbuser/.config/autostart && cp /tmp/overlay/autostart/* /home/dmbuser/.config/autostart

    # =========================================================================
    # Setup developer user
    # =========================================================================
    useradd -m -d /home/dev -s /bin/bash dev
    echo "dev:$DEV_USER_PASSWORD" | chpasswd
    for new_group in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh render www-data; do
		usermod -aG "${new_group}" dev 2> /dev/null
	done

    # =========================================================================
    # Build and install Gnome hide top bar
    # =========================================================================
    git clone https://gitlab.gnome.org/tuxor1337/hidetopbar.git /tmp/hidetopbar
    cd /tmp/hidetopbar
    make
    sudo -Hu dmbuser gnome-extensions install ./hidetopbar.zip
    
    # =========================================================================
    # Retrieve and install main application.
    # =========================================================================
    # Retrieve and setup application from remote repository.
    export COMPOSER_MAX_PARALLEL_HTTP=4
    git clone https://$APP_REPOSITORY_USER:$APP_REPOSITORY_TOKEN@github.com/$APP_REPOSITORY_PATH /srv/dmbpro
    git -C /srv/dmbpro remote set-url origin git@github.com:$APP_REPOSITORYPATH
    cp /srv/dmbpro/.env.dmbp /srv/dmbpro/.env
    chown -R www-data:www-data /srv/dmbpro  # Set ownership to www-data
    sudo -Hu www-data composer -d /srv/dmbpro install --no-dev
    php /srv/dmbpro/artisan key:generate --force
    php /srv/dmbpro/artisan migrate --force
    php /srv/dmbpro/artisan optimize
    php /srv/dmbpro/artisan config:cache
    php /srv/dmbpro/artisan event:cache
    php /srv/dmbpro/artisan route:cache
    php /srv/dmbpro/artisan view:cache
    chown -R www-data:www-data /srv/dmbpro  # Set ownership to www-data
    chmod -R g+w /srv/dmbpro                # Enable group write permissions
    chmod -R o-r /srv/dmbpro                # Disable other user read permissions

    # Install new site to Apache2 configuration.
    a2enmod rewrite
    a2dissite 000-default
    a2ensite dmbp

    # =========================================================================
    # Enable desktop manager auto-login.
    # =========================================================================
    mkdir -p /etc/gdm3
    cat <<- EOF > /etc/gdm3/custom.conf
    [daemon]
    AutomaticLoginEnable = true
    AutomaticLogin = dmbuser
EOF
    ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service

    # =========================================================================
    # Final / Cleanup tasks.
    # =========================================================================
    systemctl enable dmbp-updater    
    systemctl enable dmbp-install-armbian
    systemctl enable dmbp-app-queue-worker
    systemctl enable dmbp-app-schedule-worker
    systemctl enable ssh

    # Setup WiFi/Bluetooth drivers for Orange Pi 5B. At this time, Armbian
    # doesn't support the board natively, so must configure this manually.
    echo "overlays=orangepi-5-ap6275p" >> /boot/armbianEnv.txt
    sed -i '/fdtfile/c fdtfile=rockchip/rk3588s-orangepi-5b.dtb' /boot/armbianEnv.txt   # Set Orange Pi 5B device tree
} # Main

Main "$@"
