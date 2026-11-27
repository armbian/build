#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Handles pre-installed kodi-gbm-rockchip.

function extension_prepare_config__kodi_gbm_rkmpp() {
	display_alert "Preparing extension" "${EXTENSION}" "info"

	# Force certain characteristics. CLI image, no desktop, no minimal.
	declare -g BUILD_MINIMAL="no"
	declare -g BUILD_DESKTOP="no"

	# This only works when RELEASE is either 'trixie' or 'forky'. exit_with_error will be triggered otherwise.
	if [[ "${RELEASE}" =~ ^(trixie|forky)$ ]]; then
		display_alert "kodi-gbm-rkmpp for ${RELEASE} release" "${EXTENSION}" "info"
	else
		exit_with_error "${EXTENSION} requires RELEASE to be either 'trixie' or 'forky'. Detected RELEASE: ${RELEASE}"
	fi

	# Pre-enable the panthor overlay.
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" == vendor ]]; then
		if [[ -n $DEFAULT_OVERLAYS ]]; then
			display_alert "Appending panthor-gpu to DEFAULT_OVERLAYS" "${EXTENSION}" "info"
			DEFAULT_OVERLAYS+=" panthor-gpu"
		else
			display_alert "Setting DEFAULT_OVERLAYS to panthor-gpu" "${EXTENSION}" "info"
			declare -g DEFAULT_OVERLAYS="panthor-gpu"
		fi
	else
		exit_with_error "${EXTENSION} requires rk35xx with vendor kernel. Detected LINUXFAMILY: ${LINUXFAMILY}, BRANCH: ${BRANCH}"
	fi

	EXTRA_IMAGE_SUFFIXES+=("-kodi") # global array
	return 0
}

function pre_customize_image__905_kodi_gbm_rkmpp() {
	display_alert "Adding kodi_gbm_rkmpp" "${EXTENSION}" "info"

	declare latest_release_version
	latest_release_version=$(curl -sL "https://api.github.com/repos/armsurvivors/kodi-rockchip-deb/releases/latest" | jq -r '.tag_name')

	declare deb_file down_url down_dir full_deb_path

	deb_file="kodi-rockchip-gbm_arm64_kodi_master_ffmpeg_81_${RELEASE}.deb"
	down_url="https://github.com/armsurvivors/kodi-rockchip-deb/releases/latest/download/${deb_file}"

	down_dir="${SRC}/cache/kodi-rockchip-deb"
	mkdir -p "${down_dir}"

	full_deb_path="${down_dir}/${latest_release_version}_${deb_file}"

	if [[ ! -f "${full_deb_path}" ]]; then
		display_alert "Will download ${full_deb_path} from latest release..." "${EXTENSION} ${K8S_MAJOR_MINOR}" "info"
		wget --progress=dot:mega --local-encoding=UTF-8 --output-document="${full_deb_path}.tmp" "${down_url}"
		mv -v "${full_deb_path}.tmp" "${full_deb_path}"
	fi

	cp -v "${full_deb_path}" "${SDCARD}/root/${deb_file}"
	chroot_sdcard_apt_get_install "/root/${deb_file}"
	rm -v "${SDCARD}/root/${deb_file}"

	return 0
}

# This is done directly, instead of with add_packages_to_image(), to avoid collisions with other extensions that may also add packages.
function pre_customize_image__900_extra_packages_late() {
	display_alert "Installing extra packages for kodi_gbm_rkmpp" "${EXTENSION}" "info"
	chroot_sdcard_apt_get_install "pulseaudio" "alsa-utils"
	chroot_sdcard_apt_get_install "ir-keytable" "evtest"
	chroot_sdcard_apt_get_install "snapclient" "snapserver" "avahi-daemon"
}

function pre_customize_image__920_config_kodi_gbm_rkmpp() {
	display_alert "Configuring kodi_gbm_rkmpp" "${EXTENSION}" "info"

	display_alert "Copying PulseAudio configuration for Kodi..." "${EXTENSION}" "info"
	cp -v "${SDCARD}/usr/local/share/pulse-kodi/system.pa" "${SDCARD}/etc/pulse/system.pa"

	display_alert "Enabling PulseAudio system-wide..." "${EXTENSION}" "info"
	systemctl --root="${SDCARD}" --no-reload enable pulseaudio

	display_alert "Enabling Kodi-Pulse service..." "${EXTENSION}" "info"
	systemctl --root="${SDCARD}" --no-reload enable kodi-pulse
}

