#!/bin/bash
set -e

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4
ARCH=$5

Main() {
	if [ "$BOARD" != "orangepi3b" ]; then
		return 0
	fi

	install -d /usr/local/bin /usr/local/sbin /etc/udev/rules.d /etc/modprobe.d /etc/profile.d /etc/systemd/system
	getent group render >/dev/null || groupadd -r render

	cat >/etc/modprobe.d/blacklist-opi3b-vendor-mali.conf <<'EOF'
# Keep the RK3566 GPU on the upstream Panfrost DRM driver. The vendor Mali
# modules can probe first on some vendor kernels and log avoidable failures.
blacklist mali
blacklist mali_kbase
blacklist midgard_kbase
blacklist bifrost
EOF

	cat >/etc/udev/rules.d/70-rockchip-accelerators.rules <<'EOF'
KERNEL=="rknpu", GROUP="video", MODE="0660", TAG+="uaccess"
KERNEL=="mali0", GROUP="video", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0660", TAG+="uaccess"
EOF

	cat >/usr/local/sbin/op3b-hw-check <<'EOF'
#!/bin/sh
set -u

ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

printf 'Board: %s\n' "$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Memory: %s\n' "$(awk '/MemTotal/ { printf "%.1f GiB", $2 / 1024 / 1024 }' /proc/meminfo)"

[ -e /dev/rknpu ] && ok '/dev/rknpu present' || warn '/dev/rknpu missing; check vendor kernel, DT, and dmesg'
[ -e /dev/dri/renderD128 ] && ok 'DRM render node present' || warn 'DRM render node missing'
[ -d /sys/class/net/end0 ] || [ -d /sys/class/net/eth0 ] && ok 'Ethernet interface present' || warn 'Ethernet interface not found'
iw dev 2>/dev/null | grep -q Interface && ok 'Wi-Fi interface present' || warn 'Wi-Fi interface not found'
command -v bluetoothctl >/dev/null 2>&1 && bluetoothctl list 2>/dev/null | grep -q Controller && ok 'Bluetooth controller present' || warn 'Bluetooth controller not found'
command -v nvme >/dev/null 2>&1 && nvme list 2>/dev/null | grep -q /dev/nvme && ok 'NVMe device present' || warn 'No NVMe device detected'

printf '\nPCIe:\n'
lspci 2>/dev/null || true
printf '\nUSB:\n'
lsusb 2>/dev/null || true
printf '\nNetwork:\n'
ip -br link 2>/dev/null || true

printf '\nDRM devices:\n'
for x in /sys/class/drm/card* /sys/class/drm/renderD*; do
	[ -e "$x" ] || continue
	printf '=== %s ===\n' "$x"
	readlink -f "$x/device" 2>/dev/null || true
	grep -E 'DRIVER|OF_NAME|OF_FULLNAME' "$x/device/uevent" 2>/dev/null || true
done

printf '\nDSI/display log hints:\n'
dmesg | grep -iE 'dsi|rasp|touch|ft54|panel|backlight|drm|rknpu|panfrost|mali' | tail -120 || true
EOF
	chmod 755 /usr/local/sbin/op3b-hw-check

	cat >/usr/local/sbin/op3b-dsi-status <<'EOF'
#!/bin/sh
set -u

env_file="/boot/armbianEnv.txt"

echo "armbianEnv:"
grep -E '^(fdtfile|overlay_prefix|overlays|user_overlays|extraargs|verbosity|console)=' "$env_file" 2>/dev/null || true
echo

echo "Installed user overlays:"
ls -1 /boot/overlay-user/*.dtbo 2>/dev/null | sed 's#.*/##; s#\.dtbo$##' || true
echo

echo "DRM connectors:"
for status in /sys/class/drm/card*-*/status; do
	[ -e "$status" ] || continue
	printf '%s: ' "${status%/status}"
	cat "$status"
done
echo

echo "Deferred devices:"
cat /sys/kernel/debug/devices_deferred 2>/dev/null || true
echo

echo "Recent DSI/display log:"
dmesg | grep -iE 'dsi|rasp|touch|ft54|panel|backlight|drm|vop|hdmi' | tail -160 || true
EOF
	chmod 755 /usr/local/sbin/op3b-dsi-status

cat >/usr/local/sbin/op3b-dsi-try <<'EOF'
#!/bin/sh
set -eu

profile="${1:-vp0}"
dtb_mode="${2:-default}"
env_file="/boot/armbianEnv.txt"
state_dir="/var/lib/op3b-dsi"
backup_file="${state_dir}/armbianEnv.before-dsi"

set_env_key() {
	key="$1"
	value="$2"
	if grep -q "^${key}=" "$env_file"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
	else
		printf '%s=%s\n' "$key" "$value" >> "$env_file"
	fi
}

append_extraargs_once() {
	for arg in "$@"; do
		if grep -q '^extraargs=' "$env_file"; then
			grep -q "^extraargs=.*\\b${arg}\\b" "$env_file" || sed -i "s|^extraargs=.*|& ${arg}|" "$env_file"
		else
			printf 'extraargs=%s\n' "$arg" >> "$env_file"
		fi
	done
}

case "$profile" in
	debug-only)
		overlay_name=""
		debug_level="safe"
		;;
	early-debug)
		overlay_name=""
		debug_level="early"
		;;
	noop)
		overlay_name="orangepi3b-debug-noop"
		debug_level="safe"
		;;
	i2c-only)
		overlay_name="orangepi3b-waveshare-5inch-dsi-i2c-only"
		debug_level="safe"
		;;
	host-only)
		overlay_name="orangepi3b-waveshare-5inch-dsi-host-only"
		debug_level="safe"
		;;
	panel-no-touch)
		overlay_name="orangepi3b-waveshare-5inch-dsi-panel-no-touch"
		debug_level="safe"
		;;
		panel)
			overlay_name="orangepi3b-waveshare-5inch-dsi-panel"
			debug_level="safe"
			;;
		vp0)
			overlay_name="orangepi3b-waveshare-5inch-dsi-vp0"
			debug_level="safe"
		;;
	vp1)
		overlay_name="orangepi3b-waveshare-5inch-dsi-vp1"
		debug_level="safe"
		;;
	vp0-only)
		overlay_name="orangepi3b-waveshare-5inch-dsi-vp0-only"
		debug_level="safe"
		;;
		*)
			echo "Usage: op3b-dsi-try debug-only|early-debug|noop|i2c-only|host-only|panel-no-touch|panel|vp0|vp1|vp0-only [default|defencedog]"
			exit 2
			;;
