# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/xfce/
cp "${SRC}"/packages/blobs/desktop/wallpapers/armbian*.jpg "${destination}"/usr/share/backgrounds/xfce/

# add loading desktop splash service
mkdir -p "${destination}"/etc/systemd/system/
cp "${SRC}"/packages/blobs/desktop/desktop-splash/desktop-splash.service "${destination}"/etc/systemd/system/desktop-splash.service
