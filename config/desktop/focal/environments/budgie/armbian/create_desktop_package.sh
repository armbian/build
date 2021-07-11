# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

#install desktop bar icons
mkdir -p "${destination}"/usr/share/icons/armbian
cp "${SRC}"/packages/blobs/desktop/desktop-icons/*.png "${destination}"/usr/share/icons/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/armbian/
cp "${SRC}"/packages/blobs/desktop/wallpapers/*.jpg "${destination}"/usr/share/backgrounds/armbian/

mkdir -p "${destination}"/usr/share/cinnamon-background-properties
cat <<EOF > "${destination}"/usr/share/cinnamon-background-properties/armbian.xml
<?xml version="1.0"?>
<!DOCTYPE wallpapers SYSTEM "cinnamon-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>Armbian light</name>
    <filename>/usr/share/backgrounds/armbian/armbian18-Dre0x-Minum-light-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian dark</name>
    <filename>/usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian uc</name>
    <filename>/usr/share/backgrounds/armbian/armbian-full-undeer-construction-3840-2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian clear</name>
    <filename>/usr/share/backgrounds/armbian/Armbian-clear-rounded-bakcground-3840-2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian black_pyscho</name>
    <filename>/usr/share/backgrounds/armbian/armbian_4k_black_psycho.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian bluie_monday</name>
    <filename>/usr/share/backgrounds/armbian/armbian_4k_bluie_monday.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian grey</name>
    <filename>/usr/share/backgrounds/armbian/armbian_4k_gray.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian green</name>
    <filename>/usr/share/backgrounds/armbian/armbian_4k_green.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian purplepunk</name>
    <filename>/usr/share/backgrounds/armbian/armbian_4k_purplepunk.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
EOF
