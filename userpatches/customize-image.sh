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
	SkipFirstboot
	SetupI2CPermissions
	SetupSPIPermissions
	FixRealtimeScheduling
	ConfigureBootOverlays
	AddPPAs
	InstallMaliGPU
	SetupRKNPU
	CompileCameraOverlays
	InstallCameraPackages
	CreateMplaneSymlink
	SetupDataFilesystem
	SetupSSHPersistence
	SetupNetworkPersistence
	SetupPowerLimits
	SetupPersistentJournal
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

	for grp in gpio gpu i2c; do
		groupadd -f $grp
	done
	for grp in root video gpio adm gpu audio disk dialout systemd-journal netdev i2c input; do
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

SkipFirstboot() {
	echo ">>> Skipping Armbian first-boot wizard"
	rm -f /root/.not_logged_in_yet
	chmod +x /etc/update-motd.d/* 2>/dev/null || true
}

SetupI2CPermissions() {
	echo ">>> Setting up I2C device permissions"

	# udev rule so /dev/i2c-* is accessible to i2c group without sudo
	echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' > /etc/udev/rules.d/99-i2c.rules

	# udev rule so /dev/mpp_service is accessible without sudo (needed for rkmpp hardware encoding)
	echo 'KERNEL=="mpp_service", MODE="0666"' > /etc/udev/rules.d/99-mpp.rules
}

SetupSPIPermissions() {
	echo ">>> Setting up SPI device permissions"

	# udev rule so /dev/spidev* is accessible without sudo (needed for panda SPI communication)
	echo 'SUBSYSTEM=="spidev", MODE="0666"' > /etc/udev/rules.d/99-spidev.rules
}

FixRealtimeScheduling() {
	echo ">>> Fixing RT scheduling for rkaiq 3A engine"

	# Armbian enables CONFIG_RT_GROUP_SCHED=y in the kernel, which combined with
	# cgroup v2 makes sched_setscheduler(SCHED_RR) return EPERM even for root.
	# rkaiq's stats polling thread calls sched_setscheduler(SCHED_RR, prio=20),
	# gets EPERM, and exit(0)s -- killing 3A auto-exposure and leaving camera dark.
	# Setting sched_rt_runtime_us=-1 disables the RT bandwidth throttling,
	# allowing SCHED_RR to work. This matches ubuntu-rockchip's behavior
	# (which simply doesn't set CONFIG_RT_GROUP_SCHED).
	cat > /etc/sysctl.d/99-rkaiq-rt-scheduling.conf << 'EOF'
# Allow SCHED_RR/SCHED_FIFO for rkaiq 3A stats thread
# Without this, CONFIG_RT_GROUP_SCHED + cgroup v2 blocks RT scheduling
kernel.sched_rt_runtime_us = -1
EOF

	echo "  OK: sysctl kernel.sched_rt_runtime_us=-1 will persist across reboots"
}

ConfigureBootOverlays() {
	echo ">>> Configuring boot overlays"

	if [[ -f /boot/armbianEnv.txt ]]; then
		if grep -q '^overlays=' /boot/armbianEnv.txt; then
			sed -i 's/^overlays=.*/overlays=orangepi-5-ultra-cam0-imx415 orangepi-5-ultra-cam1-imx415 orangepi-5-ultra-cam2-imx415 rk3588-i2c2-m0 rk3588-spi0-m2-cs0-spidev/' /boot/armbianEnv.txt
		else
			echo 'overlays=orangepi-5-ultra-cam0-imx415 orangepi-5-ultra-cam1-imx415 orangepi-5-ultra-cam2-imx415 rk3588-i2c2-m0 rk3588-spi0-m2-cs0-spidev' >> /boot/armbianEnv.txt
		fi
	fi
}

