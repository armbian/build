#!/bin/sh
# Initialize the ALSA UCM profile for Xiaomi Pad 6S Pro (sm8550).
#
# The machine driver exposes a single sound card whose UCM config must be
# loaded to enable the speaker amplifiers (cs35l43 x4) and route the DSP
# mixer. alsaucm uses the card longname ("Xiaomi-Pad6SPro") to find the
# UCM configuration.
#
# This runs before user sessions start so that the speaker path is already
# enabled by the time PipeWire/WirePlumber create the ALSA sink.

set -e

# The UCM card identifier is the ALSA longname.
CARD_ALSA="XiaomiPad6SPro"
CARD_UCM="Xiaomi-Pad6SPro"

# Wait until sound card appears (up to ~10s)
i=0
until [ -d "/proc/asound/${CARD_ALSA}" ]; do
	i=$((i + 1))
	[ $i -ge 20 ] && break
	sleep 0.5
done

# Load the HiFi verb and enable the Speaker device (opens DSP mixer +
# enables all cs35l43 amps). Ignore failure if UCM is unavailable.
/usr/bin/alsaucm -c "$CARD_UCM" set _verb HiFi set _enadev Speaker || true

exit 0