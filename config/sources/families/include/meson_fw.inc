FWNAME=meson

family_firmware_install() {
# amlogic vdec firmware
    mkdir -p $1/meson/vdec/
	cp -rpf $SRC/cache/sources/linux-firmware-git/meson/vdec/* $1/meson/vdec/
# brcm wifi/bt firmware
}
