#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script
# It runs inside chroot environment
# userpatches/overlay/ on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

USERNAME=asius
PASSWD=asius

Main() {
	[[ "$BOARD" != "orangepi5-ultra" ]] && return 0
	[[ "$RELEASE" != "noble" ]] && return 0

	echo ">>> Asius: Customizing Orange Pi 5 Ultra image"

	SetupUser
	SetupLocaleTimezone
	SetupSSH
	SetupDesktopAutologin
	SkipFirstboot
	ConfigureBootOverlays
	CompileCameraOverlays
	InstallCameraPackages
	CreateMplaneSymlink
	InstallCamScript

	echo ">>> Asius: Customization complete"
}

SetupUser() {
	echo ">>> Setting up user: $USERNAME"

	# create user with sudo group (matches agnos comma user setup)
	useradd -G sudo -m -s /bin/bash $USERNAME
	echo "$USERNAME:$PASSWD" | chpasswd
	echo "root:$PASSWD" | chpasswd

	# hardware access groups (same as agnos)
	for grp in gpio gpu; do
		groupadd -f $grp
	done
	for grp in root video gpio adm gpu audio disk dialout systemd-journal netdev; do
		adduser $USERNAME $grp 2>/dev/null || true
	done

	# passwordless sudo
	echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

	# suppress "To run a command as administrator..." nag
	touch /home/$USERNAME/.sudo_as_admin_successful

	# realtime priority + nice limits (needed for openpilot)
	echo "$USERNAME - rtprio 100" >> /etc/security/limits.conf
	echo "$USERNAME - nice -10" >> /etc/security/limits.conf

	chown $USERNAME:$USERNAME /home/$USERNAME/.sudo_as_admin_successful
}

SetupLocaleTimezone() {
	echo ">>> Configuring locale and timezone"

	# generate and set locale
	locale-gen en_US.UTF-8 || true
	update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 || true

	# set timezone
	ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
	echo "Etc/UTC" > /etc/timezone
	dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true

	# set default shell to bash
	sed -i 's|^DSHELL=.*|DSHELL=/bin/bash|' /etc/adduser.conf 2>/dev/null || true
}

SetupSSH() {
	echo ">>> Configuring SSH"

	# password auth is on by default in Armbian — users SSH in with asius/asius
	# once connected they can add their own keys to ~/.ssh/authorized_keys

	# enable SSH on boot
	systemctl enable ssh 2>/dev/null || true

	# re-enable passing locale via ssh
	sed -e '/^#AcceptEnv LANG/ s/^#//' -i /etc/ssh/sshd_config 2>/dev/null || true
}

SetupDesktopAutologin() {
	echo ">>> Configuring GDM autologin for $USERNAME"

	mkdir -p /etc/gdm3
	cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $USERNAME
EOF

	# Armbian disables display managers during build (rootfs-desktop.sh)
	# and the firstlogin wizard re-enables them — since we skip firstlogin, do it here
	# service is called gdm.service on Ubuntu Noble (not gdm3)
	if [[ -f /lib/systemd/system/gdm.service ]]; then
		ln -sf /lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service
	elif [[ -f /lib/systemd/system/gdm3.service ]]; then
		ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service
	fi
}

SkipFirstboot() {
	echo ">>> Skipping Armbian first-boot wizard"

	# remove the trigger file so armbian-firstlogin never runs
	rm -f /root/.not_logged_in_yet

	# enable motd scripts (normally done by firstlogin)
	chmod +x /etc/update-motd.d/* 2>/dev/null || true
}

ConfigureBootOverlays() {
	echo ">>> Configuring boot overlays"

	# Panthor GPU for Mesa hw accel + IMX415 on CAM0
	# Only enable 1 camera overlay — multiple create extra media devices that break rkaiq 3A
	if [[ -f /boot/armbianEnv.txt ]]; then
		if grep -q '^overlays=' /boot/armbianEnv.txt; then
			sed -i 's/^overlays=.*/overlays=panthor-gpu orangepi-5-ultra-cam0-imx415/' /boot/armbianEnv.txt
		else
			echo 'overlays=panthor-gpu orangepi-5-ultra-cam0-imx415' >> /boot/armbianEnv.txt
		fi
	fi
}

