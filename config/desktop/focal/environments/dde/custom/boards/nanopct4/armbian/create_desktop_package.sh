# install custom xorg for pinebook-pro
cp -R "${SRC}"/packages/bsp/rk3399/xorg.conf "${destination}"/etc/X11/

# install custom asound state for pinebook-pro
cp -R "${SRC}"/packages/asound.state/ "${destination}"/etc/

	