AddPPAs() {
	echo ">>> Adding third-party PPAs"

	# Write PPA sources directly (add-apt-repository requires software-properties-common which isn't in minimal chroot)
	mkdir -p /etc/apt/keyrings

	# jjriek (panfork-mesa + rockchip-multimedia) - key 3CC0D9D1F3F0354B50D24F51F02122ECF25FB4D7
	curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3CC0D9D1F3F0354B50D24F51F02122ECF25FB4D7" | \
		gpg --dearmor -o /etc/apt/keyrings/jjriek.gpg 2>/dev/null
	echo "deb [signed-by=/etc/apt/keyrings/jjriek.gpg] https://ppa.launchpadcontent.net/jjriek/panfork-mesa/ubuntu noble main" \
		> /etc/apt/sources.list.d/jjriek-panfork-mesa.list
	echo "deb [signed-by=/etc/apt/keyrings/jjriek.gpg] https://ppa.launchpadcontent.net/jjriek/rockchip-multimedia/ubuntu noble main" \
		> /etc/apt/sources.list.d/jjriek-rockchip-multimedia.list

	# liujianfeng1994/rockchip-multimedia - key 0B2F0747E3BD546820A639B68065BE1FC67AABDE
	curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0B2F0747E3BD546820A639B68065BE1FC67AABDE" | \
		gpg --dearmor -o /etc/apt/keyrings/liujianfeng1994.gpg 2>/dev/null
	echo "deb [signed-by=/etc/apt/keyrings/liujianfeng1994.gpg] https://ppa.launchpadcontent.net/liujianfeng1994/rockchip-multimedia/ubuntu noble main" \
		> /etc/apt/sources.list.d/liujianfeng1994-rockchip-multimedia.list

	apt-get update -q
}

InstallMaliGPU() {
	echo ">>> Installing proprietary Mali G610 GPU driver"

	export DEBIAN_FRONTEND=noninteractive

	apt-get install -y -q \
		mali-g610-firmware \
		libmali-g610-x11 \
		|| { echo "ERROR: Failed to install Mali GPU packages"; return 1; }

	# GPU rendering libs for DRM/GBM/EGL (raylib PLATFORM_COMMA)
	apt-get install -y -q \
		libgles2-mesa-dev libegl1-mesa-dev libgbm-dev libdrm-dev \
		libwayland-dev \
		|| echo "WARNING: Some GPU dev packages failed to install"

	# blacklist panthor so it doesn't race with mali_bifrost
	echo "blacklist panthor" > /etc/modprobe.d/blacklist-panthor.conf
	rm -f /etc/OpenCL/vendors/rusticl.icd
}

