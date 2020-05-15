#!/bin/bash
set -e
set -x

OVERLAY_PATH=/tmp/overlay/internetcube

InstallInternetCubeServices(){

  # Install InternetCube dependencies usb detection, hotspot, vpnclient, roundcube
  apt-get install -o Dpkg::Options::='--force-confold' -y \
    file udisks2 udiskie ntfs-3g jq \
    php7.0-fpm sipcalc hostapd iptables iw dnsmasq firmware-linux-free \
    sipcalc dnsutils openvpn curl fake-hwclock \
    php-cli php-common php-intl php-json php-mcrypt php-pear php-auth-sasl php-mail-mime php-patchwork-utf8 php-net-smtp php-net-socket php-net-ldap2 php-net-ldap3 php-zip php-gd php-mbstring php-curl

  # Install hypercube service
  mkdir -p /var/log/hypercube
  install -m 755 -o root -g root ${OVERLAY_PATH}/hypercube.sh /usr/local/bin/
  install -m 444 -o root -g root ${OVERLAY_PATH}/hypercube.service /etc/systemd/system/
  install -m 444 -o root -g root ${OVERLAY_PATH}/install.html /var/log/hypercube/

  # Enable hypercube service
  # TODO use systemctl for doing this
  ln -f -s '/etc/systemd/system/hypercube.service' /etc/systemd/system/multi-user.target.wants/hypercube.service

}

