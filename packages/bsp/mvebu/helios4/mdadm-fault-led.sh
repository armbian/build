#!/bin/sh
#
# Make Red Fault LED (LED2) reports mdadm error events.
#
# Invoked by `mdadm --monitor --program=...` with positional args:
#   $1 = event name (Fail, DegradedArray, RebuildStarted, RebuildFinished,
#        NewArray, TestMessage, ...)
#   $2 = md device, e.g. /dev/md0
#   $3 = component device (only set for some events, e.g. Fail)
#
EVENT=$1
ARRAY=$2

# RED Fault LED trigger
# trigger none = LED not-blinking if LED on
# trigger timer = LED blinking if LED on
TRIGGER=/sys/class/leds/helios4:red:fault/trigger

# RED Fault LED brightness
# brightness 0 = LED off
# brightness 1 = LED on
BRIGHTNESS=/sys/class/leds/helios4:red:fault/brightness

case "$EVENT" in
	Fail | DegradedArray)
		# Component marked faulty, or a newly noticed array is degraded.
		echo none > "$TRIGGER"
		echo 1 > "$BRIGHTNESS"
		;;
	NewArray)
		# Cold-boot path: mdadm --monitor emits NewArray (not DegradedArray)
		# for arrays seen for the first time after startup, even if they are
		# already degraded. Probe state explicitly so the LED comes up at
		# boot when a disk died while the system was off.
		[ -n "$ARRAY" ] || exit 0
		STATE=$(mdadm --detail "$ARRAY" 2> /dev/null | awk -F: '/^[[:space:]]*State[[:space:]]*:/ {sub(/^ /,"",$2); print $2; exit}')
		case "$STATE" in
			*degraded* | *FAILED* | *failed*)
				echo none > "$TRIGGER"
				echo 1 > "$BRIGHTNESS"
				;;
		esac
		;;
	RebuildStarted)
		# An md array started reconstruction.
		echo timer > "$TRIGGER"
		echo 1 > "$BRIGHTNESS"
		;;
	RebuildFinished)
		# An md array that was rebuilding isn't any more, either because
		# it finished normally or was aborted.
		echo none > "$TRIGGER"
		echo 0 > "$BRIGHTNESS"
		;;
	TestMessage)
		# Smoke-test the LED.
		echo timer > "$TRIGGER"
		echo 1 > "$BRIGHTNESS"
		sleep 5
		echo 0 > "$BRIGHTNESS"
		;;
esac
