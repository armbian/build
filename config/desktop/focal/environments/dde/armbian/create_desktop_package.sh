# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel_dde/. "${destination}"/etc/skel

# install logo for login screen
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/deepin/
cp "${SRC}"/packages/blobs/desktop/wallpapers/armbian*.jpg "${destination}"/usr/share/backgrounds/deepin/
ln -s "${destination}"/usr/share/backgrounds/deepin/armbian03-Dre0x-Minum-dark-3840x2160.jpg "${destination}"/usr/share/backgrounds/deepin/desktop.jpg

# add loading desktop splash service
mkdir -p "${destination}"/etc/systemd/system/
cp "${SRC}"/packages/blobs/desktop/desktop-splash/desktop-splash.service "${destination}"/etc/systemd/system/desktop-splash.service
