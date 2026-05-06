# Common configuration for reComputer RK3576/RK3588 DevKit
# Source this file from individual board configs.

# Seeed APT repository configuration
SEEED_APT_REPO_URL="https://seeed-studio.github.io/seeed_armbian_extension"

# Configure Seeed APT repository in the image (persists for apt upgrade)
function post_family_tweaks_bsp__seeed_configure_apt_source() {
	display_alert "$BOARD" "Configuring Seeed APT repository" "info"

	install -d -m 0755 "${destination}/usr/share/keyrings"
	install -d -m 0755 "${destination}/etc/apt/sources.list.d"
	curl -fsSL --connect-timeout 30 --retry 3 \
		"${SEEED_APT_REPO_URL}/seeed-repo.gpg" \
		| gpg --dearmor > "${destination}/usr/share/keyrings/seeed-repo.gpg" 2>/dev/null

	cat > "${destination}/etc/apt/sources.list.d/seeed.list" <<- EOF
		deb [signed-by=/usr/share/keyrings/seeed-repo.gpg] ${SEEED_APT_REPO_URL} stable main
	EOF
}

# Helper: install packages from Seeed APT repo.
# Imports GPG key, writes source, updates only Seeed index, installs packages.
# The persistent apt source is configured by post_family_tweaks_bsp__seeed_configure_apt_source.
# Usage: seeed_recomputer_install_from_apt <package> [<package> ...]
function seeed_recomputer_install_from_apt() {
	(($#)) || return 0

	# Import GPG key if not already present (dearmor to binary format for signed-by)
	if [[ ! -f "${SDCARD}/usr/share/keyrings/seeed-repo.gpg" ]]; then
		install -d -m 0755 "${SDCARD}/usr/share/keyrings"
		curl -fsSL --connect-timeout 30 --retry 3 \
			"${SEEED_APT_REPO_URL}/seeed-repo.gpg" \
			| gpg --dearmor > "${SDCARD}/usr/share/keyrings/seeed-repo.gpg" 2>/dev/null
	fi

	# Write Seeed source if not present
	if [[ ! -f "${SDCARD}/etc/apt/sources.list.d/seeed.list" ]]; then
		cat > "${SDCARD}/etc/apt/sources.list.d/seeed.list" <<- EOF
			deb [signed-by=/usr/share/keyrings/seeed-repo.gpg] ${SEEED_APT_REPO_URL} stable main
		EOF
	fi

	# Only update the Seeed source, not all sources
	chroot_sdcard apt-get -y -qq -o Dpkg::Use-Pty=0 \
		-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/seeed.list \
		-o Dir::Etc::sourceparts=/dev/null \
		update

	chroot_sdcard DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Use-Pty=0 \
		--no-install-recommends install "$@"
}

# Install Seeed common packages (USB gadget, Morse tools)
# Note: fcs960k-aic-bluez is NOT installed here — it conflicts with bluez,
# which gets pulled in later by desktop packages. It's installed in
# post_repo_customize_image instead, after all desktop/extension packages.
function pre_install_distribution_specific__recomputer_install_seeed_packages() {
	display_alert "Installing Seeed packages from APT repo" "seeed-apt" "info"

	seeed_recomputer_install_from_apt \
		usbdevice-gadget-rk3588 \
		wpa-supplicant-morse-tools \
		morsectrl-tools \
		hostapd-morse-tools

	display_alert "Seeed packages installed successfully" "seeed-apt" "info"
}

# Install fcs960k-aic-bluez AFTER all desktop/extension packages.
# This package conflicts with bluez; desktop pulls in bluez during
# install_distribution_agnostic, so we must install fcs960k last to replace it.
function post_repo_customize_image__recomputer_install_fcs960k_bluez() {
	display_alert "Installing fcs960k-aic-bluez (replacing bluez)" "seeed-apt" "info"

	seeed_recomputer_install_from_apt fcs960k-aic-bluez
}

# AIC8800 wireless tweaks (BSP-level)
function post_family_tweaks_bsp__recomputer_aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d

	cat > "${destination}"/etc/modprobe.d/aic8800-wireless.conf <<- EOT
		options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	EOT

	cat > "${destination}"/etc/modules-load.d/aic8800-btlpm.conf <<- EOT
		hidp
		rfcomm
		bnep
		aic8800_btlpm_sdio
	EOT

	if [[ -d "$SRC/packages/bsp/aic8800" ]]; then
		install -d -m 0755 "${destination}/usr/bin"
		install -m 0755 "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}/usr/bin/aic-bluetooth"

		# BT UART differs between boards
		sed -i "s|/dev/ttyS1|${BT_UART}|g" "${destination}/usr/bin/aic-bluetooth"

		install -d -m 0755 "${destination}/usr/lib/systemd/system"
		install -m 0644 "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}/usr/lib/systemd/system/aic-bluetooth.service"
	else
		display_alert "$BOARD" "Skipping AIC8800 BT assets (packages/bsp/aic8800 not found)" "warn"
	fi
}

# Enable AIC8800 Bluetooth Service
function post_family_tweaks__recomputer_enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	if chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service || chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	else
		display_alert "$BOARD" "aic-bluetooth.service not found in image; skipping enable" "warn"
	fi
}

