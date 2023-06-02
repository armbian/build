#!/bin/bash

# The tokens to ensure xdotool will run against the X Server
export DISPLAY=:0.0
export XAUTHORITY=/usr/local/bin/HtcDisplay/.Xauthority

# If it can find a chormium window then it will refresh it
xdotool search --onlyvisible --class chromium-browser windowactivate key ctrl+r
