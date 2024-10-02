# Allwinner H6 quad core 2GB RAM SoC GBE USB3
BOARD_NAME="Orange Pi 3 LTS"
BOARDFAMILY="sun50iw6"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_3_lts_defconfig"
BOOT_LOGO="desktop"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="orangepi_3_lts_defconfig"

enable_extension "uwe5622-allwinner"

function post_family_config__opi3lts_set_asoundstate_file() {
	declare -g ASOUND_STATE='asound.state.sun50iw6-current'
}

function post_family_tweaks__opi3lts_configure_pulse_audio() {
	if [[ $BUILD_DESKTOP == yes ]]; then
		sed -i "s/auto-profiles = yes/auto-profiles = no/" ${SDCARD}/usr/share/pulseaudio/alsa-mixer/profile-sets/default.conf
		echo "load-module module-alsa-sink device=hw:0,0 sink_name=AudioCodec-Playback sink_properties=\"device.description='Audio Codec'\"" >> ${SDCARD}/etc/pulse/default.pa
		echo "load-module module-alsa-sink device=hw:1,0 sink_name=HDMI-Playback sink_properties=\"device.description='HDMI Audio'\"" >> ${SDCARD}/etc/pulse/default.pa
	fi
}