# Morse FGH100M firmware
function post_family_tweaks_bsp__recomputer_fgh100m_morse_firmware() {
	local morse_fw_rev="commit:974c7744263ffb56a1c8678962e740fdcb3428f7"

	fetch_from_repo "https://github.com/MorseMicro/morse-firmware.git" "morse-firmware" "${morse_fw_rev}" "yes"

	local morse_fw_dir="${SRC}/cache/sources/morse-firmware/${morse_fw_rev#*:}"

	if [[ -d "${morse_fw_dir}" ]]; then
		install -d -m 0755 "${destination}/lib/firmware/morse"
		install -m 0644 "${morse_fw_dir}/bcf/quectel/bcf_fgh100mhaamd.bin" "${destination}/lib/firmware/morse/bcf_default.bin"
		install -m 0644 "${morse_fw_dir}/firmware/mm6108.bin" "${destination}/lib/firmware/morse/mm6108.bin"
	else
		display_alert "$BOARD" "morse-firmware not found at ${morse_fw_dir}" "warn"
	fi
}

# USB gadget defaults (ACM + RNDIS, usb0 management link)
function post_family_tweaks__recomputer_enable_usb_gadget_defaults() {
	display_alert "$BOARD" "Configuring USB gadget defaults (ACM + RNDIS, usb0 management link)" "info"

	do_with_retries 3 chroot_sdcard_apt_get_install dnsmasq

	# USB gadget mode selection (ACM serial + RNDIS network)
	cat > "${SDCARD}/etc/init.d/.usb_config" <<- EOF
		usb_acm_en
		usb_rndis_en
	EOF

	# NM static IP connection for usb0
	mkdir -p "${SDCARD}/etc/NetworkManager/system-connections"
	cat > "${SDCARD}/etc/NetworkManager/system-connections/usb0-static.nmconnection" <<- EOF
		[connection]
		id=usb0-static
		type=ethernet
		interface-name=usb0
		autoconnect=true

		[ipv4]
		address1=192.168.42.1/24
		method=manual
		never-default=true

		[ipv6]
		method=disabled
	EOF
	chmod 600 "${SDCARD}/etc/NetworkManager/system-connections/usb0-static.nmconnection"

	# dnsmasq DHCP on usb0
	mkdir -p "${SDCARD}/etc/dnsmasq.d"
	cat > "${SDCARD}/etc/dnsmasq.d/usb0-dhcp.conf" <<- EOF
		interface=usb0
		bind-dynamic
		port=0
		dhcp-range=192.168.42.100,192.168.42.150,255.255.255.0,12h
		dhcp-option=option:router
		dhcp-option=option:dns-server
	EOF

	# serial-getty@ttyGS0: clear BindsTo=dev-ttyGS0.device from base unit
	# (ttyGS0 is a USB gadget, not present at boot → BindsTo causes dependency failure).
	# Keep Restart=always from base unit (not on-failure, else normal logout kills the getty).
	mkdir -p "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d"
	cat > "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usbdevice.conf" <<- EOF
		[Unit]
		BindsTo=
		After=usbdevice.service
		Wants=usbdevice.service

		[Service]
		RestartSec=3
	EOF

	chroot_sdcard systemctl --no-reload enable usbdevice.service
	chroot_sdcard systemctl --no-reload enable dnsmasq.service

	# usbdevice.service: retry on failure + tell NM to manage usb0 + bring link up
	mkdir -p "${SDCARD}/etc/systemd/system/usbdevice.service.d"
	cat > "${SDCARD}/etc/systemd/system/usbdevice.service.d/10-retry.conf" <<- EOF
		[Service]
		Restart=on-failure
		RestartSec=5
		ExecStartPost=/usr/bin/nmcli device set usb0 managed yes
		ExecStartPost=/sbin/ip link set usb0 up
	EOF

}

