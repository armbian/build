#!/bin/bash
# Description: This script install Lighthouse latest version from official binary.

echo -e "\nBegining of the script: Installing Lighthouse - latest version"

# Check current lighthouse version
LIGHTHOUSE_LATEST=$(curl -s https://api.github.com/repos/sigp/lighthouse/releases/latest | jq -r .tag_name)

echo "Lighthouse latest version is $LIGHTHOUSE_LATEST."

# Check for required privileges
if [ "$EUID" -ne 0 ]; then
	echo -e "\nRoot privileges are required. Re-run with sudo"
	exit 1
fi

# Install Lighthouse
echo -e "\nDownloading latest version..."
curl -LO https://github.com/sigp/lighthouse/releases/download/${LIGHTHOUSE_LATEST}/lighthouse-${LIGHTHOUSE_LATEST}-aarch64-unknown-linux-gnu.tar.gz
tar -xvf lighthouse-${LIGHTHOUSE_LATEST}-aarch64-unknown-linux-gnu.tar.gz
mv ./lighthouse /usr/bin/lighthouse
rm -f lighthouse-${LIGHTHOUSE_LATEST}-aarch64-unknown-linux-gnu.tar.gz lighthouse-${LIGHTHOUSE_LATEST}

# Check if update was successful
LIGHTHOUSE_CURRENT=$(lighthouse --version | grep -o 'v[0-9.]*')

echo -e "\nLighthouse installed succesfully (version: $LIGHTHOUSE_CURRENT)."
exit 0
