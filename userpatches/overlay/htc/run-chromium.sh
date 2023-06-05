#!/bin/bash

# The url to load in the browser. A default is used if it isn't specified.
DISPLAY_URL="${DISPLAY_URL:-http://192.168.0.230:3000/}"

# Load the browser in kiosk mode
chromium-browser --no-first-run --disable --disable-translate --disable-infobars --disable-suggestions-service --disable-save-password-bubble --start-maximized --kiosk --disable-session-crashed-bubble --incognito $DISPLAY_URL
