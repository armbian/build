# install optimized browser configurations
cp "${SRC}"/config/desktop/focal/appgroups/browsers/configs/chromium.conf "${destination}"/etc/armbian
cp "${SRC}"/config/desktop/focal/appgroups/browsers/configs/firefox.conf  "${destination}"/etc/armbian
cp -R "${SRC}"/config/desktop/focal/appgroups/browsers/chromium "${destination}"/etc/armbian
