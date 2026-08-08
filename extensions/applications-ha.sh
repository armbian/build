enable_extension "docker-ce"

function extension_prepare_config__home_assistant() {

	if [[ ${MINIMAL} == "yes" ]]; then
		exit_with_error "Home Assistant Supervised needs full CLI image that comes with Network manager"
	fi

	display_alert "Target image will be a Home Assistant Supervised deploy" "${EXTENSION}" "info"
        case "${RELEASE}" in
                bullseye | bookworm | trixie)
                        display_alert "Setting up Home Assistant Supervised on Debian ${RELEASE}" "${EXTENSION}" "info"
                        ;;
                *)
                        exit_with_error "Home Assistant Supervised is not supported on ${DISTRIBUTION} ${RELEASE}"
                        ;;
        esac

        EXTRA_IMAGE_SUFFIXES+=("-homeassistant") # global array

}

function pre_customize_image__500_add_ha_to_image() {

	# Rockchip vendor kernel needs some additional arguments to work right
	if [[ ${BRANCH} == "vendor" && ${BOARDFAMILY} == "rockchip-rk3588" ]]; then
		declare -g HA_UBOOT_EXTRAARGS="apparmor=1 security=apparmor"
	fi

        # We need extra space in the rootfs for the Java build machine
        display_alert "Adding extra space" "current extra: ${EXTRA_ROOTFS_MIB_SIZE}" "info"
        if [[ ${EXTRA_ROOTFS_MIB_SIZE} -le 512 ]]; then
                declare -g EXTRA_ROOTFS_MIB_SIZE=512
                display_alert "Setting new EXTRA_ROOTFS_MIB_SIZE: ${EXTRA_ROOTFS_MIB_SIZE}" "${EXTENSION}" "info"
        fi

	declare -g HA_OS_AGENT_ARCH="${ARCH}"
	[[ "${ARCH}" == "armhf" ]] && declare -g HA_OS_AGENT_ARCH="armv7"
	[[ "${ARCH}" == "arm64" ]] && declare -g HA_OS_AGENT_ARCH="aarch64"
	[[ "${ARCH}" == "amd64" ]] && declare -g HA_OS_AGENT_ARCH="x86_64"

	declare -g HA_OS_AGENT_CACHE_DIR="${SRC}/cache/home_assistant_debs"

	# os-agent   deb: amd64 https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_x86_64.deb
	# os-agent   deb: arm64 https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_aarch64.deb
	# os-agent   deb: armhf https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_armv7.deb
	declare -g HA_OS_AGENT_VERSION="1.7.2"
	declare -g HA_OS_AGENT_FILENAME="os-agent_${HA_OS_AGENT_VERSION}_linux_${HA_OS_AGENT_ARCH}.deb"
	declare -g HA_OS_AGENT_URL="https://github.com/home-assistant/os-agent/releases/download/${HA_OS_AGENT_VERSION}/${HA_OS_AGENT_FILENAME}"
	declare -g HA_OS_AGENT_CACHE_FILE="${HA_OS_AGENT_CACHE_DIR}/${HA_OS_AGENT_FILENAME}"

	# Fetch supervised repostory from release 3.0.0, patch it to disable Grub update and install
	# Without this patch, installation breaks with /usr/sbin/grub-probe: error: failed to get canonical path of `tmpfs'
	fetch_from_repo "https://github.com/home-assistant/supervised-installer" "supervised-installer" "commit:f5951143a17a45013a6c4c5364a6c39e19d23f03"
	cd "${SRC}"/cache/sources/supervised-installer || exit

	# Updating grup fails in chroot and we do it later anyway
	sed -i "/update-grub/d" homeassistant-supervised/DEBIAN/postinst

	# Build deb file
	chmod 555 homeassistant-supervised/DEBIAN/p*
	dpkg-deb -v --build --root-owner-group homeassistant-supervised

	# supervised deb: all
	declare -g HA_SUPERVISED_VERSION="3.0.0"
	declare -g HA_SUPERVISED_FILENAME="homeassistant-supervised_${HA_SUPERVISED_VERSION}.deb"
	declare -g HA_SUPERVISED_URL="https://github.com/home-assistant/supervised-installer/releases/download/${HA_SUPERVISED_VERSION}/homeassistant-supervised.deb"

	# using Armbian patched version
	declare -g HA_SUPERVISED_URL="https://github.com/armbian/supervised-installer/releases/download/2.9.9/homeassistant-supervised.deb"
	# using Armbian patched version

	declare -g HA_SUPERVISED_CACHE_FILE="${HA_OS_AGENT_CACHE_DIR}/${HA_SUPERVISED_FILENAME}"

	display_alert "Adding HA dependency packages" "${EXTENSION}" "info"
	chroot_sdcard_apt_get_install systemd-journal-remote apparmor cifs-utils nfs-common network-manager bluetooth systemd-timesyncd

	display_alert "Fetching Home Assistant debs" "${EXTENSION}" "info"
	mkdir -p "${HA_OS_AGENT_CACHE_DIR}"

	cp homeassistant-supervised.deb "${HA_OS_AGENT_CACHE_DIR}/${HA_SUPERVISED_FILENAME}"

	if [[ -f "${HA_OS_AGENT_CACHE_FILE}" ]]; then
		display_alert "Using cached Home Assistant os-agent deb" "${HA_OS_AGENT_CACHE_FILE}" "info"
	else
		display_alert "Fetching Home Assistant os-agent deb" "${HA_OS_AGENT_URL}" "info"
		run_host_command_logged wget --progress=dot:giga --output-document="${HA_OS_AGENT_CACHE_FILE}" "${HA_OS_AGENT_URL}"
	fi
	if [[ -f "${HA_SUPERVISED_CACHE_FILE}" ]]; then
		display_alert "Using cached Home Assistant supervised deb" "${HA_SUPERVISED_CACHE_FILE}" "info"
	else
		display_alert "Fetching Home Assistant supervised deb" "${HA_SUPERVISED_URL}" "info"
		run_host_command_logged wget --progress=dot:giga --output-document="${HA_SUPERVISED_CACHE_FILE}" "${HA_SUPERVISED_URL}"
	fi

	display_alert "Adding Home Assistant debs to image" "${EXTENSION}" "info"
	run_host_command_logged mkdir -p "${SDCARD}"/opt/hainstall
	run_host_command_logged cp -pv "${HA_OS_AGENT_CACHE_FILE}" "${SDCARD}/opt/hainstall/${HA_OS_AGENT_FILENAME}"
	run_host_command_logged cp -pv "${HA_SUPERVISED_CACHE_FILE}" "${SDCARD}/opt/hainstall/${HA_SUPERVISED_FILENAME}"
	chroot_sdcard_apt_get_install "/opt/hainstall/${HA_OS_AGENT_FILENAME}"
	case "${ARCH}" in
		armhf)
			MACHINE=tinker
		;;
                amd64)
			MACHINE=generic-x86-64
		;;
		arm64)
			MACHINE=odroid-n2
                ;;
		*)
		exit_with_error "Home Assistant Supervised is not supported on ${ARCH} architecture"
		;;
	esac

	# hack os-release to say its Debian
	sed -i 's/^PRETTY_NAME=".*/PRETTY_NAME="Debian GNU\/Linux 12 (bookworm)"/g' "${SDCARD}/etc/os-release"

	# install HA supervised
	chroot_sdcard MACHINE=${MACHINE} dpkg -i "/opt/hainstall/${HA_SUPERVISED_FILENAME}"

	# workarounding supervisor loosing healthy state https://github.com/home-assistant/supervisor/issues/4381
	cat <<- SUPERVISOR_FIX > "${SDCARD}/usr/local/bin/supervisor_fix.sh"
	#!/bin/bash
	while true; do
		if ha supervisor info 2>&1 | grep -q "healthy: false"; then
			echo "Unhealthy detected, restarting" | systemd-cat -t $(basename "$0") -p debug
			systemctl restart hassio-supervisor.service
			sleep 600
		else
			sleep 5
		fi
	done
	SUPERVISOR_FIX

	# add executable bit
	run_host_command_logged chmod +x "${SDCARD}/usr/local/bin/supervisor_fix.sh"

	# generate service file to run this script
	cat <<- SUPERVISOR_FIX_SERVICE > "${SDCARD}/etc/systemd/system/supervisor-fix.service"
	[Unit]
	Description=Supervisor Unhealthy Fix

	[Service]
	StandardOutput=null
	StandardError=null
	ExecStart=/usr/local/bin/supervisor_fix.sh

	[Install]
	WantedBy=multi-user.target
	SUPERVISOR_FIX_SERVICE

	# enable service
	chroot_sdcard systemctl enable supervisor-fix

	cat <<- PROVISIONING > "${SDCARD}/root/provisioning.sh"
	#!/bin/bash
	trap 'rm -- "\$0"' EXIT
	sleep 5
	for s in {1..50};do
		for i in {0..100..10}; do
			j=\$i
			echo "\$i"
			sleep 2
		done
		if [[ -n "\$(ss | grep 8123)" ]]; then
				break;
		fi
	done | dialog --gauge "Preparing Home Assistant Supervised\n\nPlease wait! (can take 15 minutes) " 10 50 0
	if [[ \$? -eq 0 ]]; then
		if dialog --title " Reboot required " --yes-button "Reboot" --no-button "Cancel" --yesno \
		"A reboot is required to enable AppArmor. Shall we reboot now?" 7 68; then
		reboot
		fi
	else
		echo "Something went wrong. Check logs!"
	fi
	PROVISIONING

}

