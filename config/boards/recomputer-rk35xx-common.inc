# Common configuration for reComputer RK3576/RK3588 DevKit
# Source this file from individual board configs.

# Helper: download a deb if not cached, then install into chroot
# Usage: seeed_recomputer_download_and_install_deb <url> <cache_filename> <display_name>
function seeed_recomputer_download_and_install_deb() {
	local url="$1"
	local cache_filename="$2"
	local display_name="$3"

	local deb_file="${SRC}/cache/download/${cache_filename}"
	mkdir -p "${SRC}/cache/download"

	if [[ ! -f "${deb_file}" ]]; then
		display_alert "Downloading ${display_name}" "${url}" "info"
		wget "${url}" -O "${deb_file}" || {
			display_alert "Failed to download ${display_name}" "${display_name}" "err"
			return 1
		}
	fi

	install_deb_chroot "${deb_file}" "" "" ""
	display_alert "${display_name} installed successfully" "${display_name}" "info"
}

# Install custom bluez package for FCS960K support
function pre_install_distribution_specific__recomputer_install_custom_bluez() {
	seeed_recomputer_download_and_install_deb \
		"https://github.com/Seeed-Studio/seeed_armbian_extension/releases/download/v1.0/fcs960k-aic-bluez_5.66-1_arm64.deb" \
		"fcs960k-aic-bluez_5.66-1_arm64.deb" \
		"fcs960k-aic-bluez"
}

# Install USB gadget package
function pre_install_distribution_specific__recomputer_install_usbdevice_gadget() {
	seeed_recomputer_download_and_install_deb \
		"https://github.com/Seeed-Studio/seeed_armbian_extension/releases/download/v1.0/usbdevice-gadget-rk3588_1.0.1_arm64.deb" \
		"usbdevice-gadget-rk3588_1.0.1_arm64.deb" \
		"usbdevice-gadget"
}

# Install Morse Wireless tools (FGH100M support)
# Note: Extract and copy files directly without deb installation
function pre_install_distribution_specific__recomputer_install_morse_tools() {
	display_alert "Installing Morse wireless tools for FGH100M" "morse-tools" "info"

	local cache_dir="${SRC}/cache/download"
	local extract_dir="${SRC}/cache/morse-tools-extract"
	mkdir -p "${cache_dir}" "${extract_dir}"

	declare -A packages=(
		["wpa-supplicant-morse-tools"]="https://github.com/Seeed-Studio/seeed_armbian_extension/releases/download/v1.0/wpa-supplicant-morse-tools_1.0-1_arm64.deb"
		["morsectrl-tools"]="https://github.com/Seeed-Studio/seeed_armbian_extension/releases/download/v1.0/morsectrl-tools_1.0-1_arm64.deb"
		["hostapd-morse-tools"]="https://github.com/Seeed-Studio/seeed_armbian_extension/releases/download/v1.0/hostapd-morse-tools_1.0-1_arm64.deb"
	)

	for pkg_name in "${!packages[@]}"; do
		local pkg_url="${packages[$pkg_name]}"
		local pkg_file="${cache_dir}/${pkg_name}_1.0-1_arm64.deb"

		if [[ ! -f "${pkg_file}" ]]; then
			display_alert "Downloading ${pkg_name}" "${pkg_url}" "info"
			wget "${pkg_url}" -O "${pkg_file}" || {
				display_alert "Failed to download ${pkg_name}" "${pkg_name}" "err"
				continue
			}
		fi

		display_alert "Extracting ${pkg_name}" "morse-tools" "info"
		rm -rf "${extract_dir}/${pkg_name}"
		mkdir -p "${extract_dir}/${pkg_name}"
		dpkg-deb -x "${pkg_file}" "${extract_dir}/${pkg_name}"

		display_alert "Copying ${pkg_name} files" "morse-tools" "info"
		cp -r "${extract_dir}/${pkg_name}"/* "${SDCARD}/"
	done

	display_alert "Morse wireless tools installed successfully" "morse-tools" "info"
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

		# BT UART differs between SoCs
		local bt_uart
		case "${BOOT_SOC}" in
			rk3576) bt_uart="/dev/ttyS4" ;;
			rk3588) bt_uart="/dev/ttyS6" ;;
			*)      bt_uart="/dev/ttyS1" ;;
		esac
		sed -i "s|/dev/ttyS1|${bt_uart}|g" "${destination}/usr/bin/aic-bluetooth"

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
		bind-interfaces
		port=0
		dhcp-range=192.168.42.100,192.168.42.150,255.255.255.0,12h
		dhcp-option=option:router
		dhcp-option=option:dns-server
	EOF

	# serial-getty@ttyGS0 ordering: wait for usbdevice to create the device node
	mkdir -p "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d"
	cat > "${SDCARD}/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usbdevice.conf" <<- EOF
		[Unit]
		After=usbdevice.service
		Wants=usbdevice.service
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

	# dnsmasq: wait for usbdevice + retry if usb0 not ready yet
	mkdir -p "${SDCARD}/etc/systemd/system/dnsmasq.service.d"
	cat > "${SDCARD}/etc/systemd/system/dnsmasq.service.d/10-usb-gadget.conf" <<- EOF
		[Unit]
		After=usbdevice.service
		Wants=usbdevice.service
		[Service]
		Restart=on-failure
		RestartSec=5
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

		eval "$(udevadm info --query=property --name="$DEV" 2>/dev/null | grep -E '^ID_FS_LABEL_ENC=|^ID_MODEL=')"
		LABEL="${ID_FS_LABEL_ENC:-${ID_MODEL:-$(basename "$DEV")}}"
		LABEL=$(echo "$LABEL" | sed 's/^ *//;s/ *$//' | tr -s ' ')

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


# Enable Seeed RK extension (clone/pull + enable_extension)
if [[ "${ENABLE_SEEED_RK_EXTENSION}" == "yes" ]]; then
	if [[ ! -d "${SRC}/extensions/seeed_armbian_extension" ]]; then
		echo "[${BOARD_NAME}] Cloning Seeed extensions from GitHub..."
		git clone https://github.com/Seeed-Studio/seeed_armbian_extension.git "${SRC}/extensions/seeed_armbian_extension" || {
			echo "[${BOARD_NAME}] Warning: Failed to clone Seeed extensions"
		}
	else
		echo "[${BOARD_NAME}] Seeed extensions already exists, pulling updates..."
		git -C "${SRC}/extensions/seeed_armbian_extension" pull || echo "[${BOARD_NAME}] Warning: Failed to pull updates"
	fi

	enable_extension "seeed_armbian_extension"
fi
