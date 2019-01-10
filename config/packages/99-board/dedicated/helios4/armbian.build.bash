#!/bin/bash
#

mkdir -p ${upperdir}/etc/
mkdir -p ${upperdir}/usr/share/${ARMBIAN_PKG_PACKAGE}

## Fancontrol tweaks
cp ${lowerdir}/helios4-temp/fancontrol.patch ${upperdir}/usr/share/${ARMBIAN_PKG_PACKAGE}/

case $BRANCH in
default)
	install -m 644 ${lowerdir}helios4-temp/fancontrol_pwm-fan-mvebu-default.conf ${upperdir}/etc/fancontrol
	;;
next)
	install -m 644 ${lowerdir}helios4-temp/fancontrol_pwm-fan-mvebu-next.conf ${upperdir}/etc/fancontrol
	;;
esac
