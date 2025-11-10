#!/bin/bash
# Format and rename partitions in the latest Armbian image
# Layout:
#   p1 = boot
#   p2 = recovery
#   p3 = rootfs
#   p4 = userdata

set -e

IMG_DIR="/build/os-boy/new-build/build/output/images"

# Find the newest .img file
IMG=$(ls -1t "$IMG_DIR"/*.img 2>/dev/null | head -n1)
if [ -z "$IMG" ]; then
    echo "❌ No image file found in $IMG_DIR"
    exit 1
fi

echo "[🌱] Found image: $IMG"
echo "[🌱] Setting up loop device..."

# Create loop device with partition mappings
LOOP=$(losetup -fP --show "$IMG")
echo "→ Using $LOOP"
sleep 1

# --- Format partitions ---
if [ -b "${LOOP}p2" ]; then
    echo "[🪄] Formatting ${LOOP}p2 as ext4 (recovery)"
    mkfs.ext4 -F -L recovery "${LOOP}p2"
else
    echo "⚠️  Partition 2 not found (skipped)"
fi

if [ -b "${LOOP}p4" ]; then
    echo "[🪄] Formatting ${LOOP}p4 as ext4 (userdata)"
    mkfs.ext4 -F -L userdata "${LOOP}p4"
else
    echo "⚠️  Partition 4 not found (skipped)"
fi

# --- Rename all partition labels for consistency ---
echo "[✏️] Renaming partition labels..."

if [ -b "${LOOP}p1" ]; then
    e2label "${LOOP}p1" boot || true
fi
if [ -b "${LOOP}p2" ]; then
    e2label "${LOOP}p2" recovery || true
fi
if [ -b "${LOOP}p3" ]; then
    e2label "${LOOP}p3" rootfs || true
fi
if [ -b "${LOOP}p4" ]; then
    e2label "${LOOP}p4" userdata || true
fi

# Force kernel to re-read partition info
sync
partprobe "$LOOP"
sleep 1

# --- Verify labels ---
echo "[🔍] Partition labels after rename:"
lsblk "$LOOP" -o NAME,LABEL,SIZE,TYPE

# --- Cleanup ---
sync
echo "[🌿] Detaching loop device..."
losetup -d "$LOOP"

echo "[✅] Format and label complete: $IMG"

