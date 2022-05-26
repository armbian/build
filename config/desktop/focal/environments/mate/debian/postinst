# overwrite stock lightdm greeter configuration
if [ -d /etc/armbian/lightdm ]; then cp -R /etc/armbian/lightdm /etc/; fi

# disable Pulseaudio timer scheduling which does not work with sndhdmi driver
if [ -f /etc/pulse/default.pa ]; then sed "s/load-module module-udev-detect$/& tsched=0/g" -i /etc/pulse/default.pa; fi

##dconf desktop settings
keys=/etc/dconf/db/local.d/00-desktop
profile=/etc/dconf/profile/user

install -Dv /dev/null $keys
install -Dv /dev/null $profile

# gather dconf settings
# deconf dump org/nemo/ > nemo_backup
# deconf dump org/mate/ > cinnamon_desktop_backup

echo "[org/nemo/list-view]
default-visible-columns=['name', 'size', 'type', 'date_modified', 'owner', 'permissions']

[org/nemo/preferences]
quick-renames-with-pause-in-between=true
show-advanced-permissions=true
show-compact-view-icon-toolbar=false
show-full-path-titles=true
show-hidden-files=true
show-home-icon-toolbar=true
show-icon-view-icon-toolbar=false
show-image-thumbnails='never'
show-list-view-icon-toolbar=false
show-new-folder-icon-toolbar=true
show-open-in-terminal-toolbar=true

[org/nemo/window-state]
geometry='800x550+550+244'
maximized=false
sidebar-bookmark-breakpoint=5

[org/mate]
desklet-decorations=0
desktop-effects=false
enabled-applets=['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:1:show-desktop@cinnamon.org:1', 'panel1:left:2:grouped-window-list@cinnamon.org:2', 'panel1:right:0:systray@cinnamon.org:3', 'panel1:right:1:xapp-status@cinnamon.org:4', 'panel1:right:2:notifications@cinnamon.org:5', 'panel1:right:3:printers@cinnamon.org:6', 'panel1:right:4:removable-drives@cinnamon.org:7', 'panel1:right:5:keyboard@cinnamon.org:8', 'panel1:right:6:favorites@cinnamon.org:9', 'panel1:right:7:network@cinnamon.org:10', 'panel1:right:8:sound@cinnamon.org:11', 'panel1:right:9:power@cinnamon.org:12', 'panel1:right:10:calendar@cinnamon.org:13']
enabled-desklets=@as []
next-applet-id=14
panels-height=['1:33']
panels-resizable=['1:true']
startup-animation=false

[org/mate/desktop/a11y/applications]
screen-keyboard-enabled=false
screen-reader-enabled=false

[org/mate/desktop/a11y/mouse]
dwell-click-enabled=false
dwell-threshold=10
dwell-time=1.2
secondary-click-enabled=false
secondary-click-time=1.2

[org/mate/desktop/background]
picture-options='zoom'
picture-uri='file:///usr/share/backgrounds/armbian/armbian03-Dre0x-Minum-dark-3840x2160.jpg'
primary-color='#456789'
secondary-color='#FFFFFF'

[org/mate/desktop/applications/terminal]
exec='/usr/bin/terminator'

[org/mate/desktop/default-applications/terminal]
exec='/usr/bin/terminator'

[org/mate/desktop/interface]
clock-show-date=true
cursor-theme='whiteglass'
gtk-theme='Numix'
icon-theme='Numix'
scaling-factor=uint32 0
toolkit-accessibility=false

[org/mate/desktop/media-handling]
autorun-never=false

[org/mate/desktop/screensaver]
picture-options='zoom'
picture-uri='file:///usr/share/backgrounds/armbian-lightdm/armbian03-Dre0x-Minum-dark-3840x2160'
primary-color='#456789'
secondary-color='#FFFFFF'

[org/mate/desktop/wm/preferences]
num-workspaces=2
theme='Numix'

[org/mate/settings-daemon/peripherals/touchpad]
disable-while-typing=true
horiz-scroll-enabled=false
motion-acceleration=5.4820717131474108
motion-threshold=2
natural-scroll=false
scroll-method='two-finger-scrolling'
three-finger-click=2
two-finger-click=3

[org/mate/settings-daemon/plugins/power]
button-power='interactive'
critical-battery-action='hibernate'
idle-brightness=30
idle-dim-time=90
lid-close-ac-action='nothing'
lid-close-battery-action='nothing'
sleep-display-ac=600
sleep-display-battery=600
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org/mate/settings-daemon/plugins/xsettings]
buttons-have-icons=true
menus-have-icons=true

[org/mate/sounds]
login-enabled=false
logout-enabled=false
plug-enabled=false
switch-enabled=false
tile-enabled=false
unplug-enabled=false" >> $keys

echo "user-db:user
system-db:local" >> $profile

dconf update

#re-compile schemas
if [ -d /usr/share/glib-2.0/schemas ]; then glib-compile-schemas /usr/share/glib-2.0/schemas; fi