SetupRKNPU() {
	echo ">>> Setting up RKNPU2 runtime + NPU performance tuning"

	# The kernel RKNPU driver is built-in (CONFIG_ROCKCHIP_RKNPU=y, v0.9.8).
	# Building it as a module (=m) fails due to unexported iommu symbols.
	#
	# For CPU fallback on unsupported ops (needed for fp16 attention accuracy),
	# we use the updated librknnrt.so from airockchip which supports the
	# RKNN_FLAG_EXECUTE_FALLBACK_PRIOR_DEVICE_GPU flag. This lets the runtime
	# handle mixed NPU+CPU execution without needing a newer kernel driver.
	#
	# See: logs/2026-03-05-model_benchmarks.md
	# See: logs/2026-03-06-bukapilot-rk3588-analysis.md (rknnmodel.cc)

	local RKNPU2_VERSION="2.3.0"
	local RKNPU2_URL="https://github.com/airockchip/rknn-toolkit2/raw/v${RKNPU2_VERSION}/rknpu2"

	# Install RKNN runtime library (librknnrt.so) - needed for NPU inference
	local RKNN_LIB_DIR="/usr/lib"
	echo "  Installing librknnrt.so from airockchip/rknn-toolkit2"

	curl -fsSL "${RKNPU2_URL}/runtime/Linux/librknn_api/aarch64/librknnrt.so" \
		-o "${RKNN_LIB_DIR}/librknnrt.so" || {
		echo "WARNING: Failed to download librknnrt.so, trying alternative URL"
		curl -fsSL "https://github.com/airockchip/rknn-toolkit2/raw/master/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so" \
			-o "${RKNN_LIB_DIR}/librknnrt.so" || {
			echo "ERROR: Failed to download librknnrt.so"
			return 1
		}
	}
	chmod 755 "${RKNN_LIB_DIR}/librknnrt.so"

	# Install RKNN API headers for openpilot C++ build (bukapilot's rknnmodel.cc)
	mkdir -p /usr/include/rockchip /usr/local/include/rockchip
	curl -fsSL "${RKNPU2_URL}/runtime/Linux/librknn_api/include/rknn_api.h" \
		-o /usr/include/rockchip/rknn_api.h 2>/dev/null || true
	curl -fsSL "${RKNPU2_URL}/runtime/Linux/librknn_api/include/rknn_matmul_api.h" \
		-o /usr/include/rockchip/rknn_matmul_api.h 2>/dev/null || true
	cp /usr/include/rockchip/rknn_api.h /usr/local/include/rockchip/ 2>/dev/null || true
	cp /usr/include/rockchip/rknn_matmul_api.h /usr/local/include/rockchip/ 2>/dev/null || true

	ldconfig

	# Create systemd service for NPU + DDR frequency setup on boot
	cat > /usr/local/bin/asius-npu-setup.sh << 'NPUEOF'
#!/bin/bash
# Configure NPU and DDR for max performance on boot.
# The kernel RKNPU driver is built-in so no module loading needed.
# librknnrt.so handles CPU fallback for ops the NPU can't run in fp16.

# Fix NPU governor to max frequency (1GHz) for consistent inference latency
if [ -d /sys/class/devfreq/fdab0000.npu ]; then
	echo userspace > /sys/class/devfreq/fdab0000.npu/governor
	echo 1000000000 > /sys/class/devfreq/fdab0000.npu/userspace/set_freq
	echo "asius-npu: NPU fixed at 1GHz"
fi

# Fix DDR governor to max frequency for NPU memory bandwidth
if [ -d /sys/class/devfreq/dmc ]; then
	echo userspace > /sys/class/devfreq/dmc/governor
	echo 2112000000 > /sys/class/devfreq/dmc/userspace/set_freq
	echo "asius-npu: DDR fixed at 2112MHz"
fi
NPUEOF
	chmod 755 /usr/local/bin/asius-npu-setup.sh

	cat > /etc/systemd/system/asius-npu.service << 'EOF'
[Unit]
Description=Asius RKNPU frequency setup
After=local-fs.target
Before=openpilot.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asius-npu-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable asius-npu.service 2>/dev/null || true

	echo "  OK: RKNPU2 runtime installed, NPU setup service enabled"
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

	apt-get install -y -q \
		ffmpeg \
		v4l-utils \
		libv4l-rkmpp \
		camera-engine-rkaiq-rk3588 \
		|| echo "WARNING: Some camera packages failed to install"

	# rkaiq crashes if an ISP instance has no sensor and FakeCamera0 files are missing.
	# This happens when camera overlays are enabled but a camera isn't plugged in.
	# Providing these files lets rkaiq skip the unused ISP gracefully.
	if [[ -d /etc/iqfiles ]]; then
		local IQ="/etc/iqfiles/imx415_CMK-OT2022-PX1_IR0147-50IRC-8M-F20.json"
		if [[ -f "$IQ" ]]; then
			cp "$IQ" /etc/iqfiles/FakeCamera0.json
			touch /etc/iqfiles/FakeCamera0.bin
			echo "  OK: FakeCamera0 files created"
		fi
	fi
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

	mkdir -p /data/openpilot /data/params/d /data/persist/comma /data/media/0/realdata /data/log /data/stats /data/ssh /data/tmp
	chown -R $USERNAME:$USERNAME /data/openpilot /data/params /data/persist /data/media /data/log /data/stats /data/ssh /data/tmp

	ln -sf /data/openpilot /data/pythonpath

	# /persist symlink for openpilot compatibility (expects /persist/ on device)
	ln -sfn /data/persist /persist

	# marker file so openpilot knows this is an asius device (like /TICI for comma)
	touch /ASIUS

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

	# Allow netdev group to manage NetworkManager from remote (SSH) sessions.
	# Default polkit rule requires subject.local which is false over SSH/Tailscale.
	mkdir -p /etc/polkit-1/rules.d
	cat > /etc/polkit-1/rules.d/50-networkmanager.rules << 'PKEOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
PKEOF
}

