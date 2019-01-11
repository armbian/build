#!/bin/bash
#

mkdir -p ${upperdir}/usr/lib/nand-sata-install
mkdir -p ${upperdir}/usr/sbin

install -m 755 ${sectiondir}scripts/nand-sata-install/nand-sata-install ${upperdir}/usr/sbin
install -m 644 ${sectiondir}scripts/nand-sata-install/exclude.txt ${upperdir}/usr/lib/nand-sata-install

# Family tweaks
case $RELEASE in
	"jessie"|"stretch")
		PACKAGE_TO_REMOVE="alsa-base alsa-utils bluez"
		;;
	"xenial"|"bionic")
		PACKAGE_TO_REMOVE="linux-sound-base alsa-base alsa-utils bluez"
		;;
esac

chroot $SDCARD /bin/bash -c "apt-get -y -qq remove --auto-remove $PACKAGE_TO_REMOVE >/dev/null 2>&1"
