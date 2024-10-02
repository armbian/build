# install optimized browser configurations
cp "${SRC}"/packages/blobs/desktop/chromium.conf "${destination}"/etc/armbian
cp "${SRC}"/packages/blobs/desktop/firefox.conf  "${destination}"/etc/armbian
cp -R "${SRC}"/packages/blobs/desktop/chromium "${destination}"/etc/armbian
