#!/bin/bash
set -e

IMG_DIR="/build/os-boy/new-build/build/output/images"
DATA_TAR="/build/os-boy/user-data.tar.gz"
MNT_DIR="/mnt/userdata"

# --- Step 1 – find latest image file ---
IMG_FILE=$(ls -t "${IMG_DIR}"/*.img "${IMG_DIR}"/*.raw 2>/dev/null | head -n 1)
if [[ -z "$IMG_FILE" ]]; then
    echo "[ERROR] No image found in ${IMG_DIR}"
    exit 1
fi
echo "[+] Found image: $IMG_FILE"

# --- Step 2 – setup loop device ---
LOOP=$(losetup -f --show -P "$IMG_FILE")
echo "[+] Loop device attached: $LOOP"

# --- Step 3 – identify userdata partition (p4) ---
PART="${LOOP}p4"
if [[ ! -b "$PART" ]]; then
    echo "[ERROR] ${PART} not found — check partition layout."
    losetup -d "$LOOP"
    exit 1
fi

# --- Step 4 – ensure filesystem exists (format if needed) ---
FS_TYPE=$(blkid -o value -s TYPE "$PART" || true)
if [[ -z "$FS_TYPE" ]]; then
    echo "[+] No filesystem detected on $PART — formatting as ext4 (label=userdata)..."
    mkfs.ext4 -L userdata "$PART"
else
    echo "[+] Detected existing filesystem ($FS_TYPE) on $PART"
fi

# --- Step 5 – mount and copy file ---
mkdir -p "$MNT_DIR"
echo "[+] Mounting ${PART}..."
mount "$PART" "$MNT_DIR"

FREE_SPACE=$(df -m --output=avail "$MNT_DIR" | tail -n 1)
FILE_SIZE=$(du -m "$DATA_TAR" | cut -f1)
if (( FREE_SPACE < FILE_SIZE + 50 )); then
    echo "[WARNING] Low space: only ${FREE_SPACE} MB available, file is ${FILE_SIZE} MB"
fi

DEST_PATH="$MNT_DIR/user-data.tar.gz"
echo "[+] Copying ${DATA_TAR} → ${DEST_PATH}"
cp "$DATA_TAR" "$DEST_PATH"

sync
echo "[+] File copied successfully to userdata partition."

# --- Step 6 – cleanup ---
echo "[+] Unmounting and detaching loop..."
umount "$MNT_DIR"
losetup -d "$LOOP"
rmdir "$MNT_DIR"

echo "[✓] Done. user-data.tar.gz injected into partition 4 (/userdata) successfully!"

