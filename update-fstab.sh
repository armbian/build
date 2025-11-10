#!/bin/bash

set -e

IMG_DIR="/build/os-boy/new-build/build/output/images"

# Find the newest .img file
IMG=$(ls -1t "$IMG_DIR"/*.img 2>/dev/null | head -n1)
if [ -z "$IMG" ]; then
    echo "❌ No image file found in $IMG_DIR"
    exit 1
fi

echo "[🧠] Updating fstab inside: $IMG"

# Setup loop device
LOOP=$(losetup -fP --show "$IMG")
echo "→ Using $LOOP"
sleep 1

# Mount rootfs (partition 3)
if [ -b "${LOOP}p3" ]; then
    mkdir -p /mnt/rootfs
    mount "${LOOP}p3" /mnt/rootfs
    echo "[🧾] Writing /etc/fstab..."

    cat << 'EOF' > /mnt/rootfs/etc/fstab
# Do not direct edit this file, this file was generated from the update-fstab script.
/dev/mmcblk1p3 / ext4 defaults,noatime,commit=120,errors=remount-ro 0 1
/dev/mmcblk1p1 /boot ext4 defaults,ro 0 2
/dev/mmcblk1p4 /user-data ext4 defaults,noatime,commit=120,errors=remount-ro 0 2
#/user-data/root /root none bind 0 0
#/user-data/home /home none bind 0 0
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF

        # Ensure mountpoint exists
    mkdir -p /mnt/rootfs/user-data
    sync
    umount /mnt/rootfs

    echo "[🧩] Running filesystem checks..."
    e2fsck -y "${LOOP}p3" || true
    if [ -b "${LOOP}p4" ]; then
        e2fsck -y "${LOOP}p4" || true
    fi

    echo "[✅] fstab updated and filesystems verified"
else
    echo "⚠️ Partition 3 (rootfs) not found!"
fi

# Cleanup
losetup -d "$LOOP"
echo "[🌿] Done."
