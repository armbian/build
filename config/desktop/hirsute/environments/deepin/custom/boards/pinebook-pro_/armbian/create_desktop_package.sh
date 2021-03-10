# install custom xorg for pinebook-pro
cp -R "${SRC}"/packages/bsp/pinebook-pro/xorg.conf "${destination}"/etc/X11/

## touchpad and keyboard tweaks
# from https://github.com/ayufan-rock64/linux-package/tree/master/root-pinebookpro
cp $SRC/packages/bsp/pinebook-pro/40-pinebookpro-touchpad.conf $destination/etc/X11/xorg.conf.d/
#keybord
mkdir -p $destination/etc/udev/hwdb.d/
cp $SRC/packages/bsp/pinebook-pro/10-usb-kbd.hwdb $destination/etc/udev/hwdb.d/

## brightness and power management defaults
mkdir -p $destination/usr/local/share/xdg/xfce4/xfconf/xfce-perchannel-xml/
cp $SRC/packages/bsp/pinebook-pro/xfce4-power-manager.xml $destination/usr/local/share/xdg/xfce4/xfconf/xfce-perchannel-xml/

# install custom asound state for pinebook-pro
cp -R "${SRC}"/packages/asound.state/ "${destination}"/etc/

	
