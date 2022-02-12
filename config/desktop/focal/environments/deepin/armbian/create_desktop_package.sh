# install lightdm greeter
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/armbian

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

#install cinnamon desktop bar icons
mkdir -p "${destination}"/usr/share/icons/armbian
cp "${SRC}"/packages/blobs/desktop/desktop-icons/*.png "${destination}"/usr/share/icons/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/armbian/
cp "${SRC}"/packages/blobs/desktop/desktop-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/armbian

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/armbian-lightdm/
cp "${SRC}"/packages/blobs/desktop/lightdm-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/armbian-lightdm

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/armbian
cp "${SRC}"/packages/blobs/desktop/icons/armbian.png "${destination}"/usr/share/pixmaps/armbian

#generate wallpaper list for background changer
mkdir -p "${destination}"/usr/share/deepin-background-properties
cat << EOF > "${destination}"/usr/share/deepin-background-properties/armbian.xml
<?xml version="1.0"?>
<!DOCTYPE wallpapers SYSTEM "deepin-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>Armbian black-pyscho</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-black-psycho.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian bluie-circle</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-blue-circle.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian blue-monday</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-blue-monday.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian blue-penguin</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-blue-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian gray-resultado</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-gray.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian green-penguin</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-green-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian green-retro</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-green-retro.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian green-wall-penguin</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-green-wall-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian 4k-neglated</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-neglated.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian neon-gray-penguin</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-neon-gray-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian plastic-love</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-plastic-love.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian purple-penguine</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-purple-penguine.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
    <wallpaper deleted="false">
    <name>Armbian purplepunk-resultado</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-purplepunk.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian red-penguin-dark</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-red-penguin-dark.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Armbian red-penguin</name>
    <filename>/usr/share/backgrounds/armbian/armbian-4k-red-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
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
    <filename>/usr/share/backgrounds/armbian/armbian-full-under-construction-3840-2160.jpg</filename>
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
</wallpapers>
EOF
