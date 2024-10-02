# overwrite stock lightdm greeter configuration
if [ -d /etc/armbian/lightdm ]; then cp -R /etc/armbian/lightdm /etc/; fi

# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i  /etc/pulse/default.pa; fi

# set wallpapper to armbian
echo "exec_always --no-startup-id feh --bg-scale --zoom fill --no-fehbg /usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg" | tee -a /etc/i3/config

# lightdm wallpaper
mv /etc/lightdm/slick-greeter.conf /etc/lightdm/slick-greeter.conf.bak
touch /etc/lightdm/slick-greeter.conf
echo "[Greeter]
background=/usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg
theme-name = Numix
icon-theme-name = Numix
font-name = Sans 11
draw-user-background = false
show-keyboard = true
onscreen-keyboard = false
screen-reader = true
draw-grid = true" | tee -a /etc/lightdm/slick-greeter.conf

echo "Finished preparing /etc/lightdm/slick-greeter.conf..."

mv /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.bak
touch /etc/lightdm/lightdm-gtk-greeter.conf
echo "[greeter]
background=/usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg
theme-name = Numix
icon-theme-name = Numix
font-name = Sans 11
draw-user-background = false
show-keyboard = true
onscreen-keyboard = false
screen-reader = true
draw-grid = true" | tee -a /etc/lightdm/lightdm-gtk-greeter.conf

echo "Finished preparing /etc/lightdm/lightdm-gtk-greeter.conf..."

slick-greeter -h #applies wallpaper