# Extra: handle MCE remote control keymap.
function pre_customize_image__910_mce_keymap_kodi_gbm_rkmpp() {
	display_alert "Adding MCE remote control keymap" "${EXTENSION}" "info"

	# @TODO: this is all old+stupid, probably simply sed fix to toml keytable suffices
	display_alert "Adding MCE remote control keymap to /etc/rc_maps.cfg..." "${EXTENSION}" "info"
	sed -i '/^gpio_ir_recv/d' "${SDCARD}/etc/rc_maps.cfg"
	sed -i 's|^\(\*[[:space:]]*rc-rc6-mce[[:space:]].*\)|# \1|' "${SDCARD}/etc/rc_maps.cfg"
	echo 'gpio_ir_recv   rc-rc6-mce   rc6_mce_kodi' | tee -a "${SDCARD}/etc/rc_maps.cfg"
	display_alert "Resulting MCE remote control keymap entries in /etc/rc_maps.cfg:" "${EXTENSION}" "info"
	grep -i -e 'mce' -e 'rc6' "${SDCARD}/etc/rc_maps.cfg"

	display_alert "Adding MCE remote control keymap to /etc/rc_keymaps/rc6_mce_kodi..." "${EXTENSION}" "info"
	cat <<- MCE_KEYTABLE > "${SDCARD}/etc/rc_keymaps/rc6_mce_kodi"
		# table rc6_mce_kodi, type: RC6
		# Windows MCE keymap, tuned for Kodi.
		# Changes vs upstream rc-rc6-mce:
		#   0x800f0422  KEY_OK    -> KEY_ENTER
		#   0x800f0423  KEY_EXIT  -> KEY_BACKSPACE
		#   0x800f040d  KEY_MEDIA -> KEY_HOMEPAGE
		0x800f0400 KEY_NUMERIC_0
		0x800f0401 KEY_NUMERIC_1
		0x800f0402 KEY_NUMERIC_2
		0x800f0403 KEY_NUMERIC_3
		0x800f0404 KEY_NUMERIC_4
		0x800f0405 KEY_NUMERIC_5
		0x800f0406 KEY_NUMERIC_6
		0x800f0407 KEY_NUMERIC_7
		0x800f0408 KEY_NUMERIC_8
		0x800f0409 KEY_NUMERIC_9
		0x800f040a KEY_DELETE
		0x800f040b KEY_ENTER
		0x800f040c KEY_SLEEP
		0x800f040d KEY_HOMEPAGE
		0x800f040e KEY_MUTE
		0x800f040f KEY_INFO
		0x800f0410 KEY_VOLUMEUP
		0x800f0411 KEY_VOLUMEDOWN
		0x800f0412 KEY_CHANNELUP
		0x800f0413 KEY_CHANNELDOWN
		0x800f0414 KEY_FASTFORWARD
		0x800f0415 KEY_REWIND
		0x800f0416 KEY_PLAY
		0x800f0417 KEY_RECORD
		0x800f0418 KEY_PAUSE
		0x800f0419 KEY_STOP
		0x800f041a KEY_NEXT
		0x800f041b KEY_PREVIOUS
		0x800f041c KEY_NUMERIC_POUND
		0x800f041d KEY_NUMERIC_STAR
		0x800f041e KEY_UP
		0x800f041f KEY_DOWN
		0x800f0420 KEY_LEFT
		0x800f0421 KEY_RIGHT
		0x800f0422 KEY_ENTER
		0x800f0423 KEY_BACKSPACE
		0x800f0424 KEY_DVD
		0x800f0425 KEY_TUNER
		0x800f0426 KEY_EPG
		0x800f0427 KEY_ZOOM
		0x800f0432 KEY_MODE
		0x800f0433 KEY_PRESENTATION
		0x800f0434 KEY_EJECTCD
		0x800f043a KEY_BRIGHTNESSUP
		0x800f0446 KEY_TV
		0x800f0447 KEY_AUDIO
		0x800f0448 KEY_PVR
		0x800f0449 KEY_CAMERA
		0x800f044a KEY_VIDEO
		0x800f044c KEY_LANGUAGE
		0x800f044d KEY_TITLE
		0x800f044e KEY_PRINT
		0x800f0450 KEY_RADIO
		0x800f045a KEY_SUBTITLE
		0x800f045b KEY_RED
		0x800f045c KEY_GREEN
		0x800f045d KEY_YELLOW
		0x800f045e KEY_BLUE
		0x800f0465 KEY_POWER2
		0x800f0469 KEY_MESSENGER
		0x800f046e KEY_PLAYPAUSE
		0x800f046f KEY_PLAYER
		0x800f0480 KEY_BRIGHTNESSDOWN
		0x800f0481 KEY_PLAYPAUSE
	MCE_KEYTABLE

	return 0
}
