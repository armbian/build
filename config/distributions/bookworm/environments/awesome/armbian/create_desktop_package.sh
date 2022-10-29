# install lightdm greeter
mkdir -p "${destination}"/etc/riscv
cp -R "${SRC}"/packages/blobs/desktop/lightdm "${destination}"/etc/riscv

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${SRC}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

#install cinnamon desktop bar icons
mkdir -p "${destination}"/usr/share/icons/riscv
cp "${SRC}"/packages/blobs/desktop/desktop-icons/*.png "${destination}"/usr/share/icons/riscv

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/riscv/
cp "${SRC}"/packages/blobs/desktop/desktop-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/riscv

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/lightdm/
cp "${SRC}"/packages/blobs/desktop/lightdm-wallpapers/*.jpg "${destination}"/usr/share/backgrounds/lightdm

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/riscv
cp "${SRC}"/packages/blobs/desktop/icons/riscv-chip-logo.png "${destination}"/usr/share/pixmaps/riscv