SetupPowerLimits() {
	echo ">>> Setting up CPU/GPU power limits"

	# Cap frequencies to reduce peak power draw (~5W savings).
	# Prevents brown-out crashes on USB power sources.
	# RK3588 at full clocks (2.35GHz big + 1GHz GPU) draws ~15-20W,
	# which exceeds most USB-C sources under camera + model load.
	cat > /usr/local/bin/asius-power-limit.sh << 'EOF'
#!/bin/bash
# Big cores (A76): cap to 1.8GHz (from 2.35GHz)
echo 1800000 > /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq
echo 1800000 > /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
# Little cores (A55): cap to 1.2GHz (from 1.8GHz)
echo 1200000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
# GPU: performance governor, 900MHz (safe cap, 44ms exec with 6ms headroom)
echo performance > /sys/devices/platform/fb000000.gpu/devfreq/fb000000.gpu/governor 2>/dev/null || true
echo 900000000 > /sys/devices/platform/fb000000.gpu/devfreq/fb000000.gpu/max_freq 2>/dev/null || true
EOF
	chmod 755 /usr/local/bin/asius-power-limit.sh

	cat > /etc/systemd/system/asius-power-limit.service << 'EOF'
[Unit]
Description=Asius CPU/GPU power limits
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asius-power-limit.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable asius-power-limit.service 2>/dev/null || true
}

SetupPersistentJournal() {
	echo ">>> Enabling persistent journal"

	mkdir -p /var/log/journal
	mkdir -p /etc/systemd/journald.conf.d
	cat > /etc/systemd/journald.conf.d/persistent.conf << 'EOF'
[Journal]
Storage=persistent
SystemMaxUse=50M
SystemMaxFileSize=10M
EOF
}

SetupPython() {
	echo ">>> Setting up Python + uv"

	export DEBIAN_FRONTEND=noninteractive

	apt-get install -y -q \
		python3 python3-dev python3-venv \
		network-manager \
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
tmux kill-session -t openpilot 2>/dev/null
exec tmux new-session -d -s openpilot ./launch_openpilot.sh
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

if [ -f "$CONTINUE" ]; then
    chmod +x "$CONTINUE"
    exec su -l asius -c "exec $CONTINUE"
fi

echo "asius-launcher: no /data/continue.sh found"
LAUNCHEOF
	chmod 755 /usr/local/bin/asius-launcher.sh

	cat > /etc/systemd/system/openpilot.service << 'EOF'
[Unit]
Description=Openpilot launcher
After=network.target asius-firstboot.service asius-npu.service rkaiq_3A.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/asius-launcher.sh
ExecStop=/usr/bin/tmux kill-session -t openpilot
User=root
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable openpilot.service 2>/dev/null || true
}

