# install custom xorg for pinebook-pro
mkdir -p "${destination}"/etc/X11/
cp -R "${SRC}"/packages/bsp/pinebook-pro/xorg.conf "${destination}"/etc/X11/

# install custom asound state for pinebook-pro
cp -R "${SRC}"/packages/blobs/asound.state/asound.state.pinebook-pro "${destination}"/etc/

## touchpad and keyboard tweaks
mkdir -p "${destination}"/etc/X11/xorg.conf.d/
# from https://github.com/ayufan-rock64/linux-package/tree/master/root-pinebookpro
cp "${SRC}"/packages/bsp/pinebook-pro/40-pinebookpro-touchpad.conf "${destination}"/etc/X11/xorg.conf.d/
#keyboard hwdb
mkdir -p "${destination}"/etc/udev/hwdb.d/
cp "${SRC}"/packages/bsp/pinebook-pro/10-usb-kbd.hwdb "${destination}"/etc/udev/hwdb.d/
