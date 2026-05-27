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

	if [[ ! -s "${destination}/usr/share/keyrings/seeed-repo.gpg" ]]; then
		exit_with_error "Failed to import Seeed GPG key"
	fi

	# Select APT distribution based on target release
	# Debian uses bookworm, Ubuntu uses stable
	local SEEED_DIST="bookworm"
	if [[ "${RELEASE}" =~ ^(focal|jammy|noble|plucky|questing|oracular)$ ]]; then
		SEEED_DIST="stable"
	fi

	cat > "${destination}/etc/apt/sources.list.d/seeed.list" <<- EOF
		deb [signed-by=/usr/share/keyrings/seeed-repo.gpg] ${SEEED_APT_REPO_URL} ${SEEED_DIST} main
	EOF
}

# Helper: install packages from Seeed APT repo.
# Imports GPG key, writes source, updates index, installs packages.
# Automatically selects 'bookworm' or 'stable' distribution based on RELEASE.
# Usage: seeed_recomputer_install_from_apt <package> [<package> ...]
function seeed_recomputer_install_from_apt() {
	(($#)) || return 0

	# Select APT distribution based on target release
	# Debian uses bookworm, Ubuntu uses stable
	local SEEED_DIST="bookworm"
	if [[ "${RELEASE}" =~ ^(focal|jammy|noble|plucky|questing|oracular)$ ]]; then
		SEEED_DIST="stable"
	fi

	# Import GPG key if not already present (dearmor to binary format for signed-by)
	if [[ ! -f "${SDCARD}/usr/share/keyrings/seeed-repo.gpg" ]]; then
		install -d -m 0755 "${SDCARD}/usr/share/keyrings"
		curl -fsSL --noproxy '*' --connect-timeout 30 --retry 3 \
			"${SEEED_APT_REPO_URL}/seeed-repo.gpg" \
			| gpg --dearmor > "${SDCARD}/usr/share/keyrings/seeed-repo.gpg" 2>/dev/null

		if [[ ! -s "${SDCARD}/usr/share/keyrings/seeed-repo.gpg" ]]; then
			exit_with_error "Failed to import Seeed GPG key"
		fi
	fi

	# Write Seeed source if not present (or update distribution if mismatched)
	local expected_source="deb [signed-by=/usr/share/keyrings/seeed-repo.gpg] ${SEEED_APT_REPO_URL} ${SEEED_DIST} main"
	if [[ ! -f "${SDCARD}/etc/apt/sources.list.d/seeed.list" ]] || \
	   ! grep -qF "${expected_source}" "${SDCARD}/etc/apt/sources.list.d/seeed.list" 2>/dev/null; then
		cat > "${SDCARD}/etc/apt/sources.list.d/seeed.list" <<- EOF
			${expected_source}
		EOF
	fi

	chroot_sdcard apt-get -y -qq -o Dpkg::Use-Pty=0 update
	chroot_sdcard DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Use-Pty=0 \
		--no-install-recommends install "$@"
}

# Install Seeed common packages (USB gadget, Morse tools).
# fcs960k-aic-bluez is NOT installed here — it conflicts with bluez,
# which is pulled in by desktop packages. It is installed in a separate
# post_repo_customize_image hook after all desktop/extension packages.
function pre_install_distribution_specific__recomputer_install_seeed_packages() {
	display_alert "Installing Seeed packages from APT repo" "seeed-apt" "info"

	seeed_recomputer_install_from_apt \
		usbdevice-gadget-rk \
		wpa-supplicant-morse-tools \
		morsectrl-tools \
		hostapd-morse-tools \
		morse-fgh100m-dkms

	display_alert "Seeed packages installed successfully" "seeed-apt" "info"
}

# Install fcs960k-aic-bluez AFTER all desktop/extension packages.
# This package conflicts with bluez; desktop pulls in bluez during
# install_distribution_agnostic, so we install fcs960k last to replace it.
# apt's conflict resolution removes packages that depend on bluez
# (e.g. gnome-session, gnome-control-center, gdm3).
# We perform snapshot and diff entirely inside chroot to avoid
# pipe/process-substitution issues with dpkg-query across chroot boundary.
function post_repo_customize_image__recomputer_install_fcs960k_bluez() {
	display_alert "Installing fcs960k-aic-bluez (replacing bluez)" "seeed-apt" "info"

	# Snapshot installed packages (only "ii" status, excluding rc/unpacked)
	# dpkg-query -W lists ALL packages including rc-status (removed, config-files),
	# which would make comm diff miss packages that were removed but left config files.
	local snapshot_before snapshot_after
	snapshot_before=$(mktemp --tmpdir="${SDCARD}/tmp" pkg-before.XXXXXX)
	snapshot_after=$(mktemp --tmpdir="${SDCARD}/tmp" pkg-after.XXXXXX)
	chroot_sdcard_with_stdout dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' \
		| grep "^ii " | awk '{print $2}' | sort > "${snapshot_before}"

	# Pre-compute packages that depend on bluez (one apt-cache call instead of N)
	local bluez_deps
	bluez_deps=$(chroot_sdcard_with_stdout apt-cache rdepends --installed bluez 2>/dev/null \
		| awk 'NR>2 && NF{print $1}' | sort -u)

	seeed_recomputer_install_from_apt fcs960k-aic-bluez

	# Diff to detect removed packages
	chroot_sdcard_with_stdout dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' \
		| grep "^ii " | awk '{print $2}' | sort > "${snapshot_after}"
	local removed_pkgs
	removed_pkgs=$(comm -23 "${snapshot_before}" "${snapshot_after}")
	removed_pkgs=$(printf '%s\n' "${removed_pkgs}" | grep -vxE 'bluez|fcs960k-aic-bluez' || true)
	rm -f "${snapshot_before}" "${snapshot_after}"

	if [[ -n "${removed_pkgs}" ]]; then
		# Filter out packages that depend on bluez — reinstalling them would
		# pull bluez back via apt dependency resolution, which conflicts with
		# fcs960k-aic-bluez and removes it again.
		local -a safe_pkgs=()
		for pkg in ${removed_pkgs}; do
			if printf '%s\n' "${bluez_deps}" | grep -qxF "$pkg"; then
				display_alert "Skipping reinstall (depends on bluez)" "$pkg" "warn"
			else
				safe_pkgs+=("$pkg")
			fi
		done

		if [[ ${#safe_pkgs[@]} -gt 0 ]]; then
			display_alert "Reinstalling packages removed by bluez conflict" "${safe_pkgs[*]}" "warn"
			chroot_sdcard_apt_get_install "${safe_pkgs[@]}"
		fi
	fi

	# Re-disable display managers: reinstalling gdm3 triggers its postinst
	# which re-enables display-manager.service, undoing desktop_postinstall()'s
	# disable. Without this the system boots into GDM instead of console,
	# skipping armbian-firstlogin's user/password setup prompt.
	disable_systemd_service_sdcard gdm3.service
	disable_systemd_service_sdcard lightdm.service
	disable_systemd_service_sdcard sddm.service
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
	if chroot_sdcard test -f /usr/lib/systemd/system/aic-bluetooth.service || \
	   chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service || \
	   chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
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

# Auto-mount USB storage under /media/<first-user>/ (DE-agnostic)
function post_family_tweaks__recomputer_usb_auto_mount() {
	display_alert "$BOARD" "Installing USB auto-mount" "info"

	# Helper script: mount/unmount USB device under /media/<first-user>/LABEL
	install -d -m 0755 "${SDCARD}/usr/local/bin"
	cat > "${SDCARD}/usr/local/bin/usb-automount" <<- 'SCRIPT'
		#!/bin/sh
		ACTION="$1"
		DEV="$2"
		FIRST_USER=$(id -nu 1000 2>/dev/null || echo user)
		BASE="/media/${FIRST_USER}"

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
		            chown "${FIRST_USER}:${FIRST_USER}" "$MPOINT" 2>/dev/null
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
		ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="?*", ENV{ID_BUS}=="usb", ENV{ID_PART_ENTRY_NUMBER}=="?*", ENV{UDISKS_IGNORE}="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb-automount@%k.service"
	EOF
}

# Add /usr/sbin and /sbin to PATH for all users
function post_family_tweaks__recomputer_add_sbin_to_path() {
	display_alert "$BOARD" "Adding sbin directories to PATH" "info"

	mkdir -p "${SDCARD}/etc/profile.d"
	cat > "${SDCARD}/etc/profile.d/custom-path.sh" <<-'EOF'
	# Add sbin directories to PATH for ifconfig and other admin tools
	case ":$PATH:" in
	  *":/usr/sbin:"*) ;;
	  *) [ -d /usr/sbin ] && PATH="/usr/sbin:$PATH" ;;
	esac
	case ":$PATH:" in
	  *":/sbin:"*) ;;
	  *) [ -d /sbin ] && PATH="/sbin:$PATH" ;;
	esac
	export PATH
	EOF

	chmod +x "${SDCARD}/etc/profile.d/custom-path.sh"
}

# Patch armbian-firstlogin: disable GDM auto-login.
# Upstream sets AutomaticLoginEnable=true and relies on a background
# (sleep 20; sed) to disable it, which is unreliable and gets killed.
# Force AutomaticLoginEnable=false so GDM always prompts for password.
function post_family_tweaks__recomputer_disable_gdm_autologin() {
	display_alert "$BOARD" "Disabling GDM auto-login in armbian-firstlogin" "info"
	sed -i 's/AutomaticLoginEnable = true/AutomaticLoginEnable = false/' \
		"${SDCARD}/usr/lib/armbian/armbian-firstlogin"
}

#

# Stage kernel patches from Seeed extension into userpatches so the
# Armbian framework applies them during kernel build. Uses the same
# pattern as gateway-dk-ask.sh: copy to userpatches/kernel/${KERNELPATCHDIR}/.
function post_family_config__recomputer_stage_kernel_patches() {
	if [[ "${ENABLE_SEEED_RK_EXTENSION}" != "yes" ]]; then
		return 0
	fi

	local ext_patch_dir="${SRC}/extensions/seeed_armbian_extension/patches/kernel"
	local user_patch_dir="${SRC}/userpatches/kernel/${KERNELPATCHDIR}"

	if [[ ! -d "${ext_patch_dir}" ]]; then
		display_alert "Seeed kernel patches" "Directory not found: ${ext_patch_dir}" "warn"
		return 0
	fi

	install -d -m 0755 "${user_patch_dir}"

	local patch_file
	for patch_file in "${ext_patch_dir}"/*.patch; do
		[[ -f "${patch_file}" ]] || continue
		cp "${patch_file}" "${user_patch_dir}/"
		display_alert "Seeed kernel patch staged" "$(basename "${patch_file}")" "info"
	done
}

# Clone/pull Seeed RK extension and enable it.
# Must run during board config sourcing (before initialize_extension_manager),
# because enable_extension() cannot be called after the extension manager initializes.
if [[ "${ENABLE_SEEED_RK_EXTENSION:-no}" == "yes" ]]; then
	# GITHUB_SOURCE is not set yet during board config sourcing; provide a default
	# so fetch_from_repo's URL rewriting works correctly.
	GITHUB_SOURCE="${GITHUB_SOURCE:-https://github.com}"
	fetch_from_repo "https://github.com/Seeed-Studio/seeed_armbian_extension" "seeed_armbian_extension" "branch:main"
	SEEED_EXT_DIR="${SRC}/cache/sources/seeed_armbian_extension"
	mkdir -p "${SRC}/extensions"
	ln -sf "${SEEED_EXT_DIR}" "${SRC}/extensions/seeed_armbian_extension"
	enable_extension "seeed_armbian_extension"
fi
