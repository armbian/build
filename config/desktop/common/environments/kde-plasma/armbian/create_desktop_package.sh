# install sddm greeter theme
mkdir -p "${destination}"/usr/share/sddm/themes
cp -R "${SRC}"/packages/blobs/desktop/sddm/themes/plasma-chili/ "${destination}"/usr/share/sddm/themes

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/armbian/
cp "${SRC}"/packages/blobs/desktop/desktop-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/armbian

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

# set default wallpaper
#echo "
#dbus-send --session --dest=org.kde.plasmashell --type=method_call /PlasmaShell org.kde.PlasmaShell.evaluateScript 'string:
#var Desktops = desktops();
#for (i=0;i<Desktops.length;i++) {
#        d = Desktops[i];
#        d.wallpaperPlugin = \"org.kde.image\";
#        d.currentConfigGroup = Array(\"Wallpaper\",
#                                    \"org.kde.image\",
#                                    \"General\");
#        d.writeConfig(\"Image\", \"file:///usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg\");
#}'" > "${destination}"/usr/share/backgrounds/armbian/set-armbian-wallpaper.sh
