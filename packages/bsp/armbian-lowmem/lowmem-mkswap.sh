#!/usr/bin/env bash
set -euo pipefail

SWAPFILE_PATH="/swapfile"
SWAPFILE_SIZE_MB=256

[[ -f /etc/default/armbian-lowmem ]] && . /etc/default/armbian-lowmem

echo "Creating swapfile of size ${SWAPFILE_SIZE_MB}MiB at ${SWAPFILE_PATH}"

# Safety: do not overwrite existing swapfile
if [[ -f "${SWAPFILE_PATH}" ]]; then
    echo "Swapfile ${SWAPFILE_PATH} already exists, not overwriting." >&2
    exit 0
fi

# Safety: ensure we have enough free space for the swapfile + headroom
SWAPFILE_BASE=$(dirname "${SWAPFILE_PATH}")
FREE_MB=$(df -Pm "${SWAPFILE_BASE}" | awk 'NR==2{print $4}')
NEEDED_MB=$(( SWAPFILE_SIZE_MB + 64 ))  # 64MiB headroom
if (( FREE_MB < NEEDED_MB )); then
    echo "Not enough free space in ${SWAPFILE_BASE} to create ${SWAPFILE_SIZE_MB}MiB swapfile." >&2
    exit 1
fi

# Create swapfile, set permissions, and enable it
fallocate -l "${SWAPFILE_SIZE_MB}M" "${SWAPFILE_PATH}"
chmod 600 "${SWAPFILE_PATH}"
mkswap "${SWAPFILE_PATH}"
# Add to fstab if not present
if ! grep -qE "^[[:space:]]+${SWAPFILE_PATH}[[:space:]]+swap[[:space:]]" /etc/fstab; then
  echo "${SWAPFILE_PATH} swap swap defaults,nofail,discard=once,pri=0 0 0" >> /etc/fstab
fi

swapon -p 0 "${SWAPFILE_PATH}"
