#!/bin/bash
#

mkdir -p ${upperdir}/usr/lib/nand-sata-install
mkdir -p ${upperdir}/usr/sbin

install -m 755 ${sectiondir}scripts/nand-sata-install/nand-sata-install ${upperdir}/usr/sbin
install -m 644 ${sectiondir}scripts/nand-sata-install/exclude.txt ${upperdir}/usr/lib/nand-sata-install