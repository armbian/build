#!/bin/bash
#
# Sources for utilities in usr/local/bin
# https://github.com/BPI-SINOVOIP/BPI-R2-bsp/tree/master/vendor/mediatek/connectivity/tools/binary

[[ -f $SDCARD/etc/netplan/armbian-default.yaml ]] && sed -i "s/^  renderer.*/  renderer: networkd/" $SDCARD/etc/netplan/armbian-default.yaml

cp ${lowerdir}overlay/etc/armbian/mt7623/10*  $SDCARD/etc/systemd/network/

# very unstable wifi driver, disabled by default http://www.fw-web.de/dokuwiki/doku.php?id=en:bpi-r2:wlan#internal
# chroot $SDCARD /bin/bash -c "systemctl --no-reload enable mt7623-wifi.service >/dev/null 2>&1"

mkdir -p ${upperdir}/usr/lib/nand-sata-install
mkdir -p ${upperdir}/usr/sbin

install -m 755 ${sectiondir}scripts/nand-sata-install/nand-sata-install ${upperdir}/usr/sbin
install -m 644 ${sectiondir}scripts/nand-sata-install/exclude.txt ${upperdir}/usr/lib/nand-sata-install
