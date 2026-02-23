#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
# runs inside chroot, userpatches/overlay/ is bind-mounted to /tmp/overlay

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

USERNAME=${USERNAME:-asius}
PASSWD=${PASSWD:-asius}
OPENPILOT_REPO=${OPENPILOT_REPO:-"https://github.com/asiusai/openpilot.git"}
OPENPILOT_BRANCH=${OPENPILOT_BRANCH:-"orangepi"}

Main() {
	[[ "$BOARD" != "orangepi5-ultra" ]] && return 0
	[[ "$RELEASE" != "noble" ]] && return 0

	echo ">>> Asius: Customizing Orange Pi 5 Ultra image"

	SetupUser
	SetupLocaleTimezone
	SetupDesktopAutologin
	SkipFirstboot
	ConfigureBootOverlays
	InstallMaliGPU
	CompileCameraOverlays
	InstallCameraPackages
	CreateMplaneSymlink
	SetupDataFilesystem
	SetupSSHPersistence
	SetupNetworkPersistence
	SetupPython
	SetupTmux
	CloneOpenpilot
	SetupBootLauncher
	SetupFirstBoot

	echo ">>> Asius: Customization complete"
}

SetupUser() {
	echo ">>> Setting up user: $USERNAME"

	useradd -G sudo -m -s /bin/bash $USERNAME
	echo "$USERNAME:$PASSWD" | chpasswd
	echo "root:$PASSWD" | chpasswd

	for grp in gpio gpu; do
		groupadd -f $grp
	done
	for grp in root video gpio adm gpu audio disk dialout systemd-journal netdev; do
		adduser $USERNAME $grp 2>/dev/null || true
	done

	echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
	touch /home/$USERNAME/.sudo_as_admin_successful
	chown $USERNAME:$USERNAME /home/$USERNAME/.sudo_as_admin_successful

	# realtime priority + nice limits for openpilot
	echo "$USERNAME - rtprio 100" >> /etc/security/limits.conf
	echo "$USERNAME - nice -10" >> /etc/security/limits.conf

	# TODO: remove soon, default SSH authorized keys
	mkdir -p /data/params/d
	curl -fsSL https://github.com/karelnagel.keys > /data/params/d/GithubSshKeys
	chown $USERNAME:$USERNAME /data/params/d/GithubSshKeys
}

SetupLocaleTimezone() {
	echo ">>> Configuring locale and timezone"

	locale-gen en_US.UTF-8 || true
	update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 || true

	ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
	echo "Etc/UTC" > /etc/timezone
	dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true

	sed -i 's|^DSHELL=.*|DSHELL=/bin/bash|' /etc/adduser.conf 2>/dev/null || true
}

SetupDesktopAutologin() {
	echo ">>> Configuring GDM autologin for $USERNAME"

	mkdir -p /etc/gdm3
	cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = $USERNAME
EOF

	# Armbian disables display managers during build, re-enable since we skip firstlogin
	if [[ -f /lib/systemd/system/gdm.service ]]; then
		ln -sf /lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service
	elif [[ -f /lib/systemd/system/gdm3.service ]]; then
		ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service
	fi
}

SkipFirstboot() {
	echo ">>> Skipping Armbian first-boot wizard"
	rm -f /root/.not_logged_in_yet
	chmod +x /etc/update-motd.d/* 2>/dev/null || true
}

ConfigureBootOverlays() {
	echo ">>> Configuring boot overlays"

	if [[ -f /boot/armbianEnv.txt ]]; then
		if grep -q '^overlays=' /boot/armbianEnv.txt; then
			sed -i 's/^overlays=.*/overlays=orangepi-5-ultra-cam0-imx415 orangepi-5-ultra-cam2-imx415/' /boot/armbianEnv.txt
		else
			echo 'overlays=orangepi-5-ultra-cam0-imx415 orangepi-5-ultra-cam2-imx415' >> /boot/armbianEnv.txt
		fi
	fi
}

