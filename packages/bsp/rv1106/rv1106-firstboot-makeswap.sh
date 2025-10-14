#!/usr/bin/env bash
set -euo pipefail

SWAPFILE="/swapfile"
SIZE_MB=256

echo "Creating swapfile of size ${SIZE_MB}MiB at ${SWAPFILE}"

# Safety: do not overwrite existing swapfile
if [[ -f "${SWAPFILE}" ]]; then
    echo "Swapfile ${SWAPFILE} already exists, not overwriting." >&2
    exit 1
fi

# Safety: ensure we have enough free space for the swapfile + headroom
FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
NEEDED_MB=$(( SIZE_MB + 64 ))  # 64MiB headroom
if (( FREE_MB < NEEDED_MB )); then
    echo "Not enough free space to create ${SIZE_MB}MiB swapfile." >&2
    exit 1
fi

# Create swapfile, set permissions, and enable it
fallocate -l "${SIZE_MB}M" "$SWAPFILE"
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
# Add to fstab if not present
if ! grep -qE '^[^#]*\s+/swapfile\s+swap\s' /etc/fstab; then
  echo "/swapfile swap swap defaults,nofail,pri=0 0 0" >> /etc/fstab
fi

swapon -p 0 "$SWAPFILE"

# Disable/mask the service after successful run
systemctl disable rv1106-firstboot-makeswap.service || true
systemctl mask rv1106-firstboot-makeswap.service || true
