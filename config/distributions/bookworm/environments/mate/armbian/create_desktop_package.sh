# install lightdm greeter
mkdir -p "${destination}"/etc/riscv
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/riscv

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel.all/. "${destination}"/etc/skel

#install cinnamon desktop bar icons
mkdir -p "${destination}"/usr/share/icons/riscv
cp "${SRC}"/packages/blobs/desktop/icons/riscv-chip-logo.png "${destination}"/usr/share/icons/riscv

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/riscv/
cp "${SRC}"/packages/blobs/desktop/desktop-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/riscv

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/lightdm/
cp "${SRC}"/packages/blobs/desktop/lightdm-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/lightdm

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/riscv
cp "${SRC}"/packages/blobs/desktop/icons/riscv-chip-logo.png "${destination}"/usr/share/pixmaps/riscv

#generate wallpaper list for background changer
mkdir -p "${destination}"/usr/share/mate-background-properties
cat <<EOF > "${destination}"/usr/share/mate-background-properties/rv64os.xml
<?xml version="1.0"?>
<!DOCTYPE wallpapers SYSTEM "mate-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>RV64OS logo0</name>
    <filename>/usr/share/backgrounds/riscv/Riscv-0-logo.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>RV64OS bluie-circle</name>
    <filename>/usr/share/backgrounds/riscv/Riscv-1-logo.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>RV64OS bluie-circle</name>
    <filename>/usr/share/backgrounds/riscv/Riscv-2-logo.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>RV64OS blue-monday</name>
    <filename>/usr/share/backgrounds/riscv/Riscv-3-logo.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>RV64OS blue-penguin</name>
    <filename>/usr/share/backgrounds/riscv/Riscv-4-logo.jpg/filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
EOF
