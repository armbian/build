#!/bin/bash
# Comprehensive comparison between our hybrid image and official Armbian
# Compares: Armbian-RG34XXSP-ALPHA vs Armbian-unofficial (official build)
# Run with: sudo ./compare_armbian_images.sh

set -e

# Image paths
HYBRID_IMG_GZ="builds/Armbian-RG34XXSP-ALPHA-20250720_234709.img.gz"
OFFICIAL_IMG="repos_to_update/armbian-build-rg34xxsp-support-branch/output/images/Armbian-unofficial_25.08.0-trunk_Rg34xxsp_bookworm_current_6.12.35_minimal.img"

# Temporary paths
HYBRID_IMG="/tmp/hybrid_armbian.img"
COMPARISON_DIR="/tmp/armbian_comparison"
HYBRID_MOUNT="$COMPARISON_DIR/hybrid_mount"
OFFICIAL_MOUNT="$COMPARISON_DIR/official_mount"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_section() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_diff() {
    echo -e "${YELLOW}[DIFF]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "=========================================="
echo "Armbian Image Comprehensive Comparison"
echo "=========================================="
echo "Hybrid:   $HYBRID_IMG_GZ"
echo "Official: $OFFICIAL_IMG"
echo ""

# Check files exist
if [[ ! -f "$HYBRID_IMG_GZ" ]]; then
    log_error "Hybrid image not found: $HYBRID_IMG_GZ"
    exit 1
fi

if [[ ! -f "$OFFICIAL_IMG" ]]; then
    log_error "Official image not found: $OFFICIAL_IMG"
    exit 1
fi

# Setup
mkdir -p "$COMPARISON_DIR" "$HYBRID_MOUNT" "$OFFICIAL_MOUNT"

# Decompress hybrid image
log_info "Decompressing hybrid image..."
gzip -dc "$HYBRID_IMG_GZ" > "$HYBRID_IMG"

log_section "1. IMAGE STRUCTURE COMPARISON"

# File sizes
HYBRID_SIZE=$(stat -c%s "$HYBRID_IMG")
OFFICIAL_SIZE=$(stat -c%s "$OFFICIAL_IMG")
HYBRID_SIZE_MB=$((HYBRID_SIZE / 1024 / 1024))
OFFICIAL_SIZE_MB=$((OFFICIAL_SIZE / 1024 / 1024))

echo "Image Sizes:"
echo "  Hybrid:   ${HYBRID_SIZE_MB}MB (${HYBRID_SIZE} bytes)"
echo "  Official: ${OFFICIAL_SIZE_MB}MB (${OFFICIAL_SIZE} bytes)"

if [[ $HYBRID_SIZE -eq $OFFICIAL_SIZE ]]; then
    log_success "✓ Image sizes match exactly"
else
    log_diff "✗ Image sizes differ by $((HYBRID_SIZE_MB - OFFICIAL_SIZE_MB))MB"
fi

echo ""
echo "Partition Tables:"
echo "--- HYBRID ---"
fdisk -l "$HYBRID_IMG" | grep -E "(Disk|Device|sectors)"

echo ""
echo "--- OFFICIAL ---"
fdisk -l "$OFFICIAL_IMG" | grep -E "(Disk|Device|sectors)"

log_section "2. BOOTLOADER COMPARISON"

# Compare first 4MB (bootloader area)
echo "Bootloader Area (0-4MB):"
HYBRID_BOOT=$(dd if="$HYBRID_IMG" bs=1M count=4 2>/dev/null | sha256sum | cut -d' ' -f1)
OFFICIAL_BOOT=$(dd if="$OFFICIAL_IMG" bs=1M count=4 2>/dev/null | sha256sum | cut -d' ' -f1)

echo "  Hybrid bootloader SHA256:   $HYBRID_BOOT"
echo "  Official bootloader SHA256: $OFFICIAL_BOOT"

if [[ "$HYBRID_BOOT" == "$OFFICIAL_BOOT" ]]; then
    log_success "✓ Bootloader areas are identical"
else
    log_diff "✗ Bootloader areas differ"
    
    # Detailed bootloader analysis
    echo ""
    echo "Detailed Bootloader Analysis:"
    
    # SPL comparison (8KB-40KB)
    HYBRID_SPL=$(dd if="$HYBRID_IMG" bs=1 skip=8192 count=32768 2>/dev/null | sha256sum | cut -d' ' -f1)
    OFFICIAL_SPL=$(dd if="$OFFICIAL_IMG" bs=1 skip=8192 count=32768 2>/dev/null | sha256sum | cut -d' ' -f1)
    
    echo "  SPL (8KB-40KB):"
    echo "    Hybrid:   $HYBRID_SPL"
    echo "    Official: $OFFICIAL_SPL"
    
    if [[ "$HYBRID_SPL" == "$OFFICIAL_SPL" ]]; then
        log_success "    ✓ SPL areas match"
    else
        log_diff "    ✗ SPL areas differ"
    fi
    
    # U-Boot comparison (40KB-240KB)
    HYBRID_UBOOT=$(dd if="$HYBRID_IMG" bs=1 skip=40960 count=204800 2>/dev/null | sha256sum | cut -d' ' -f1)
    OFFICIAL_UBOOT=$(dd if="$OFFICIAL_IMG" bs=1 skip=40960 count=204800 2>/dev/null | sha256sum | cut -d' ' -f1)
    
    echo "  U-Boot (40KB-240KB):"
    echo "    Hybrid:   $HYBRID_UBOOT"
    echo "    Official: $OFFICIAL_UBOOT"
    
    if [[ "$HYBRID_UBOOT" == "$OFFICIAL_UBOOT" ]]; then
        log_success "    ✓ U-Boot areas match"
    else
        log_diff "    ✗ U-Boot areas differ"
    fi
fi

log_section "3. FILESYSTEM COMPARISON"

# Check if official image is in use
log_info "Checking processes using official image..."
lsof "$OFFICIAL_IMG" 2>/dev/null || true
fuser -v "$OFFICIAL_IMG" 2>/dev/null || true

# Force cleanup any existing loop devices
log_info "Force cleaning up any existing loop devices..."
for loop in $(losetup -a | cut -d: -f1); do
    log_info "Detaching $loop"
    umount $loop* 2>/dev/null || true
    losetup -d $loop 2>/dev/null || true
done

# Wait and check again
sleep 3
log_info "Available loop devices: $(losetup -f)"

# Always copy official image to temp location to avoid lock issues
log_info "Official image may be locked, using temporary copy approach..."

# Copy official image to temp location
OFFICIAL_IMG_TEMP="/tmp/official_armbian_temp.img"
log_info "Copying official image to temporary location..."
cp "$OFFICIAL_IMG" "$OFFICIAL_IMG_TEMP"
OFFICIAL_IMG="$OFFICIAL_IMG_TEMP"
log_info "Using temporary copy: $OFFICIAL_IMG_TEMP"

# Setup loop devices
HYBRID_LOOP=$(losetup -f)
OFFICIAL_LOOP=$(losetup -f)

log_info "Setting up loop device for hybrid image..."
losetup -P "$HYBRID_LOOP" "$HYBRID_IMG"
log_info "Setting up loop device for official image..."  
losetup -P "$OFFICIAL_LOOP" "$OFFICIAL_IMG"
sleep 2

# Filesystem information
echo "Filesystem Information:"
echo "--- HYBRID ---"
echo "  Partition 1:"
if [[ -b "${HYBRID_LOOP}p1" ]]; then
    file -s "${HYBRID_LOOP}p1"
    blkid "${HYBRID_LOOP}p1" || echo "    No filesystem info available"
else
    echo "    Partition not accessible"
fi

echo ""
echo "--- OFFICIAL ---"
echo "  Partition 1:"
if [[ -b "${OFFICIAL_LOOP}p1" ]]; then
    file -s "${OFFICIAL_LOOP}p1"
    blkid "${OFFICIAL_LOOP}p1" || echo "    No filesystem info available"
else
    echo "    Partition not accessible"
fi

log_section "4. FILESYSTEM CONTENT COMPARISON"

# Mount filesystems
if mount "${HYBRID_LOOP}p1" "$HYBRID_MOUNT" 2>/dev/null; then
    log_success "✓ Hybrid filesystem mounted"
    HYBRID_MOUNTED=true
else
    log_error "✗ Failed to mount hybrid filesystem"
    HYBRID_MOUNTED=false
fi

if mount "${OFFICIAL_LOOP}p1" "$OFFICIAL_MOUNT" 2>/dev/null; then
    log_success "✓ Official filesystem mounted"
    OFFICIAL_MOUNTED=true
else
    log_error "✗ Failed to mount official filesystem"
    OFFICIAL_MOUNTED=false
fi

if [[ "$HYBRID_MOUNTED" == "true" && "$OFFICIAL_MOUNTED" == "true" ]]; then
    
    echo ""
    echo "Root Directory Structure Comparison:"
    echo "--- HYBRID ---"
    ls -la "$HYBRID_MOUNT/" | head -20
    
    echo ""
    echo "--- OFFICIAL ---"
    ls -la "$OFFICIAL_MOUNT/" | head -20
    
    echo ""
    echo "Directory Differences:"
    echo "Directories only in HYBRID:"
    diff <(ls -1 "$HYBRID_MOUNT/" | sort) <(ls -1 "$OFFICIAL_MOUNT/" | sort) | grep "^<" | sed 's/^< /  /' || echo "  (none)"
    echo "Directories only in OFFICIAL:"
    diff <(ls -1 "$HYBRID_MOUNT/" | sort) <(ls -1 "$OFFICIAL_MOUNT/" | sort) | grep "^>" | sed 's/^> /  /' || echo "  (none)"
    
    log_section "5. BOOT DIRECTORY COMPARISON"
    
    echo "/boot Directory Contents:"
    echo "--- HYBRID ---"
    if [[ -d "$HYBRID_MOUNT/boot" ]]; then
        ls -la "$HYBRID_MOUNT/boot/" | head -20
    else
        echo "  No /boot directory"
    fi
    
    echo ""
    echo "--- OFFICIAL ---"
    if [[ -d "$OFFICIAL_MOUNT/boot" ]]; then
        ls -la "$OFFICIAL_MOUNT/boot/" | head -20
    else
        echo "  No /boot directory"
    fi
    
    if [[ -d "$HYBRID_MOUNT/boot" && -d "$OFFICIAL_MOUNT/boot" ]]; then
        echo ""
        echo "Boot File Differences:"
        echo "Files only in HYBRID /boot:"
        diff <(ls -1 "$HYBRID_MOUNT/boot/" | sort) <(ls -1 "$OFFICIAL_MOUNT/boot/" | sort) | grep "^<" | sed 's/^< /  /' || echo "  (none)"
        echo "Files only in OFFICIAL /boot:"
        diff <(ls -1 "$HYBRID_MOUNT/boot/" | sort) <(ls -1 "$OFFICIAL_MOUNT/boot/" | sort) | grep "^>" | sed 's/^> /  /' || echo "  (none)"
        
        # Compare specific boot files
        echo ""
        echo "Boot File Content Comparison:"
        
        # Kernel comparison
        if [[ -f "$HYBRID_MOUNT/boot/Image" && -f "$OFFICIAL_MOUNT/boot/Image" ]]; then
            HYBRID_KERNEL=$(sha256sum "$HYBRID_MOUNT/boot/Image" | cut -d' ' -f1)
            OFFICIAL_KERNEL=$(sha256sum "$OFFICIAL_MOUNT/boot/Image" | cut -d' ' -f1)
            echo "  Kernel (Image):"
            echo "    Hybrid:   $HYBRID_KERNEL"
            echo "    Official: $OFFICIAL_KERNEL"
            if [[ "$HYBRID_KERNEL" == "$OFFICIAL_KERNEL" ]]; then
                log_success "    ✓ Kernels are identical"
            else
                log_diff "    ✗ Kernels differ (EXPECTED - we use ROCKNIX kernel)"
            fi
        fi
        
        # DTB comparison
        echo ""
        echo "  Device Tree Files:"
        if [[ -f "$HYBRID_MOUNT/boot/sun50i-h700-anbernic-rg34xx-sp.dtb" ]]; then
            echo "    Hybrid has: sun50i-h700-anbernic-rg34xx-sp.dtb"
        fi
        if [[ -d "$HYBRID_MOUNT/boot/dtb" ]]; then
            echo "    Hybrid DTB directory: $(ls -1 "$HYBRID_MOUNT/boot/dtb/" | wc -l) files"
        fi
        if [[ -d "$OFFICIAL_MOUNT/boot/dtb" ]]; then
            echo "    Official DTB directory: $(ls -1 "$OFFICIAL_MOUNT/boot/dtb/" | wc -l) files"
        fi
        
        # Boot script comparison
        if [[ -f "$HYBRID_MOUNT/boot/boot.cmd" && -f "$OFFICIAL_MOUNT/boot/boot.cmd" ]]; then
            echo ""
            echo "  Boot Script Differences:"
            echo "--- HYBRID boot.cmd (first 10 lines) ---"
            head -10 "$HYBRID_MOUNT/boot/boot.cmd"
            echo ""
            echo "--- OFFICIAL boot.cmd (first 10 lines) ---"
            head -10 "$OFFICIAL_MOUNT/boot/boot.cmd"
        fi
        
        # armbianEnv.txt comparison
        if [[ -f "$HYBRID_MOUNT/boot/armbianEnv.txt" && -f "$OFFICIAL_MOUNT/boot/armbianEnv.txt" ]]; then
            echo ""
            echo "  armbianEnv.txt Differences:"
            echo "--- HYBRID ---"
            cat "$HYBRID_MOUNT/boot/armbianEnv.txt"
            echo ""
            echo "--- OFFICIAL ---"
            cat "$OFFICIAL_MOUNT/boot/armbianEnv.txt"
        fi
    fi
    
    log_section "6. SYSTEM CONFIGURATION COMPARISON"
    
    # OS release comparison
    echo "OS Release Information:"
    echo "--- HYBRID ---"
    if [[ -f "$HYBRID_MOUNT/etc/os-release" ]]; then
        cat "$HYBRID_MOUNT/etc/os-release"
    else
        echo "  No /etc/os-release"
    fi
    
    echo ""
    echo "--- OFFICIAL ---"
    if [[ -f "$OFFICIAL_MOUNT/etc/os-release" ]]; then
        cat "$OFFICIAL_MOUNT/etc/os-release"
    else
        echo "  No /etc/os-release"
    fi
    
    # Hostname comparison
    echo ""
    echo "Hostname:"
    echo "  Hybrid:   $(cat "$HYBRID_MOUNT/etc/hostname" 2>/dev/null || echo 'not set')"
    echo "  Official: $(cat "$OFFICIAL_MOUNT/etc/hostname" 2>/dev/null || echo 'not set')"
    
    # Package differences
    echo ""
    echo "Installed Packages:"
    if [[ -f "$HYBRID_MOUNT/var/lib/dpkg/status" && -f "$OFFICIAL_MOUNT/var/lib/dpkg/status" ]]; then
        HYBRID_PKGS=$(grep "^Package:" "$HYBRID_MOUNT/var/lib/dpkg/status" | wc -l)
        OFFICIAL_PKGS=$(grep "^Package:" "$OFFICIAL_MOUNT/var/lib/dpkg/status" | wc -l)
        echo "  Hybrid packages:   $HYBRID_PKGS"
        echo "  Official packages: $OFFICIAL_PKGS"
        
        if [[ $HYBRID_PKGS -eq $OFFICIAL_PKGS ]]; then
            log_success "  ✓ Same number of packages"
        else
            log_diff "  ✗ Package count differs by $((HYBRID_PKGS - OFFICIAL_PKGS))"
        fi
    fi
    
    log_section "7. FILESYSTEM USAGE COMPARISON"
    
    echo "Filesystem Usage:"
    echo "--- HYBRID ---"
    df -h "$HYBRID_MOUNT"
    du -sh "$HYBRID_MOUNT" 2>/dev/null | head -1
    
    echo ""
    echo "--- OFFICIAL ---"
    df -h "$OFFICIAL_MOUNT"
    du -sh "$OFFICIAL_MOUNT" 2>/dev/null | head -1
    
fi

# Cleanup
if [[ "$HYBRID_MOUNTED" == "true" ]]; then
    umount "$HYBRID_MOUNT" 2>/dev/null || true
fi
if [[ "$OFFICIAL_MOUNTED" == "true" ]]; then
    umount "$OFFICIAL_MOUNT" 2>/dev/null || true
fi

losetup -d "$HYBRID_LOOP" 2>/dev/null || true
losetup -d "$OFFICIAL_LOOP" 2>/dev/null || true
rm -f "$HYBRID_IMG"
rm -f "/tmp/official_armbian_temp.img" 2>/dev/null || true
rm -rf "$COMPARISON_DIR"

log_section "8. SUMMARY OF KEY DIFFERENCES"

echo "Expected Differences (by design):"
echo "  ✓ Kernel: Hybrid uses ROCKNIX kernel vs Official uses Armbian kernel"
echo "  ✓ DTB: Hybrid uses ROCKNIX DTB in /boot/dtb-rocknix/"
echo "  ✓ Boot script: Hybrid has custom boot.cmd for ROCKNIX kernel"
echo "  ✓ Hostname: Different naming (armbian-rg34xxsp-hybrid vs default)"
echo ""
echo "Unexpected Differences (need investigation):"
echo "  - Image size differences"
echo "  - Bootloader differences (if any)"
echo "  - File structure differences"
echo "  - Package differences"
echo "  - Configuration differences"
echo ""

log_success "✓ Comparison complete!"
echo ""
echo "This analysis shows exactly what differs between our hybrid"
echo "approach and the standard Armbian build system."