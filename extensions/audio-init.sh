#!/bin/bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Some boards needs special audio initialization
# To use, enable_extension audio-init, and set AUDIO_INIT_SCRIPT_CONTENT

function extension_prepare_config__audio_init() {
    display_alert "Extension: ${EXTENSION}: ${BOARD}" "initializing config" "info"
}

# Add necessary audio packages to the image
function post_family_config__audio_init_add_audio_packages() {
    display_alert "Extension: ${EXTENSION}: ${BOARD}" "adding audio packages to image" "info"
    # Install essential audio packages instead of non-existent "audio" package
    add_packages_to_image alsa-utils pulseaudio bluez bluez-tools
}

# Deploy the script and the systemd service in the BSP
function post_family_tweaks_bsp__audio_init_add_systemd_service() {
    display_alert "Extension: ${EXTENSION}: ${BOARD}" "adding audio init service to BSP" "info"
    : "${destination:?destination is not set}"

    declare script_dir="/usr/local/sbin"
    run_host_command_logged mkdir -pv "${destination}${script_dir}"
    declare script_path="${script_dir}/audio-init.sh"

    # Create audio initialization script with custom content
    cat <<- AUDIO_INIT_SCRIPT > "${destination}${script_path}"
        #!/bin/bash
        # Wait for audio devices to initialize
        sleep 2

        # Set ALSA controls
        amixer -c rockchipes8388 set 'OUT1 Switch' on || true
        amixer -c rockchipes8388 set 'OUT2 Switch' on || true
        amixer -c rockchipes8388 set 'Speaker Switch' on || true
        amixer -c rockchipes8388 set 'PCM Volume' 255,255 || true

        # Restore ALSA state if available
        if [ -f /var/lib/alsa/asound.state ]; then
            alsactl -f /var/lib/alsa/asound.state restore || true
        else
            alsactl store || true
        fi

        # Set default PulseAudio sink
        pactl set-default-sink alsa_output.platform-rockchipes8388.stereo-speakers || true

        # Ensure PulseAudio service applies changes
        systemctl --user restart pulseaudio.service || true
AUDIO_INIT_SCRIPT
    run_host_command_logged chmod -v +x "${destination}${script_path}" # Make it executable

    # Create systemd service file
    cat <<- AUDIO_INIT_SYSTEMD_SERVICE > "$destination"/lib/systemd/system/audio-init.service
        [Unit]
        Description=${BOARD} Audio Initialization
        After=sound.target systemd-user-sessions.service
        Before=pulseaudio.service

        [Service]
        Type=oneshot
        ExecStart=${script_path}

        [Install]
        WantedBy=multi-user.target
AUDIO_INIT_SYSTEMD_SERVICE

    return 0
}

# Enable the service in the image
function post_family_tweaks__audio_init_enable_service_in_image() {
    display_alert "Extension: ${EXTENSION}: ${BOARD}" "enabling audio init service in the image" "info"
    chroot_sdcard systemctl --no-reload enable "audio-init.service"
    return 0
}