esac

if [ -n "$overlay_name" ]; then
	overlay_file="/boot/overlay-user/${overlay_name}.dtbo"
	if [ ! -f "$overlay_file" ]; then
		echo "Missing $overlay_file"
		exit 1
	fi
fi

install -d "$state_dir"
cp "$env_file" "$backup_file"
rm -f "${state_dir}/confirmed"

set_env_key user_overlays "$overlay_name"
set_env_key verbosity 7
set_env_key console both
set_env_key bootlogo false
set_env_key show_bootargs true
append_extraargs_once \
	ignore_loglevel \
	loglevel=8 \
	printk.time=1

if [ "$debug_level" = "early" ]; then
	set_env_key earlycon on
	append_extraargs_once \
		initcall_debug \
		earlyprintk \
		keep_bootcon \
		no_console_suspend \
		earlycon=uart8250,mmio32,0xfe660000,1500000n8
else
	set_env_key earlycon off
fi

case "$dtb_mode" in
	default)
		sed -i 's|^fdtfile=.*|fdtfile=rockchip/rk3566-orangepi-3b-v2.1.dtb|' "$env_file"
		;;
	defencedog)
		if [ ! -f /boot/dtb/rockchip/rk3566-orangepi-3b-v2.1-defencedog-6.1.75.dtb ]; then
			echo "Missing alternate defencedog DTB in /boot/dtb/rockchip"
			exit 1
		fi
		sed -i 's|^fdtfile=.*|fdtfile=rockchip/rk3566-orangepi-3b-v2.1-defencedog-6.1.75.dtb|' "$env_file"
		;;
		*)
			echo "Usage: op3b-dsi-try debug-only|early-debug|noop|i2c-only|host-only|panel-no-touch|panel|vp0|vp1|vp0-only [default|defencedog]"
			exit 2
			;;
esac

systemctl enable op3b-dsi-rollback.service >/dev/null 2>&1 || true
touch "${state_dir}/pending"

if [ -n "$overlay_name" ]; then
	echo "Prepared one-shot DSI test: ${overlay_name}, DTB mode: ${dtb_mode}"
else
	echo "Prepared one-shot DSI debug boot with no overlay, DTB mode: ${dtb_mode}"
fi
echo "Reboot now. If Linux reaches multi-user and you do not run op3b-dsi-confirm, the next boot will revert to the saved HDMI/default config."
echo "DSI test boot enables verbose normal kernel logging. early-debug is separate because earlycon can break this boot path."
	echo "Recommended order: debug-only, noop, i2c-only, host-only, panel-no-touch, panel, then vp0/vp1. Use early-debug only if the safe path boots but gives too little UART output."
