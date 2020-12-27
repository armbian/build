# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/config/desktop/focal/enviroments/xfce/skel/. "${destination}"/etc/skel

# using different icon pack. Workaround due to this bug https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=867779
sed -i 's/<property name="IconThemeName" type="string" value=".*$/<property name="IconThemeName" type="string" value="Humanity-Dark"\/>/g' \
"${destination}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

# install dedicated startup icons
mkdir -p "${destination}"/usr/share/pixmaps/armbian "${destination}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
cp "${SRC}/config/desktop/desktop-extras/icons/${DISTRIBUTION,,}.png" "${destination}"/usr/share/pixmaps/armbian
sed 's/xenial.png/'"${DISTRIBUTION,,}"'.png/' -i "${destination}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml

