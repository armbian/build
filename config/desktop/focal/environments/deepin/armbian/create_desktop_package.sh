# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel_dde/. "${destination}"/etc/skel

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/wallpapers/armbian/
cp "${SRC}"/packages/blobs/desktop/wallpapers/armbian*.jpg "${destination}"/usr/share/wallpapers/armbian/
