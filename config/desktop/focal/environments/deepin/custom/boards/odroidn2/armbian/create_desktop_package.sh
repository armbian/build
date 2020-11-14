# install custom xorg for pinebook-pro
mkdir -p "${destination}"/etc/X11/
cp -R "${SRC}"/packages/bsp/odroid/xorg.conf "${destination}"/etc/X11/
