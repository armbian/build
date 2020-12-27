# install lightdm greeter
cp -R "${SRC}"/config/desktop/$RELEASE/enviroments/desktop-overlay/lightdm "${destination}"/etc/armbian

# install default desktop settings
#mkdir -p "${destination}"/etc/skel
#cp -R "${SRC}"/config/desktop/focal/enviroments/deepin/skel/. "${destination}"/etc/skel

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/config/desktop/$RELEASE/enviroments/desktop-overlay/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/armbian/
cp "${SRC}"/config/desktop/$RELEASE/enviroments/desktop-overlay/wallpapers/armbian*.jpg "${destination}"/usr/share/backgrounds/armbian/
