# Armbian colors for whiptail and debconf. libnewt 0.52.25+ reads only this variable.
# Older libnewt reads /etc/newt/palette: the BSP postinst points it to palette.armbian.
[ -r /etc/newt/palette.armbian ] && export NEWT_COLORS_FILE=/etc/newt/palette.armbian