CompileCameraOverlays() {
	echo ">>> Compiling camera DT overlays"

	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y -q device-tree-compiler cpp || {
		echo "WARNING: Failed to install dtc/cpp, skipping overlay compilation"
		return 0
	}

	local KDIR
	KDIR=$(ls -d /usr/src/linux-headers-*-vendor-rk35xx 2>/dev/null | head -1)
	if [[ -z "$KDIR" ]]; then
		echo "WARNING: No kernel headers found, skipping overlay compilation"
		return 0
	fi

	local OVERLAY_DIR="/boot/dtb/rockchip/overlay"
	mkdir -p "$OVERLAY_DIR"

	local failed=0
	for dts in /tmp/overlay/*.dts; do
		[[ ! -f "$dts" ]] && continue
		local name
		name=$(basename "$dts" .dts)
		echo "  Compiling $name.dtbo"

		cpp -nostdinc -I "$KDIR/include" -undef -x assembler-with-cpp "$dts" 2>/dev/null | \
			dtc -@ -I dts -O dtb -o "$OVERLAY_DIR/$name.dtbo" 2>/dev/null

		if [[ $? -eq 0 && -f "$OVERLAY_DIR/$name.dtbo" ]]; then
			echo "  OK: $name.dtbo"
		else
			echo "  FAILED: $name.dtbo"
			failed=$((failed + 1))
		fi
	done

	echo ">>> Camera overlays compiled ($failed failures)"
}

InstallCameraPackages() {
	echo ">>> Installing camera packages"

	export DEBIAN_FRONTEND=noninteractive

	# rkmpp-patched ffmpeg + v4l-utils with multiplanar support
	add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia --no-update
	# camera-engine-rkaiq for ISP 3A (auto-exposure, AWB)
	add-apt-repository -y ppa:jjriek/rockchip-multimedia --no-update
	apt-get update -q

	apt-get install -y -q \
		ffmpeg \
		v4l-utils \
		libv4l-rkmpp \
		camera-engine-rkaiq-rk3588 \
		|| echo "WARNING: Some camera packages failed to install"
}

CreateMplaneSymlink() {
	echo ">>> Creating libv4l-mplane symlink"

	local PLUGIN="/usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-mplane.so"
	local LINK="/usr/lib/aarch64-linux-gnu/libv4l-mplane.so"

	if [[ -f "$PLUGIN" ]]; then
		ln -sf "$PLUGIN" "$LINK"
		ldconfig
		echo "  OK: $LINK -> $PLUGIN"
	else
		echo "  SKIP: $PLUGIN not found (will be created after package install)"
		cat > /etc/profile.d/mplane-fixup.sh << 'FIXEOF'
#!/bin/bash
if [[ -f /usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-mplane.so ]] && \
   [[ ! -L /usr/lib/aarch64-linux-gnu/libv4l-mplane.so ]]; then
	sudo ln -sf /usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-mplane.so \
		/usr/lib/aarch64-linux-gnu/libv4l-mplane.so
	sudo ldconfig
fi
FIXEOF
		chmod 644 /etc/profile.d/mplane-fixup.sh
	fi
}

InstallCamScript() {
	echo ">>> Installing ~/cam.sh"

	cat > /home/$USERNAME/cam.sh << 'CAMEOF'
#!/bin/bash
CAM=${CAM:-/dev/video11}
W=${W:-1920}
H=${H:-1080}
v4l2-ctl -d $CAM --set-fmt-video=width=$W,height=$H,pixelformat=NV12
ffplay -f v4l2 -video_size ${W}x${H} -input_format nv12 $CAM
CAMEOF
	chmod 755 /home/$USERNAME/cam.sh
	chown $USERNAME:$USERNAME /home/$USERNAME/cam.sh
}

Main "$@"
