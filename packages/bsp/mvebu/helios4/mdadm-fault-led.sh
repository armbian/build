#!/bin/bash
#
# Make Red Fault LED (LED2) reports mdadm error events.
#
EVENT=$1

# RED Fault LED trigger
# trigger none = LED not-blinking if LED on
# trigger timer = LED blinking if LED on
TRIGGER=/sys/class/leds/helios4\:red\:fault/trigger

# RED Fault LED brightness
# britghness 0 = LED off
# britghness 1 = LED on
BRIGHTNESS=/sys/class/leds/helios4\:red\:fault/brightness

# Active component device of an array has been marked as faulty OR A newly noticed array appears to be degraded.
if [[ $EVENT == "Fail" || $EVENT == "DegradedArray" ]]; then
	echo none > $TRIGGER
	echo 1 > $BRIGHTNESS
fi

# An md array started reconstruction
if [ $EVENT == "RebuildStarted" ]; then
	echo timer > $TRIGGER
	echo 1 > $BRIGHTNESS
fi

# An md array that was rebuilding, isn't any more, either because it finished normally or was aborted.
if [ $EVENT == "RebuildFinished" ]; then
	echo none > $TRIGGER
	echo 0 > $BRIGHTNESS
fi

# Test RED Fault LED
if [ $EVENT == "TestMessage" ]; then
	echo timer > $TRIGGER
	echo 1 > $BRIGHTNESS
	sleep 5
	echo 0 > $BRIGHTNESS
fi
