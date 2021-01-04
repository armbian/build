# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/wallpapers/armbian/
cp "${SRC}"/packages/blobs/desktop/wallpapers/armbian*.jpg "${destination}"/usr/share/wallpapers/armbian/
