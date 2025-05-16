# overwrite stock lightdm greeter configuration
if [ -d /etc/armbian/lightdm ]; then cp -R /etc/armbian/lightdm /etc/; fi

# Disable Pulseaudio timer scheduling which does not work with sndhdmi driver
if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i  /etc/pulse/default.pa; fi

# set wallpapper to armbian