SetupFirstBoot() {
	echo ">>> Setting up first-boot initialization"

	cat > /usr/local/bin/asius-firstboot.sh << 'FBEOF'
#!/bin/bash
MARKER="/data/.asius_initialized"
[ -f "$MARKER" ] && exit 0

echo "asius-firstboot: initializing /data"

mkdir -p /data/openpilot /data/params/d /data/persist/comma /data/media/0/realdata /data/log /data/stats /data/ssh /data/etc/ssh /data/tmp

if [ ! -f /data/ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f /data/ssh/id_ed25519 -N "" -C "asius@$(hostname)"
    chown asius:asius /data/ssh/id_ed25519 /data/ssh/id_ed25519.pub
fi

# generate RSA keypair for openpilot device registration (pilotauth API)
if [ ! -f /data/persist/comma/id_rsa ]; then
    openssl genrsa -out /data/persist/comma/id_rsa 2048
    openssl rsa -in /data/persist/comma/id_rsa -pubout -out /data/persist/comma/id_rsa.pub
    chmod 600 /data/persist/comma/id_rsa
    chown asius:asius /data/persist/comma/id_rsa /data/persist/comma/id_rsa.pub
fi

echo -n 1 > /data/params/d/SshEnabled

chown -R asius:asius /data/openpilot /data/params /data/persist /data/media /data/ssh /data/tmp
chown root:root /data/etc /data/etc/ssh
ln -sfn /data/openpilot /data/pythonpath

# wait for DNS to be ready (NetworkManager may not be up yet at boot)
echo "asius-firstboot: waiting for network..."
for i in $(seq 1 60); do
    if getent hosts pypi.org >/dev/null 2>&1; then
        echo "asius-firstboot: network ready after ${i}s"
        break
    fi
    sleep 1
done
if ! getent hosts pypi.org >/dev/null 2>&1; then
    echo "ERROR: asius-firstboot: no network after 60s, aborting (will retry next boot)"
    exit 1
fi

# create venv + install openpilot python deps (must run on real hardware, not cross-arch chroot)
if [ ! -f /usr/local/venv/bin/python3 ]; then
    echo "asius-firstboot: creating python venv"
    uv venv /usr/local/venv --seed --python-preference only-system --python=3.12 || {
        echo "ERROR: asius-firstboot: venv creation failed, aborting"
        exit 1
    }
    chown -R asius:asius /usr/local/venv
fi

if [ -f /data/openpilot/pyproject.toml ]; then
    echo "asius-firstboot: installing openpilot python dependencies"
    source /usr/local/venv/bin/activate
    cd /data/openpilot
    MAKEFLAGS="-j$(nproc)" UV_NO_CACHE=1 UV_PROJECT_ENVIRONMENT=/usr/local/venv \
        uv pip install -e ".[dev]" --compile-bytecode || {
        echo "ERROR: asius-firstboot: pip install failed, aborting (will retry next boot)"
        exit 1
    }
    # install extra deps not in pyproject.toml
    uv pip install Pillow opencv-python-headless || true
fi

# build and install PLATFORM_COMMA raylib Python wheel (must run on real aarch64 hardware)
RAYLIB_DIR="/data/openpilot/third_party/raylib"
if [ -f "$RAYLIB_DIR/larch64/libraylib.a" ] && [ -f "$RAYLIB_DIR/include/raylib.h" ]; then
    echo "asius-firstboot: building raylib PLATFORM_COMMA Python wheel"
    source /usr/local/venv/bin/activate

    # clone raylib-python-cffi if not present
    if [ ! -d "$RAYLIB_DIR/raylib_python_repo" ]; then
        git clone --depth=1 https://github.com/electronstudio/raylib-python-cffi.git "$RAYLIB_DIR/raylib_python_repo"
        chown -R asius:asius "$RAYLIB_DIR/raylib_python_repo"
    fi

    cd "$RAYLIB_DIR/raylib_python_repo"
    rm -rf build dist
    RAYLIB_PLATFORM=PLATFORM_COMMA \
        RAYLIB_INCLUDE_PATH="$RAYLIB_DIR/include" \
        RAYGUI_INCLUDE_PATH="$RAYLIB_DIR/include" \
        RAYLIB_LINK_ARGS="$RAYLIB_DIR/larch64/libraylib.a -lGLESv2 -lEGL -lgbm -ldrm -lm -lpthread -lrt -ldl -latomic" \
        python3 setup.py bdist_wheel || {
        echo "ERROR: asius-firstboot: raylib wheel build failed"
    }

    WHEEL=$(ls dist/raylib-*.whl 2>/dev/null | head -1)
    if [ -n "$WHEEL" ]; then
        pip install --force-reinstall "$WHEEL" || echo "ERROR: raylib wheel install failed"
        echo "asius-firstboot: raylib PLATFORM_COMMA wheel installed"
    fi
    cd /data/openpilot
fi

touch "$MARKER"
chown asius:asius "$MARKER"

echo "asius-firstboot: done, SSH pubkey: $(cat /data/ssh/id_ed25519.pub 2>/dev/null)"
FBEOF
	chmod 755 /usr/local/bin/asius-firstboot.sh

	cat > /etc/systemd/system/asius-firstboot.service << 'EOF'
[Unit]
Description=Asius first-boot initialization
After=local-fs.target network-online.target
Wants=network-online.target
Before=openpilot.service
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