InstallMaliGPU() {
	echo ">>> Installing proprietary Mali G610 GPU driver"

	export DEBIAN_FRONTEND=noninteractive

	add-apt-repository -y ppa:jjriek/panfork-mesa --no-update
	apt-get update -q

	apt-get install -y -q \
		mali-g610-firmware \
		libmali-g610-x11 \
		|| { echo "ERROR: Failed to install Mali GPU packages"; return 1; }

	# blacklist panthor so it doesn't race with mali_bifrost
	echo "blacklist panthor" > /etc/modprobe.d/blacklist-panthor.conf
	rm -f /etc/OpenCL/vendors/rusticl.icd
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

	add-apt-repository -y ppa:liujianfeng1994/rockchip-multimedia --no-update
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
	else
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

SetupDataFilesystem() {
	echo ">>> Setting up /data filesystem"

	mkdir -p /data
	chown $USERNAME:$USERNAME /data

	mkdir -p /data/openpilot /data/params/d /data/persist /data/media /data/ssh /data/tmp
	chown -R $USERNAME:$USERNAME /data/openpilot /data/params /data/persist /data/media /data/ssh /data/tmp

	ln -sf /data/openpilot /data/pythonpath

	mkdir -p /data/etc/ssh /data/etc/NetworkManager/system-connections
	chown root:root /data/etc
}

SetupSSHPersistence() {
	echo ">>> Setting up persistent SSH in /data"

	systemctl enable ssh 2>/dev/null || true

	# generate host keys in /data/etc/ssh/ on first boot
	mkdir -p /etc/systemd/system/ssh.service.d
	cat > /etc/systemd/system/ssh.service.d/override.conf << 'EOF'
[Service]
ExecStartPre=
ExecStartPre=/bin/bash -c 'mkdir -p /data/etc/ssh && if [ ! -f /data/etc/ssh/ssh_host_ed25519_key ]; then /usr/bin/ssh-keygen -A -f /data; fi'
ExecStartPre=/usr/sbin/sshd -t
EOF

	cat > /etc/ssh/sshd_config.d/asius.conf << 'EOF'
HostKey /data/etc/ssh/ssh_host_rsa_key
HostKey /data/etc/ssh/ssh_host_ecdsa_key
HostKey /data/etc/ssh/ssh_host_ed25519_key

AuthorizedKeysFile /data/params/d/GithubSshKeys %h/.ssh/authorized_keys

PasswordAuthentication yes
PermitRootLogin no
StrictModes no
AcceptEnv LANG LC_*
EOF

	cat > /etc/ssh/ssh_config.d/asius.conf << 'EOF'
Host *
    IdentityFile /data/ssh/id_ed25519
    IdentityFile /data/ssh/id_rsa
    UserKnownHostsFile /data/ssh/known_hosts
    StrictHostKeyChecking no
EOF
}

SetupNetworkPersistence() {
	echo ">>> Setting up network persistence in /data"

	cat > /usr/local/bin/asius-network-persist.sh << 'NETEOF'
#!/bin/bash
DATA_NM="/data/etc/NetworkManager/system-connections"
SYS_NM="/etc/NetworkManager/system-connections"
mkdir -p "$DATA_NM"
if [[ ! -L "$SYS_NM" ]]; then
    [[ -d "$SYS_NM" ]] && cp -a "$SYS_NM"/* "$DATA_NM/" 2>/dev/null || true
    rm -rf "$SYS_NM"
    ln -sf "$DATA_NM" "$SYS_NM"
fi
NETEOF
	chmod 755 /usr/local/bin/asius-network-persist.sh

	mkdir -p /etc/systemd/system/NetworkManager.service.d
	cat > /etc/systemd/system/NetworkManager.service.d/persist.conf << 'EOF'
[Service]
ExecStartPre=/usr/local/bin/asius-network-persist.sh
EOF
}

SetupPython() {
	echo ">>> Setting up Python + uv"

	export DEBIAN_FRONTEND=noninteractive

	apt-get install -y -q \
		python3 python3-dev python3-venv \
		build-essential cmake clang curl pkg-config git git-lfs \
		libssl-dev libffi-dev libsqlite3-dev zlib1g-dev libbz2-dev liblzma-dev \
		libzmq3-dev libczmq-dev libeigen3-dev libusb-1.0-0-dev libsystemd-dev \
		libdbus-1-dev libjpeg-dev ocl-icd-opencl-dev opencl-headers \
		libarchive-dev libcurl4-openssl-dev portaudio19-dev libportaudio2 \
		capnproto libcapnp-dev gcc-arm-none-eabi gettext \
		libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
		scons \
		|| echo "WARNING: Some build dependencies failed to install"

	curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

	# venv + pip install happens on first boot (asius-firstboot.service)
	# chroot can't compile native C extensions for aarch64

	cat > /etc/profile.d/asius-python.sh << 'EOF'
export PYTHONPATH="/data/pythonpath"
export UV_PYTHON_INSTALL_DIR="/usr/local/uv/python"
export UV_PYTHON_PREFERENCE=only-system
export UV_LINK_MODE=copy
[ -f /usr/local/venv/bin/activate ] && source /usr/local/venv/bin/activate
EOF

	cat >> /home/$USERNAME/.bashrc << 'EOF'

[ -d "/data/openpilot" ] && [ -n "$PS1" ] && cd /data/openpilot 2>/dev/null || true
EOF
	chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc
}

SetupTmux() {
	echo ">>> Setting up tmux configuration"

	apt-get install -y -q tmux || echo "WARNING: Failed to install tmux"

	cat > /home/$USERNAME/.tmux.conf << 'TMUXEOF'
unbind C-b
set -g prefix `
bind-key ` last-window
bind-key e send-prefix

set -g status-position bottom
set -g status-style bg=colour234,fg=colour137,dim
set -g status-left ''

set -g status-left-length 20
set -g history-limit 7200
set -g status-right '#[fg=colour230,bold]#(cat /data/params/d/DongleId 2>/dev/null | cut -c 1-16) #[fg=colour233,bg=colour239,bold] #(echo "scale=1; $(cat /sys/devices/virtual/thermal/thermal_zone0/temp)/1000" | bc)°C #[fg=colour233,bg=colour241,bold] %d/%m #[fg=colour233,bg=colour245,bold] %H:%M:%S '
set -g status-right-length 70
setw -g window-status-current-style fg=colour81,bg=colour238,bold
setw -g window-status-current-format ' #I#[fg=colour250]:#[fg=colour255]#W#[fg=colour50]#F '

setw -g window-status-style fg=colour138,bg=colour235
setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '

setw -g window-status-bell-style fg=colour255,bg=colour1,bold

set -g mouse off
TMUXEOF
	chown $USERNAME:$USERNAME /home/$USERNAME/.tmux.conf
}

CloneOpenpilot() {
	echo ">>> Cloning openpilot ($OPENPILOT_BRANCH branch) into /data/openpilot"

	apt-get install -y -q git git-lfs || { echo "ERROR: Failed to install git"; return 1; }

	git clone --branch=$OPENPILOT_BRANCH --depth=1 "$OPENPILOT_REPO" /data/openpilot
	chown -R $USERNAME:$USERNAME /data/openpilot

	su -c "cd /data/openpilot && git submodule update --init --depth=1" $USERNAME

	cat > /data/continue.sh << 'EOF'
#!/bin/bash
cd /data/openpilot
tmux kill-session -t comma 2>/dev/null
exec tmux new-session -d -s comma ./launch_openpilot.sh
EOF
	chmod 755 /data/continue.sh
	chown $USERNAME:$USERNAME /data/continue.sh

	echo "  OK: openpilot cloned and continue.sh written"
}

SetupBootLauncher() {
	echo ">>> Setting up openpilot boot launcher"

	cat > /usr/local/bin/asius-launcher.sh << 'LAUNCHEOF'
#!/bin/bash
source /etc/profile

CONTINUE="/data/continue.sh"

chown asius:asius /data
chown asius:asius /data/media 2>/dev/null || true

rm -rf /data/tmp
mkdir -p /data/tmp
chown asius:asius /data/tmp

# wait for Xwayland to be ready (needed for UI)
for i in $(seq 1 30); do
    ls /run/user/1000/.mutter-Xwaylandauth.* >/dev/null 2>&1 && break
    sleep 1
done

if [ -f "$CONTINUE" ]; then
    chmod +x "$CONTINUE"
    exec su -l asius -c "exec $CONTINUE"
fi

echo "asius-launcher: no /data/continue.sh found"
LAUNCHEOF
	chmod 755 /usr/local/bin/asius-launcher.sh

	cat > /etc/systemd/system/asius.service << 'EOF'
[Unit]
Description=Asius openpilot launcher
After=network.target gdm.service asius-firstboot.service rkaiq_3A.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/asius-launcher.sh
ExecStop=/usr/bin/tmux kill-session -t comma
User=root
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable asius.service 2>/dev/null || true
}

SetupFirstBoot() {
	echo ">>> Setting up first-boot initialization"

	cat > /usr/local/bin/asius-firstboot.sh << 'FBEOF'
#!/bin/bash
MARKER="/data/.asius_initialized"
[ -f "$MARKER" ] && exit 0

echo "asius-firstboot: initializing /data"

mkdir -p /data/openpilot /data/params/d /data/persist /data/media /data/ssh /data/etc/ssh /data/tmp

if [ ! -f /data/ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f /data/ssh/id_ed25519 -N "" -C "asius@$(hostname)"
    chown asius:asius /data/ssh/id_ed25519 /data/ssh/id_ed25519.pub
fi

echo -n 1 > /data/params/d/SshEnabled

chown -R asius:asius /data/openpilot /data/params /data/persist /data/media /data/ssh /data/tmp
chown root:root /data/etc /data/etc/ssh
ln -sf /data/openpilot /data/pythonpath

# create venv + install openpilot python deps (must run on real hardware, not cross-arch chroot)
if [ ! -f /usr/local/venv/bin/python3 ]; then
    echo "asius-firstboot: creating python venv"
    uv venv /usr/local/venv --seed --python-preference only-system --python=3.12
    chown -R asius:asius /usr/local/venv
fi

if [ -f /data/openpilot/pyproject.toml ]; then
    echo "asius-firstboot: installing openpilot python dependencies"
    source /usr/local/venv/bin/activate
    cd /data/openpilot
    MAKEFLAGS="-j$(nproc)" UV_NO_CACHE=1 UV_PROJECT_ENVIRONMENT=/usr/local/venv \
        uv pip install -e ".[dev]" --compile-bytecode \
        || echo "WARNING: some python deps failed"
fi

touch "$MARKER"
chown asius:asius "$MARKER"

echo "asius-firstboot: done, SSH pubkey: $(cat /data/ssh/id_ed25519.pub 2>/dev/null)"
FBEOF
	chmod 755 /usr/local/bin/asius-firstboot.sh

	cat > /etc/systemd/system/asius-firstboot.service << 'EOF'
[Unit]
Description=Asius first-boot initialization
After=local-fs.target
Before=ssh.service asius.service
ConditionPathExists=!/data/.asius_initialized

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asius-firstboot.sh
RemainAfterExit=yes
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable asius-firstboot.service 2>/dev/null || true
}

Main "$@"
