# Armbian colors for whiptail and debconf. libnewt reads only this variable, not /etc/newt/palette.
[ -r /etc/newt/palette.armbian ] && export NEWT_COLORS_FILE=/etc/newt/palette.armbian
