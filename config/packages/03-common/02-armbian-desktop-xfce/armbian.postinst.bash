cat <<EOF
# overwrite stock chromium configuration
if [ -d /etc/chromium-browser/ ]; then
	ln -sf /etc/armbian/chromium.conf /etc/chromium-browser/default
fi

if [ -d /etc/chromium.d/ ]; then
	ln -sf /etc/armbian/chromium.conf /etc/chromium.d/chromium.conf
fi

# copy basic bookmarks
cp -R /etc/armbian/chromium /usr/share

# overwrite stock lightdm greeter configuration
if [ -d /etc/armbian/lightdm ]; then
	cp -R /etc/armbian/lightdm /etc/
fi

# overwrite stock firefox configuration
if [ -d /usr/lib/firefox-esr/ ]; then
	ln -sf /etc/armbian/firefox.conf /usr/lib/firefox-esr/mozilla.cfg
	echo 'pref("general.config.obscure_value", 0);' > /usr/lib/firefox-esr/defaults/pref/local-settings.js
	echo 'pref("general.config.filename", "mozilla.cfg");' >> /usr/lib/firefox-esr/defaults/pref/local-settings.js
fi

# adjust menu
sed -i -n '/<Menuname>Settings<\/Menuname>/{p;:a;N;/<Filename>xfce4-session-logout.desktop<\/Filename>/!ba;s/.*\n/\
\t<Separator\/>\n\t<Merge type="all"\/>\n        <Separator\/>\n        <Filename>armbian-donate.desktop<\/Filename>\
\n        <Filename>armbian-support.desktop<\/Filename>\n/};p' /etc/xdg/menus/xfce-applications.menu

# hide few items
if [ -f /usr/share/applications/display-im6.q16.desktop ]; then
	mv /usr/share/applications/display-im6.q16.desktop /usr/share/applications/display-im6.q16.desktop.hidden
fi

if [ -f /usr/share/applications/display-im6.desktop ]]; then
	mv /usr/share/applications/display-im6.desktop /usr/share/applications/display-im6.desktop.hidden
fi

if [ -f /usr/share/applications/vim.desktop ]]; then
	mv /usr/share/applications/vim.desktop /usr/share/applications/vim.desktop.hidden
fi

if [ -f /usr/share/applications/libreoffice-startcenter.desktop ]]; then
	mv /usr/share/applications/libreoffice-startcenter.desktop /usr/share/applications/libreoffice-startcenter.desktop.hidden
fi

# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
if [ -f /etc/pulse/default.pa ]; then
	sed "s/load-module module-udev-detect$/& tsched=0/g" -i  /etc/pulse/default.pa
fi

# using different icon pack. Workaround due to this bug https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=867779
sed -i 's/<property name="IconThemeName" type="string" value="Numix"\/>/<property name="IconThemeName" type="string" value="Humanity-Dark">/g' /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml

# install dedicated startup icons
sed 's/xenial.png/${DISTRIBUTION,,}.png/' -i $destination/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
EOF