function pre_umount_final_image__xset_apparmor_in_armbianEnvTxt() {
	if [[ -f "${MOUNT}/boot/firmware/cmdline.txt" ]]; then
		# Rpi workaround
		sed -i '/./ s/$/ apparmor=1 security=apparmor/' "${MOUNT}/boot/firmware/cmdline.txt"
		display_alert "cmdline.txt contents" "${MOUNT}/boot/firmware/cmdline.txt" "info"
		run_host_command_logged cat "${MOUNT}/boot/firmware/cmdline.txt"
	elif [[ -f "${SDCARD}/boot/armbianEnv.txt" ]]; then
		echo "extraargs=${HA_UBOOT_EXTRAARGS}" >> "${SDCARD}/boot/armbianEnv.txt"
		display_alert "armbianEnv.txt contents" "${SDCARD}/boot/armbianEnv.txt" "info"
		run_host_command_logged cat "${SDCARD}/boot/armbianEnv.txt"
	elif [[ -f "${SDCARD}/boot/extlinux/extlinux.conf" ]]; then
		sed -i "/^[[:space:]]*append / s|\$| ${HA_UBOOT_EXTRAARGS}|" "${SDCARD}/boot/extlinux/extlinux.conf"
		display_alert "armbianEnv.txt contents" "${SDCARD}/boot/extlinux/extlinux.conf" "info"
		run_host_command_logged cat "${SDCARD}/boot/extlinux/extlinux.conf"
	else
		exit_with_error "cmdline.txt, armbianEnv.txt or extlinux.conf not found at ${SDCARD}/boot/"
	fi
}