EOF
	chmod 755 /usr/local/sbin/op3b-dsi-try

	cat >/usr/local/sbin/op3b-dsi-disable <<'EOF'
#!/bin/sh
set -eu

env_file="/boot/armbianEnv.txt"
tmp_file="${env_file}.tmp"
state_dir="/var/lib/op3b-dsi"
backup_file="${state_dir}/armbianEnv.before-dsi"

if [ ! -f "$env_file" ]; then
	echo "Missing $env_file"
	exit 1
fi

if [ -f "$backup_file" ]; then
	cp "$backup_file" "$env_file"
else
	grep -v -E '^user_overlays=orangepi3b-waveshare-5inch-dsi' "$env_file" > "$tmp_file" || true
	cat "$tmp_file" > "$env_file"
	rm -f "$tmp_file"
	sed -i 's|^fdtfile=.*|fdtfile=rockchip/rk3566-orangepi-3b-v2.1.dtb|' "$env_file"
fi

rm -f "${state_dir}/pending" "${state_dir}/confirmed"

echo "DSI overlay disabled for next boot."
echo "Reboot to return to HDMI/default display routing."
EOF
	chmod 755 /usr/local/sbin/op3b-dsi-disable

	cat >/usr/local/sbin/op3b-dsi-confirm <<'EOF'
#!/bin/sh
set -eu

state_dir="/var/lib/op3b-dsi"
install -d "$state_dir"
touch "${state_dir}/confirmed"
rm -f "${state_dir}/pending"
systemctl disable op3b-dsi-rollback.service >/dev/null 2>&1 || true
echo "Current DSI boot config confirmed. Automatic rollback disabled."
EOF
	chmod 755 /usr/local/sbin/op3b-dsi-confirm

	cat >/usr/local/sbin/op3b-dsi-rollback <<'EOF'
#!/bin/sh
set -eu

state_dir="/var/lib/op3b-dsi"
env_file="/boot/armbianEnv.txt"
backup_file="${state_dir}/armbianEnv.before-dsi"

[ -f "${state_dir}/pending" ] || exit 0

# Give SSH/display users a window to run op3b-dsi-confirm.
sleep 180

[ ! -f "${state_dir}/confirmed" ] || exit 0
[ -f "$backup_file" ] || exit 0

cp "$backup_file" "$env_file"
rm -f "${state_dir}/pending"
systemctl disable op3b-dsi-rollback.service >/dev/null 2>&1 || true
logger -t op3b-dsi-rollback "Restored pre-DSI /boot/armbianEnv.txt for next boot"
EOF
	chmod 755 /usr/local/sbin/op3b-dsi-rollback

	cat >/etc/systemd/system/op3b-dsi-rollback.service <<'EOF'
[Unit]
Description=Rollback one-shot Orange Pi 3B DSI test config for next boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/op3b-dsi-rollback

[Install]
WantedBy=multi-user.target
EOF

	ln -sf /usr/local/sbin/op3b-dsi-try /usr/local/sbin/op3b-enable-dsi
	ln -sf /usr/local/sbin/op3b-dsi-disable /usr/local/sbin/op3b-disable-dsi

	cat >/etc/profile.d/op3b-tools.sh <<'EOF'
alias op3b-hw-check='/usr/local/sbin/op3b-hw-check'
alias op3b-dsi-status='/usr/local/sbin/op3b-dsi-status'
alias op3b-dsi-try='/usr/local/sbin/op3b-dsi-try'
alias op3b-dsi-disable='/usr/local/sbin/op3b-dsi-disable'
alias op3b-dsi-confirm='/usr/local/sbin/op3b-dsi-confirm'
alias op3b-enable-dsi='/usr/local/sbin/op3b-enable-dsi'
alias op3b-disable-dsi='/usr/local/sbin/op3b-disable-dsi'
EOF

	if [ "${OPI3B_TOUCH_DESKTOP_TWEAKS:-no}" = "yes" ]; then
		install -d /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
		install -d /etc/skel/.config/autostart
		install -d /etc/skel/.config/onboard
		install -d /etc/X11/xorg.conf.d
		install -d /etc/lightdm/lightdm.conf.d

		cat >/etc/X11/xorg.conf.d/20-op3b-modesetting.conf <<'EOF'
Section "Device"
    Identifier "OPi3B Rockchip Display"
    Driver "modesetting"
    Option "SWCursor" "true"
    Option "PageFlip" "false"
EndSection
EOF

		cat >/etc/X11/xorg.conf.d/40-opi3b-ft5426-touch.conf <<'EOF'
Section "InputClass"
    Identifier "Orange Pi 3B DSI FT5426 touchscreen"
    MatchProduct "fts_ts"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "1 0 0 0 1 0"
