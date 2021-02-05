# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

# install backgrounds
mkdir -p "${destination}"/usr/share/backgrounds/armbian/
cp "${SRC}"/packages/blobs/desktop/wallpapers/*.jpg "${destination}"/usr/share/backgrounds/armbian/