# Auto-mount USB storage under /media/seeed/ (DE-agnostic)
function post_family_tweaks__recomputer_usb_auto_mount() {
	display_alert "$BOARD" "Installing USB auto-mount" "info"

	# Helper script: mount/unmount USB device under /media/seeed/LABEL
	install -d -m 0755 "${SDCARD}/usr/local/bin"
	cat > "${SDCARD}/usr/local/bin/usb-automount" <<- 'SCRIPT'
		#!/bin/sh
		ACTION="$1"
		DEV="$2"
		BASE="/media/seeed"

		ID_FS_LABEL_ENC=$(udevadm info --query=property --name="$DEV" --property=ID_FS_LABEL_ENC --value 2>/dev/null)
		ID_MODEL=$(udevadm info --query=property --name="$DEV" --property=ID_MODEL --value 2>/dev/null)
		LABEL="${ID_FS_LABEL_ENC:-${ID_MODEL:-$(basename "$DEV")}}"
		# Sanitize: keep only safe characters for path component
		LABEL=$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')

		case "$ACTION" in
		    add)
		        MPOINT="$BASE/$LABEL"
		        mkdir -p "$MPOINT"
		        if mount -o noatime "$DEV" "$MPOINT" 2>/dev/null || \
		           mount -o noatime,uid=1000,gid=1000,umask=002 "$DEV" "$MPOINT" 2>/dev/null; then
		            chown seeed:seeed "$MPOINT" 2>/dev/null
		        else
		            rmdir "$MPOINT" 2>/dev/null
		        fi
		        ;;
		    remove)
		        MPOINT="$BASE/$LABEL"
		        umount "$DEV" 2>/dev/null || true
		        rmdir "$MPOINT" 2>/dev/null || true
		        ;;
		esac
	SCRIPT
	chmod 755 "${SDCARD}/usr/local/bin/usb-automount"

	# Systemd template service: one instance per USB partition
	cat > "${SDCARD}/etc/systemd/system/usb-automount@.service" <<- EOF
		[Unit]
		Description=Auto-mount USB device %i
		BindsTo=dev-%i.device
		After=dev-%i.device

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/local/bin/usb-automount add /dev/%i '' ''
		ExecStop=/usr/local/bin/usb-automount remove /dev/%i '' ''
	EOF

	# Udev rule: trigger systemd service when USB partition appears
	mkdir -p "${SDCARD}/etc/udev/rules.d"
	cat > "${SDCARD}/etc/udev/rules.d/80-udisks-auto-mount.rules" <<- EOF
		ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="?*", ENV{ID_BUS}=="usb", ENV{ID_PART_ENTRY_NUMBER}=="?*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb-automount@%k.service"
	EOF
}

# Add /usr/sbin and /sbin to PATH for all users
function post_family_tweaks__recomputer_add_sbin_to_path() {
	display_alert "$BOARD" "Adding sbin directories to PATH" "info"

	mkdir -p $SDCARD/etc/profile.d
	cat > $SDCARD/etc/profile.d/custom-path.sh <<-'EOF'
	# Add sbin directories to PATH for ifconfig and other admin tools
	if [ -d /usr/sbin ] && [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
	    PATH="/usr/sbin:$PATH"
	fi
	if [ -d /sbin ] && [[ ":$PATH:" != *":/sbin:"* ]]; then
	    PATH="/sbin:$PATH"
	fi
	export PATH
	EOF

	chmod +x $SDCARD/etc/profile.d/custom-path.sh
}

# Clone/pull Seeed RK extension at top-level before enable_extension
if [[ "${ENABLE_SEEED_RK_EXTENSION}" == "yes" ]]; then
	if [[ ! -d "${SRC}/extensions/seeed_armbian_extension" ]]; then
		display_alert "Cloning Seeed extensions from GitHub" "$BOARD_NAME" "info"
		git clone https://github.com/Seeed-Studio/seeed_armbian_extension.git "${SRC}/extensions/seeed_armbian_extension" || {
			display_alert "Failed to clone Seeed extensions" "$BOARD_NAME" "warn"
		}
	else
		display_alert "Seeed extensions already exists, pulling updates" "$BOARD_NAME" "info"
		git -C "${SRC}/extensions/seeed_armbian_extension" pull || display_alert "Failed to pull updates" "$BOARD_NAME" "warn"
	fi

	enable_extension "seeed_armbian_extension"
fi