EndSection
EOF

		cat >/usr/local/bin/op3b-touch-fix <<'EOF'
#!/bin/sh
set -eu

mode="${1:-normal}"
display="${DISPLAY:-:0}"
export DISPLAY="$display"

if [ -z "${XAUTHORITY:-}" ]; then
	for candidate in \
		"/var/run/lightdm/root/${display}" \
		"/run/lightdm/root/${display}" \
		"$HOME/.Xauthority" \
		"/home/${SUDO_USER:-}/.Xauthority" \
		"/home/$(logname 2>/dev/null || true)/.Xauthority" \
		/var/lib/lightdm/.Xauthority
	do
		[ -n "$candidate" ] && [ -e "$candidate" ] && export XAUTHORITY="$candidate" && break
	done
fi

for _ in $(seq 1 20); do
	command -v xinput >/dev/null 2>&1 && command -v xrandr >/dev/null 2>&1 && xinput list >/dev/null 2>&1 && break
	sleep 1
done

touch_id="$(xinput list 2>/dev/null | sed -n 's/.*fts_ts.*id=\([0-9][0-9]*\).*/\1/p' | head -1)"
if [ -z "$touch_id" ]; then
	echo "fts_ts touch device not found in xinput"
	exit 1
fi

output="$(
	xrandr --query 2>/dev/null |
		awk '/ connected/{print $1}' |
		awk 'BEGIN{best=""} /^DSI/{print; exit} /^eDP|^LVDS/{if(best=="") best=$0} /^HDMI/{if(best=="") best=$0} END{if(best!="") print best}' |
		head -1
)"
if [ -z "$output" ]; then
	echo "No connected xrandr output found"
	exit 1
fi

case "$mode" in
	normal) matrix="1 0 0 0 1 0 0 0 1" ;;
	invert-x) matrix="-1 0 1 0 1 0 0 0 1" ;;
	invert-y) matrix="1 0 0 0 -1 1 0 0 1" ;;
	rotate-180) matrix="-1 0 1 0 -1 1 0 0 1" ;;
	swap) matrix="0 1 0 1 0 0 0 0 1" ;;
	rotate-cw) matrix="0 -1 1 1 0 0 0 0 1" ;;
	rotate-ccw) matrix="0 1 0 -1 0 1 0 0 1" ;;
	*)
		echo "Usage: op3b-touch-fix [normal|invert-x|invert-y|rotate-180|swap|rotate-cw|rotate-ccw]"
		exit 2
		;;
esac

xinput map-to-output "$touch_id" "$output" 2>/dev/null || true
prop="$(xinput list-props "$touch_id" | awk -F'[()]' '/Coordinate Transformation Matrix/{print $2; exit}')"
if [ -n "$prop" ]; then
	xinput set-prop "$touch_id" "$prop" $matrix
fi

echo "Mapped fts_ts id=$touch_id to output=$output with mode=$mode"
EOF
		chmod 755 /usr/local/bin/op3b-touch-fix

		ln -sf /usr/local/bin/op3b-touch-fix /usr/local/bin/op3b-touch-map

		cat >/usr/local/sbin/op3b-touch-display-setup <<'EOF'
#!/bin/sh
set -eu

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"

/usr/local/bin/op3b-touch-fix normal || true
EOF
		chmod 755 /usr/local/sbin/op3b-touch-display-setup

		cat >/etc/lightdm/lightdm.conf.d/99-op3b-touch.conf <<'EOF'
[Seat:*]
display-setup-script=/usr/local/sbin/op3b-touch-display-setup
EOF

		cat >/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="110"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 11"/>
    <property name="ToolbarStyle" type="string" value="icons"/>
    <property name="CursorThemeSize" type="int" value="28"/>
  </property>
</channel>
EOF

		cat >/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default-xhdpi"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="easy_click" type="string" value="Super"/>
    <property name="focus_delay" type="int" value="150"/>
  </property>
</channel>
EOF

		cat >/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="40"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist"/>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="pulseaudio"/>
    <property name="plugin-6" type="string" value="clock"/>
  </property>
</channel>
EOF

		cat >/etc/skel/.config/autostart/onboard.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Onboard
Exec=onboard --not-show-in=GNOME,KDE
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF

		cat >/etc/skel/.config/autostart/op3b-touch-map.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=OPi3B Touch Map
Exec=/usr/local/bin/op3b-touch-map normal
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF

		cat >/etc/skel/.config/onboard/onboard.conf <<'EOF'
[main]
layout=Phone
theme=Nightshade
show-status-icon=true
start-minimized=true
auto-show=true
EOF
	fi
}

Main
