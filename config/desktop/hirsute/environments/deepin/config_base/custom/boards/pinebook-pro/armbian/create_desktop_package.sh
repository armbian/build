# install custom xorg for pinebook-pro
cp -R "${SRC}"/packages/bsp/pinebook-pro/xorg.conf "${destination}"/etc/X11/xorg.conf.d/

# install custom asound state for pinebook-pro
cp -R "${SRC}"/packages/asound.state/ "${destination}"/etc/