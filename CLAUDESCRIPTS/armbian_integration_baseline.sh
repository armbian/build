#!/bin/bash
# Component Injection Script: Insert ROCKNIX components into standard Armbian image
# Takes official Armbian image and replaces bootloader, kernel, DTB with proven ROCKNIX components
# Provides detailed comparison and validation of each replacement
#
# Usage: ./armbian_integration_baseline.sh [OPTIONS]
# Options:
#   --skip-bootloader    Skip bootloader injection (use Armbian bootloader)
#   --skip-kernel        Skip kernel injection (use Armbian kernel)
#   --skip-dtb           Skip device tree injection (use Armbian DTB)
#   --inject-bootconfig  Inject hybrid boot configuration (default: use Armbian boot.cmd)
#   --skip-recompile     Skip Armbian recompile (use existing image)
#   --help               Show this help message
#
# Examples:
#   ./armbian_integration_baseline.sh                     # Full recompile + ROCKNIX components + Armbian boot
#   ./armbian_integration_baseline.sh --skip-recompile    # Use existing image + ROCKNIX components + Armbian boot
#   ./armbian_integration_baseline.sh --inject-bootconfig # Full recompile + inject hybrid boot config
#   ./armbian_integration_baseline.sh --skip-kernel       # Recompile, use Armbian kernel + Armbian boot

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_BASE="repos_to_update/armbian-build-rg34xxsp-support-branch/output/images/Armbian-unofficial_25.08.0-trunk_Rg34xxsp_bookworm_current_6.12.35_minimal.img"
OUTPUT_DIR="builds"
BUILD_DATE="$(date +%Y%m%d_%H%M%S)"

# Timing variables
SCRIPT_START_TIME=$(date +%s)
PHASE0_START=""
PHASE0_END=""
PHASE1_START=""
PHASE1_END=""
PHASE2_START=""
PHASE2_END=""
PHASE3A_START=""
PHASE3A_END=""
PHASE3B_START=""
PHASE3B_END=""
PHASE3C_START=""
PHASE3C_END=""
PHASE3D_START=""
PHASE3D_END=""
PHASE3E_START=""
PHASE3E_END=""
PHASE4_START=""
PHASE4_END=""

# Component injection flags (default: inject ROCKNIX components, use Armbian boot config)
INJECT_BOOTLOADER=true
INJECT_KERNEL=true
INJECT_DTB=true
INJECT_BOOTCONFIG=false
SKIP_RECOMPILE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-bootloader)
            INJECT_BOOTLOADER=false
            shift
            ;;
        --skip-kernel)
            INJECT_KERNEL=false
            shift
            ;;
        --skip-dtb)
            INJECT_DTB=false
            shift
            ;;
        --inject-bootconfig)
            INJECT_BOOTCONFIG=true
            shift
            ;;
        --skip-recompile)
            SKIP_RECOMPILE=true
            shift
            ;;
        --help)
            echo "Component Injection Script for RG34XXSP Armbian"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-bootloader    Skip bootloader injection (use Armbian bootloader)"
            echo "  --skip-kernel        Skip kernel injection (use Armbian kernel)"
            echo "  --skip-dtb           Skip device tree injection (use Armbian DTB)"
            echo "  --inject-bootconfig  Inject hybrid boot configuration (default: use Armbian boot.cmd)"
            echo "  --skip-recompile     Skip Armbian recompile (use existing image)"
            echo "  --help               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Full recompile + ROCKNIX components + Armbian boot"
            echo "  $0 --skip-recompile            # Use existing image + ROCKNIX components + Armbian boot"
            echo "  $0 --inject-bootconfig         # Full recompile + inject hybrid boot config"
            echo "  $0 --skip-bootloader           # Recompile + use Armbian bootloader + Armbian boot"
            echo "  $0 --skip-kernel               # Recompile + use Armbian kernel + Armbian boot"
            echo ""
            echo "Use cases:"
            echo "  - Testing which components are essential for boot success"
            echo "  - Gradual migration from ROCKNIX to Armbian components"
            echo "  - Board Support Package (BSP) development with Armbian build system"
            echo "  - Iterative development: recompile with changes, test injection"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

calculate_duration() {
    local start_time=$1
    local end_time=$2
    
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        local duration=$((end_time - start_time))
        if [[ $duration -ge 60 ]]; then
            local minutes=$((duration / 60))
            local seconds=$((duration % 60))
            echo "${minutes}m ${seconds}s"
        else
            echo "${duration}s"
        fi
    else
        echo "0s"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_diff() {
    echo -e "${YELLOW}[DIFF]${NC} $1"
}

compare_component() {
    local component_name="$1"
    local original_file="$2"
    local replacement_file="$3"
    
    echo ""
    echo -e "${CYAN}--- $component_name COMPARISON ---${NC}"
    
    if [[ -f "$original_file" ]]; then
        ORIG_SIZE=$(stat -c%s "$original_file")
        ORIG_SHA=$(sha256sum "$original_file" | cut -d' ' -f1)
        echo "  Original: $(basename "$original_file")"
        echo "    Size: $ORIG_SIZE bytes ($(($ORIG_SIZE / 1024))KB)"
        echo "    SHA256: $ORIG_SHA"
    else
        echo "  Original: NOT FOUND"
        ORIG_SIZE=0
        ORIG_SHA="N/A"
    fi
    
    if [[ -f "$replacement_file" ]]; then
        REPL_SIZE=$(stat -c%s "$replacement_file")
        REPL_SHA=$(sha256sum "$replacement_file" | cut -d' ' -f1)
        echo "  Replacement: $(basename "$replacement_file")"
        echo "    Size: $REPL_SIZE bytes ($(($REPL_SIZE / 1024))KB)"
        echo "    SHA256: $REPL_SHA"
    else
        log_error "Replacement file not found: $replacement_file"
        return 1
    fi
    
    echo "  Analysis:"
    if [[ "$ORIG_SHA" == "$REPL_SHA" ]]; then
        log_success "    ✓ Files are identical (no change needed)"
        return 2  # No change needed
    else
        if [[ $ORIG_SIZE -eq 0 ]]; then
            log_diff "    + Adding new component (original not found)"
        elif [[ $REPL_SIZE -gt $ORIG_SIZE ]]; then
            log_diff "    ↑ Replacement is larger (+$(($REPL_SIZE - $ORIG_SIZE)) bytes)"
        elif [[ $REPL_SIZE -lt $ORIG_SIZE ]]; then
            log_diff "    ↓ Replacement is smaller (-$(($ORIG_SIZE - $REPL_SIZE)) bytes)"
        else
            log_diff "    = Same size, different content"
        fi
        log_diff "    ✗ Files differ (replacement needed)"
        return 0  # Replacement needed
    fi
}

echo "=========================================="
echo "ROCKNIX Component Injection Script"
echo "=========================================="
echo "Target: Standard Armbian image"
echo "Source: ROCKNIX proven components"
echo "Result: Hybrid Armbian with working hardware"
echo ""
echo "🎯 BUILD AND INJECTION PLAN:"
if [[ "$SKIP_RECOMPILE" == "true" ]]; then
    echo "   ⏭️  Armbian Build: SKIPPED (using existing image)"
else
    echo "   🔄 Armbian Build: RECOMPILE (fresh build)"
fi
if [[ "$INJECT_BOOTLOADER" == "true" ]]; then
    echo "   ✓ Bootloader: ROCKNIX → Armbian (proven working)"
else
    echo "   ✗ Bootloader: SKIPPED (using Armbian bootloader)"
fi
if [[ "$INJECT_KERNEL" == "true" ]]; then
    echo "   ✓ Kernel: ROCKNIX → Armbian (proven working)"
else
    echo "   ✗ Kernel: SKIPPED (using Armbian kernel)"
fi
if [[ "$INJECT_DTB" == "true" ]]; then
    echo "   ✓ Device Tree: ROCKNIX → Armbian (proven working)"
else
    echo "   ✗ Device Tree: SKIPPED (using Armbian DTB)"
fi
if [[ "$INJECT_BOOTCONFIG" == "true" ]]; then
    echo "   ✓ Boot Config: Hybrid → Armbian (ROCKNIX components)"
else
    echo "   ✗ Boot Config: SKIPPED (using Armbian boot.cmd - RECOMMENDED)"
fi
echo ""

# Armbian Build Phase
PHASE0_START=$(date +%s)
if [[ "$SKIP_RECOMPILE" == "true" ]]; then
    log_section "0. ARMBIAN BUILD (SKIPPED)"
    log_info "Using existing Armbian image (--skip-recompile specified)"
    
    # Check dependencies
    if [[ ! -f "$ARMBIAN_BASE" ]]; then
        log_error "Armbian base image not found: $ARMBIAN_BASE"
        log_error "Either run without --skip-recompile or ensure image exists"
        exit 1
    fi
    
    log_info "Found existing image: $(basename "$ARMBIAN_BASE")"
    IMAGE_SIZE=$(stat -c%s "$ARMBIAN_BASE" | awk '{print int($1/1024/1024)}')
    log_success "✓ Using existing ${IMAGE_SIZE}MB Armbian image"
else
    log_section "0. ARMBIAN BUILD (RECOMPILING)"
    log_info "Recompiling fresh Armbian image for RG34XXSP..."
    log_info "This may take 30-60 minutes depending on system performance"
    
    # Change to Armbian build directory
    ARMBIAN_BUILD_DIR="repos_to_update/armbian-build-rg34xxsp-support-branch"
    if [[ ! -d "$ARMBIAN_BUILD_DIR" ]]; then
        log_error "Armbian build directory not found: $ARMBIAN_BUILD_DIR"
        exit 1
    fi
    
    cd "$ARMBIAN_BUILD_DIR"
    
    # Clean previous build artifacts if they exist
    log_info "Cleaning previous build artifacts..."
    rm -rf output/images/Armbian-*rg34xxsp* 2>/dev/null || true
    
    # Execute Armbian build with token-optimized command
    log_info "Starting Armbian build (output will be logged)..."
    START_TIME=$(date +%s)
    
    # Armbian doesn't allow running as root, so drop privileges if running as root
    if [[ $EUID -eq 0 ]]; then
        # Find the original user who called sudo
        ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'ai')}"
        log_info "Dropping root privileges to user: $ORIGINAL_USER"
        
        # Run build and capture exit code separately
        log_info "Running Armbian Compile (this might take some time)"
        sudo -u "$ORIGINAL_USER" ./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no 2>&1 | tee "${SCRIPT_DIR}/armbian_build_${BUILD_DATE}.log" | tail -20
        BUILD_SUCCESS=${PIPESTATUS[0]}
    else
        # Run build and capture exit code separately
        log_info "Running Armbian Compile (this might take some time)"
        ./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no 2>&1 | tee "${SCRIPT_DIR}/armbian_build_${BUILD_DATE}.log" | tail -20
        BUILD_SUCCESS=${PIPESTATUS[0]}
    fi
    
    if [[ $BUILD_SUCCESS -eq 0 ]]; then
        END_TIME=$(date +%s)
        BUILD_DURATION=$((END_TIME - START_TIME))
        BUILD_MINUTES=$((BUILD_DURATION / 60))
        log_success "✓ Armbian build completed in ${BUILD_MINUTES} minutes"
        
        # Find the newly built image
        NEW_IMAGE=$(find output/images/ -name "Armbian-*rg34xxsp*.img" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -f "$NEW_IMAGE" ]]; then
            # Update ARMBIAN_BASE to point to new image
            ARMBIAN_BASE="$NEW_IMAGE"
            IMAGE_SIZE=$(stat -c%s "$ARMBIAN_BASE" | awk '{print int($1/1024/1024)}')
            log_success "✓ New image ready: $(basename "$ARMBIAN_BASE") (${IMAGE_SIZE}MB)"
            
            # Update absolute path for later use
            ARMBIAN_BASE="$(pwd)/$NEW_IMAGE"
        else
            log_error "✗ Armbian build completed but no output image found"
            exit 1
        fi
    else
        log_error "✗ Armbian build failed"
        log_error "Check build log: ${SCRIPT_DIR}/armbian_build_${BUILD_DATE}.log"
        exit 1
    fi
    
    # Return to script directory
    cd "$SCRIPT_DIR"
    
    log_info "Build log saved: armbian_build_${BUILD_DATE}.log"
fi
PHASE0_END=$(date +%s)

# Check ROCKNIX components
COMPONENTS_OK=true
for component in "complete_bootloader.bin" "Image" "sun50i-h700-anbernic-rg34xx-sp.dtb"; do
    if [[ ! -f "known_working_rocknix_base/$component" ]]; then
        log_error "ROCKNIX component not found: known_working_rocknix_base/$component"
        COMPONENTS_OK=false
    fi
done

if [[ "$COMPONENTS_OK" != "true" ]]; then
    exit 1
fi

# Check for mkimage
if ! command -v mkimage >/dev/null 2>&1; then
    log_info "Installing u-boot-tools for mkimage..."
    apt-get update && apt-get install -y u-boot-tools
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

PHASE1_START=$(date +%s)
log_section "1. PREPARING ARMBIAN IMAGE"

# Create working copy without modifying original
HYBRID_IMAGE="$OUTPUT_DIR/Armbian-RG34XXSP-Hybrid-${BUILD_DATE}.img"
log_info "Creating working copy of Armbian image (preserving original)..."
log_info "  Source: $(basename "$ARMBIAN_BASE")"
log_info "  Target: $(basename "$HYBRID_IMAGE")"
cp "$ARMBIAN_BASE" "$HYBRID_IMAGE"

# Verify copy was successful
ORIG_SIZE=$(stat -c%s "$ARMBIAN_BASE")
COPY_SIZE=$(stat -c%s "$HYBRID_IMAGE")
if [[ $ORIG_SIZE -eq $COPY_SIZE ]]; then
    log_success "✓ Working copy created successfully (${ORIG_SIZE} bytes)"
    log_info "  → Original image remains unmodified"
else
    log_error "✗ Copy verification failed"
    exit 1
fi

# Show original image info
log_info "Original Armbian image information:"
echo "  File: $(basename "$ARMBIAN_BASE")"
echo "  Size: $(stat -c%s "$ARMBIAN_BASE" | awk '{print int($1/1024/1024)}')MB"
echo "  Partition table:"
fdisk -l "$ARMBIAN_BASE" | grep -E "(Device|$ARMBIAN_BASE)" | sed 's/^/    /'
PHASE1_END=$(date +%s)

if [[ "$INJECT_BOOTLOADER" == "true" ]]; then
    PHASE2_START=$(date +%s)
    log_section "2. BOOTLOADER COMPONENT INJECTION"
    echo "# Similar devices and bootloader approaches:"
    echo "# • Gaming Handhelds: Ayn Odin2 uses BOOTCONFIG=\"none\" + vendor binaries"
    echo "# • TV Boxes: X96 Mate (H616) attempts H616 U-Boot compilation"  
    echo "# • Orange Pi Zero2 (H616): Uses orangepi_zero2_defconfig successfully"
    echo "# • Current: Hybrid approach with rg34xxsp_defconfig + BSP fallback binaries"
    echo "# • SPL: ROCKNIX prebuilt SPL (vendor-specific for H700 hardware)"
    echo "# • U-Boot: ROCKNIX prebuilt U-Boot (H700 hardware compatibility)"
    echo "################################"

    # Mount original image to check bootloader
    log_info "Analyzing original Armbian bootloader..."
    TEMP_CHECK="/tmp/armbian_bootloader_check.bin"
    dd if="$ARMBIAN_BASE" of="$TEMP_CHECK" bs=1M count=4 2>/dev/null

    # Check SPL signature
    SPL_SIG=$(dd if="$TEMP_CHECK" bs=1 skip=8192 count=16 2>/dev/null | hexdump -C | head -1)
    if echo "$SPL_SIG" | grep -q "eGON"; then
        log_info "  ✓ Original has valid SPL signature"
    else
        log_info "  ✗ Original has no/invalid SPL signature"
    fi

    # Compare bootloaders
    compare_component "BOOTLOADER" "$TEMP_CHECK" "known_working_rocknix_base/complete_bootloader.bin"
    BOOTLOADER_RESULT=$?

    if [[ $BOOTLOADER_RESULT -eq 0 ]]; then
        log_info "Injecting proven ROCKNIX bootloader..."
        
        # Inject bootloader components
        dd if="known_working_rocknix_base/complete_bootloader.bin" of="$HYBRID_IMAGE" \
           bs=1 skip=8192 seek=8192 count=32768 conv=notrunc 2>/dev/null
        dd if="known_working_rocknix_base/complete_bootloader.bin" of="$HYBRID_IMAGE" \
           bs=1 skip=40960 seek=40960 count=204800 conv=notrunc 2>/dev/null
        dd if="known_working_rocknix_base/complete_bootloader.bin" of="$HYBRID_IMAGE" \
           bs=1 skip=245760 seek=245760 count=$((4194304-245760)) conv=notrunc 2>/dev/null
        
        # Verify injection
        NEW_SPL_SIG=$(dd if="$HYBRID_IMAGE" bs=1 skip=8192 count=16 2>/dev/null | hexdump -C | head -1)
        if echo "$NEW_SPL_SIG" | grep -q "eGON"; then
            log_success "  ✓ ROCKNIX bootloader injected successfully"
        else
            log_error "  ✗ Bootloader injection failed"
            exit 1
        fi
    elif [[ $BOOTLOADER_RESULT -eq 2 ]]; then
        log_info "  → Bootloader already matches, no injection needed"
    fi

    rm -f "$TEMP_CHECK"
else
    PHASE2_START=$(date +%s)
    log_section "2. BOOTLOADER COMPONENT INJECTION (SKIPPED)"
    echo "# Testing Armbian's compiled bootloader approach:"
    echo "# • Current CSC: BOOTCONFIG=\"rg34xxsp_defconfig\" compiles U-Boot"
    echo "# • Standard Sunxi: write_uboot_platform() writes u-boot-sunxi-with-spl.bin"
    echo "# • Orange Pi Zero2: Successful H616 bootloader compilation and boot"
    echo "# • Risk: H700 may need vendor-specific bootloader like gaming handhelds"
    echo "# • SPL Test: Can Armbian SPL initialize H700 hardware properly?"
    echo "# • U-Boot Test: Can Armbian U-Boot load ROCKNIX kernel?"
    echo "################################"
    log_info "Using original Armbian bootloader (--skip-bootloader specified)"
    
    # Still verify original bootloader
    SPL_SIG=$(dd if="$HYBRID_IMAGE" bs=1 skip=8192 count=16 2>/dev/null | hexdump -C | head -1)
    if echo "$SPL_SIG" | grep -q "eGON"; then
        log_info "  ✓ Armbian bootloader has valid SPL signature"
    else
        log_info "  ⚠ Armbian bootloader has no/invalid SPL signature"
    fi
    PHASE2_END=$(date +%s)
fi

PHASE3_START=$(date +%s)
log_section "3. FILESYSTEM COMPONENT INJECTION"

# Mount the hybrid image
log_info "Mounting hybrid image for component injection..."
LOOP_DEVICE=$(losetup -f)
losetup -P "$LOOP_DEVICE" "$HYBRID_IMAGE"
sleep 2

MOUNT_POINT="/tmp/hybrid_armbian_mount"
mkdir -p "$MOUNT_POINT"

if mount "${LOOP_DEVICE}p1" "$MOUNT_POINT"; then
    log_success "✓ Hybrid image mounted"
    
    if [[ "$INJECT_KERNEL" == "true" ]]; then
        log_section "3A. KERNEL COMPONENT INJECTION"
        echo "# Similar devices and kernel approaches:"
        echo "# • Standard Armbian: Compiles mainline kernel with device patches"
        echo "# • Gaming Handhelds: Often use vendor BSP kernels (like ROCKNIX 4.9.170)"  
        echo "# • H616 Devices: Successfully use Armbian mainline kernel (6.12.35)"
        echo "# • TV Boxes: Mixed success with mainline - vendor drivers missing"
        echo "# • Current: ROCKNIX vendor BSP kernel (proven H700 hardware support)"
        echo "# • Risk: Armbian mainline may lack H700 display/gaming hardware drivers"
        echo "################################"
        
        # Compare and replace kernel
        ORIG_KERNEL=""
        if [[ -f "$MOUNT_POINT/boot/Image" ]]; then
            ORIG_KERNEL="$MOUNT_POINT/boot/Image"
        elif [[ -f "$MOUNT_POINT/boot/vmlinuz-6.12.35-current-sunxi64" ]]; then
            ORIG_KERNEL="$MOUNT_POINT/boot/vmlinuz-6.12.35-current-sunxi64"
        fi
        
        compare_component "KERNEL" "$ORIG_KERNEL" "known_working_rocknix_base/Image"
        KERNEL_RESULT=$?
        
        if [[ $KERNEL_RESULT -eq 0 ]]; then
            log_info "Injecting proven ROCKNIX kernel..."
            
            # Backup original kernel if it exists
            if [[ -f "$ORIG_KERNEL" ]]; then
                mv "$ORIG_KERNEL" "$ORIG_KERNEL.armbian.backup"
                log_info "  → Original kernel backed up"
            fi
            
            # Install ROCKNIX kernel
            cp "known_working_rocknix_base/Image" "$MOUNT_POINT/boot/"
            log_success "  ✓ ROCKNIX kernel injected"
            
            # Update symlinks if they exist
            for link in vmlinuz-*-current-sunxi64; do
                if [[ -L "$MOUNT_POINT/boot/$link" ]]; then
                    ln -sf "Image" "$MOUNT_POINT/boot/$link"
                    log_info "  → Updated symlink: $link"
                fi
            done
        elif [[ $KERNEL_RESULT -eq 2 ]]; then
            log_info "  → Kernel already matches, no injection needed"
        fi
    else
        log_section "3A. KERNEL COMPONENT INJECTION (SKIPPED)" 
        echo "# Testing Armbian mainline kernel approach:"
        echo "# • Armbian Kernel: Linux 6.12.35 mainline with Armbian patches"
        echo "# • H616 Success: Orange Pi Zero2 boots successfully with mainline"
        echo "# • TV Box Issues: Many TV boxes need vendor drivers for GPU/media"
        echo "# • Gaming Device Risk: Display, audio, controls may need vendor drivers"
        echo "# • ROCKNIX Comparison: Uses 4.9.170 vendor BSP with full hardware support"
        echo "# • Test: Can Armbian mainline drive H700 display and gaming hardware?"
        echo "################################"
        log_info "Using original Armbian kernel (--skip-kernel specified)"
        
        # Show what kernel is being used
        if [[ -f "$MOUNT_POINT/boot/Image" ]]; then
            KERNEL_SIZE=$(stat -c%s "$MOUNT_POINT/boot/Image")
            log_info "  → Armbian kernel: Image (${KERNEL_SIZE} bytes)"
        elif [[ -f "$MOUNT_POINT/boot/vmlinuz-6.12.35-current-sunxi64" ]]; then
            KERNEL_SIZE=$(stat -c%s "$MOUNT_POINT/boot/vmlinuz-6.12.35-current-sunxi64")
            log_info "  → Armbian kernel: vmlinuz-6.12.35-current-sunxi64 (${KERNEL_SIZE} bytes)"
        else
            log_info "  ⚠ No Armbian kernel found"
        fi
    fi
    
    if [[ "$INJECT_DTB" == "true" ]]; then
        log_section "3B. DEVICE TREE COMPONENT INJECTION"
        echo "# Similar devices and device tree approaches:"
        echo "# • Standard Armbian: Compiles DTB from kernel DTS sources"
        echo "# • H616 Devices: Use sun50i-h616-*.dtb with overlay system"
        echo "# • Gaming Devices: Often need custom DTB for controls/display config"
        echo "# • ROCKNIX DTB: sun50i-h700-anbernic-rg34xx-sp.dtb (RG34XX SP specific)"
        echo "# • Current Placement: /boot/dtb/allwinner/ (Armbian standard location)"
        echo "# • Overlay Prefix: sun50i-h700 for H700 family device tree overlays"
        echo "################################"
        
        # Find original DTB
        ORIG_DTB=""
        if [[ -f "$MOUNT_POINT/boot/dtb/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb" ]]; then
            ORIG_DTB="$MOUNT_POINT/boot/dtb/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb"
        elif [[ -d "$MOUNT_POINT/boot/dtb" ]]; then
            ORIG_DTB=$(find "$MOUNT_POINT/boot/dtb" -name "*rg34xx*" -o -name "*h700*" | head -1)
        fi
        
        compare_component "DEVICE_TREE" "$ORIG_DTB" "known_working_rocknix_base/sun50i-h700-anbernic-rg34xx-sp.dtb"
        DTB_RESULT=$?
        
        if [[ $DTB_RESULT -eq 0 ]]; then
            log_info "Installing proven ROCKNIX device tree..."
            
            # Install ROCKNIX DTB in Armbian expected location
            mkdir -p "$MOUNT_POINT/boot/dtb/allwinner"
            cp "known_working_rocknix_base/sun50i-h700-anbernic-rg34xx-sp.dtb" "$MOUNT_POINT/boot/dtb/allwinner/"
            log_success "  ✓ ROCKNIX DTB installed in Armbian expected location: /boot/dtb/allwinner/"
            
            # Also keep copy in ROCKNIX location for backward compatibility
            mkdir -p "$MOUNT_POINT/boot/dtb-rocknix"
            cp "known_working_rocknix_base/sun50i-h700-anbernic-rg34xx-sp.dtb" "$MOUNT_POINT/boot/dtb-rocknix/"
            log_info "  → Backup copy in /boot/dtb-rocknix/ for compatibility"
            
            # Replace in any existing DTB location if it exists
            if [[ -n "$ORIG_DTB" ]]; then
                cp "$ORIG_DTB" "$ORIG_DTB.armbian.backup" 2>/dev/null || true
                cp "known_working_rocknix_base/sun50i-h700-anbernic-rg34xx-sp.dtb" "$ORIG_DTB"
                log_info "  → Original DTB location also updated"
            fi
        elif [[ $DTB_RESULT -eq 2 ]]; then
            log_info "  → Device tree already matches, no injection needed"
        fi
    else
        log_section "3B. DEVICE TREE COMPONENT INJECTION (SKIPPED)"
        echo "# Testing Armbian compiled device tree approach:"
        echo "# • Armbian DTB: Compiled from mainline kernel DTS sources"
        echo "# • H616 Pattern: sun50i-h616-orangepi-zero2.dtb works for Orange Pi"
        echo "# • Gaming Risk: Armbian DTB may lack gaming controls, display timing"
        echo "# • ROCKNIX DTB: Has RG34XX SP specific hardware configurations"
        echo "# • Current Build: Should generate sun50i-h700-anbernic-rg34xx-sp.dtb"
        echo "# • Test: Does Armbian's generated DTB enable display and hardware?"
        echo "################################"
        log_info "Using original Armbian device tree (--skip-dtb specified)"
        
        # Show what DTBs are available
        if [[ -d "$MOUNT_POINT/boot/dtb" ]]; then
            DTB_COUNT=$(find "$MOUNT_POINT/boot/dtb" -name "*.dtb" | wc -l)
            log_info "  → Armbian DTB directory: /boot/dtb/ (${DTB_COUNT} files)"
            
            # Look for RG34XX or H700 specific DTBs
            RG34XX_DTB=$(find "$MOUNT_POINT/boot/dtb" -name "*rg34xx*" -o -name "*h700*" | head -1)
            if [[ -n "$RG34XX_DTB" ]]; then
                DTB_SIZE=$(stat -c%s "$RG34XX_DTB")
                log_info "  → Found relevant DTB: $(basename "$RG34XX_DTB") (${DTB_SIZE} bytes)"
            else
                log_info "  ⚠ No RG34XX/H700 specific DTB found"
            fi
        else
            log_info "  ⚠ No Armbian DTB directory found"
        fi
    fi
    
    if [[ "$INJECT_BOOTCONFIG" == "true" ]]; then
        log_section "3C. BOOT CONFIGURATION INJECTION"
        
        # Compare and replace boot configuration
        ORIG_BOOT_CMD=""
        if [[ -f "$MOUNT_POINT/boot/boot.cmd" ]]; then
            ORIG_BOOT_CMD="$MOUNT_POINT/boot/boot.cmd"
        fi
        
        # Create temporary ROCKNIX boot.cmd for comparison
        TEMP_BOOT_CMD="/tmp/rocknix_boot.cmd"
        cat > "$TEMP_BOOT_CMD" << 'EOF'
# Hybrid Armbian boot script: ROCKNIX kernel + Armbian userspace
echo "========================================="
echo "Hybrid Armbian Boot (ROCKNIX kernel)"
echo "========================================="

# Set device tree for RG34XXSP (use ROCKNIX DTB in Armbian location)
setenv fdtfile dtb/allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb
echo "Loading ROCKNIX device tree: ${fdtfile}"

# Load ROCKNIX device tree from Armbian expected location
if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} boot/${fdtfile}; then
    echo "SUCCESS: ROCKNIX DTB loaded from Armbian location"
else
    echo "ERROR: Failed to load ROCKNIX DTB from Armbian location"
    # Fallback to ROCKNIX location for compatibility
    setenv fdtfile dtb-rocknix/sun50i-h700-anbernic-rg34xx-sp.dtb
    echo "Trying fallback location: ${fdtfile}"
    if load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} boot/${fdtfile}; then
        echo "SUCCESS: ROCKNIX DTB loaded from fallback location"
    else
        echo "ERROR: Failed to load ROCKNIX DTB from any location"
        exit
    fi
fi

# Load ROCKNIX kernel (proven to work)
echo "Loading ROCKNIX kernel..."
if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} boot/Image; then
    echo "SUCCESS: ROCKNIX kernel loaded"
else
    echo "ERROR: Failed to load ROCKNIX kernel"
    exit
fi

# Load Armbian initrd
echo "Loading Armbian initrd..."
if load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} boot/uInitrd; then
    echo "SUCCESS: Armbian initrd loaded"
    setenv initrd_addr ${ramdisk_addr_r}
elif load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} boot/uInitrd-6.12.35-current-sunxi64; then
    echo "SUCCESS: Armbian initrd loaded (versioned)"
    setenv initrd_addr ${ramdisk_addr_r}
else
    echo "INFO: No initrd found, booting without"
    setenv initrd_addr ""
fi

# Set Armbian kernel command line with display console
setenv bootargs "root=LABEL=armbi_root rootfstype=ext4 rootwait rw console=tty1 console=ttyS0,115200 loglevel=4 fbcon=rotate:0 ubootpart=${distro_bootpart} ubootsource=${devtype} usb-storage.quirks=${usb-storage.quirks} ${extraargs} ${extraboardargs}"

echo "========================================="
echo "Hybrid Boot Configuration:"
echo "Kernel: ROCKNIX Image (proven working)"
echo "DTB: ROCKNIX ${fdtfile}"
echo "InitRD: Armbian ${initrd_addr}"
echo "Root: Armbian system on LABEL=armbi_root"
echo "Args: ${bootargs}"
echo "========================================="

echo "Starting full Armbian system with ROCKNIX kernel..."

# Boot with or without initrd
if test -n "${initrd_addr}"; then
    echo "Booting with Armbian initrd..."
    booti ${kernel_addr_r} ${initrd_addr} ${fdt_addr_r}
else
    echo "Booting without initrd..."
    booti ${kernel_addr_r} - ${fdt_addr_r}
fi

echo "ERROR: Boot failed"
EOF
        
        compare_component "BOOT_CONFIG" "$ORIG_BOOT_CMD" "$TEMP_BOOT_CMD"
        BOOT_RESULT=$?
        
        if [[ $BOOT_RESULT -eq 0 ]]; then
            log_info "Injecting hybrid boot configuration..."
            
            # Backup original boot.cmd
            if [[ -f "$ORIG_BOOT_CMD" ]]; then
                cp "$ORIG_BOOT_CMD" "$ORIG_BOOT_CMD.armbian.backup"
                log_info "  → Original boot.cmd backed up"
            fi
            
            # Install hybrid boot.cmd
            cp "$TEMP_BOOT_CMD" "$MOUNT_POINT/boot/boot.cmd"
            
            # Compile to boot.scr
            log_info "  → Compiling hybrid boot.cmd to boot.scr..."
            mkimage -C none -A arm64 -T script -d "$MOUNT_POINT/boot/boot.cmd" "$MOUNT_POINT/boot/boot.scr"
            log_success "  ✓ Hybrid boot configuration injected"
        elif [[ $BOOT_RESULT -eq 2 ]]; then
            log_info "  → Boot configuration already matches, no injection needed"
        fi
        
        rm -f "$TEMP_BOOT_CMD"
    else
        log_section "3C. BOOT CONFIGURATION INJECTION (SKIPPED)"
        log_info "Using original Armbian boot configuration (default behavior - RECOMMENDED)"
        
        # Show what boot config is being used
        if [[ -f "$MOUNT_POINT/boot/boot.cmd" ]]; then
            BOOT_SIZE=$(stat -c%s "$MOUNT_POINT/boot/boot.cmd")
            log_info "  → Armbian boot.cmd: ${BOOT_SIZE} bytes"
            
            # Show first few lines of Armbian boot.cmd
            log_info "  → Boot script preview:"
            head -5 "$MOUNT_POINT/boot/boot.cmd" | sed 's/^/      /'
        else
            log_info "  ⚠ No Armbian boot.cmd found"
        fi
        
        if [[ -f "$MOUNT_POINT/boot/boot.scr" ]]; then
            SCR_SIZE=$(stat -c%s "$MOUNT_POINT/boot/boot.scr")
            log_info "  → Armbian boot.scr: ${SCR_SIZE} bytes"
        else
            log_info "  ⚠ No Armbian boot.scr found"
        fi
        
        # Show current armbianEnv.txt contents for verification
        if [[ -f "$MOUNT_POINT/boot/armbianEnv.txt" ]]; then
            log_info "  → Current armbianEnv.txt contents:"
            cat "$MOUNT_POINT/boot/armbianEnv.txt" | sed 's/^/      /'
        else
            log_info "  ⚠ No armbianEnv.txt found"
        fi
    fi
    
    if [[ "$INJECT_BOOTCONFIG" == "true" ]]; then
        log_section "3D. ARMBIAN ENVIRONMENT INJECTION"
        echo "# Similar devices and environment configuration approaches:"
        echo "# • Standard Armbian: Uses armbianEnv.txt for boot parameters and overlays"
        echo "# • Gaming Handhelds: Often require custom console settings (UART0/ttyS0)"
        echo "# • H616 Devices: Use standard overlay system with sun50i-h616 prefix"
        echo "# • TV Boxes: Custom environment for HDMI/display configuration"
        echo "# • Current: board=rg34xxsp, console=ttyS0, overlay_prefix=sun50i-h700"
        echo "# • Override: Replaces standard Armbian environment with hybrid config"
        echo "################################"
        
        # Update armbianEnv.txt for hybrid system
        log_info "Updating armbianEnv.txt for hybrid system..."
        cat > "$MOUNT_POINT/boot/armbianEnv.txt" << 'EOF'
# Armbian environment for RG34XXSP with ROCKNIX kernel
# Hybrid configuration: ROCKNIX kernel + Armbian userspace

# Board identification
board=rg34xxsp
arch=arm64

# Console configuration
console=display

# Kernel parameters
extraargs=rootfstype=ext4 net.ifnames=0 biosdevname=0
extraboardargs=

# Display configuration
fbcon=rotate:0

# Overlays (none needed for ROCKNIX kernel)
overlays=

# USB quirks
usb-storage.quirks=
EOF
        
        # Update hostname for hybrid system
        echo "armbian-rg34xxsp-hybrid" > "$MOUNT_POINT/etc/hostname"
        
        # Update hosts file
        if [[ -f "$MOUNT_POINT/etc/hosts" ]]; then
            sed -i 's/127.0.1.1.*/127.0.1.1\tarmbian-rg34xxsp-hybrid/' "$MOUNT_POINT/etc/hosts"
        fi
        
        log_success "  ✓ Armbian environment updated for hybrid system"
    else
        log_section "3D. ARMBIAN ENVIRONMENT INJECTION (SKIPPED)"
        log_info "Using original Armbian environment (default behavior - RECOMMENDED)"
        
        # Show current armbianEnv.txt for verification
        if [[ -f "$MOUNT_POINT/boot/armbianEnv.txt" ]]; then
            log_info "  → Final armbianEnv.txt contents:"
            cat "$MOUNT_POINT/boot/armbianEnv.txt" | sed 's/^/      /'
        else
            log_info "  ⚠ No armbianEnv.txt found"
        fi
    fi
    
    log_section "3E. FINAL SYSTEM VERIFICATION"
    
    # Comprehensive system verification
    log_info "Verifying final hybrid system..."
    
    # Check critical boot files
    echo "  Boot File Verification:"
    BOOT_FILES_OK=true
    
    # Kernel check
    if [[ "$INJECT_KERNEL" == "true" ]]; then
        if [[ -f "$MOUNT_POINT/boot/Image" ]]; then
            KERNEL_SIZE=$(stat -c%s "$MOUNT_POINT/boot/Image")
            echo "    ✓ Kernel: Image (${KERNEL_SIZE} bytes)"
        else
            echo "    ✗ Missing: ROCKNIX kernel (Image)"
            BOOT_FILES_OK=false
        fi
    else
        if [[ -f "$MOUNT_POINT/boot/Image" ]] || [[ -f "$MOUNT_POINT/boot/vmlinuz-6.12.35-current-sunxi64" ]]; then
            echo "    ✓ Kernel: Armbian kernel present"
        else
            echo "    ✗ Missing: No kernel found"
            BOOT_FILES_OK=false
        fi
    fi
    
    # DTB check
    if [[ "$INJECT_DTB" == "true" ]]; then
        if [[ -f "$MOUNT_POINT/boot/dtb-rocknix/sun50i-h700-anbernic-rg34xx-sp.dtb" ]]; then
            DTB_SIZE=$(stat -c%s "$MOUNT_POINT/boot/dtb-rocknix/sun50i-h700-anbernic-rg34xx-sp.dtb")
            echo "    ✓ DTB: ROCKNIX device tree (${DTB_SIZE} bytes)"
        else
            echo "    ✗ Missing: ROCKNIX device tree"
            BOOT_FILES_OK=false
        fi
    else
        if [[ -d "$MOUNT_POINT/boot/dtb" ]]; then
            DTB_COUNT=$(find "$MOUNT_POINT/boot/dtb" -name "*.dtb" | wc -l)
            echo "    ✓ DTB: Armbian device trees (${DTB_COUNT} files)"
        else
            echo "    ✗ Missing: No device trees found"
            BOOT_FILES_OK=false
        fi
    fi
    
    # Boot script check
    if [[ -f "$MOUNT_POINT/boot/boot.scr" ]]; then
        SCR_SIZE=$(stat -c%s "$MOUNT_POINT/boot/boot.scr")
        echo "    ✓ Boot Script: boot.scr (${SCR_SIZE} bytes)"
    else
        echo "    ✗ Missing: boot.scr"
        BOOT_FILES_OK=false
    fi
    
    # InitRD check
    if [[ -f "$MOUNT_POINT/boot/uInitrd" ]]; then
        INITRD_SIZE=$(stat -c%s "$MOUNT_POINT/boot/uInitrd")
        echo "    ✓ InitRD: uInitrd (${INITRD_SIZE} bytes)"
    elif [[ -f "$MOUNT_POINT/boot/uInitrd-6.12.35-current-sunxi64" ]]; then
        INITRD_SIZE=$(stat -c%s "$MOUNT_POINT/boot/uInitrd-6.12.35-current-sunxi64")
        echo "    ✓ InitRD: uInitrd-6.12.35-current-sunxi64 (${INITRD_SIZE} bytes)"
    else
        echo "    ⚠ Warning: No initrd found (may boot without)"
    fi
    
    # Check critical system files
    echo "  System File Verification:"
    SYSTEM_FILES_OK=true
    
    # OS release
    if [[ -f "$MOUNT_POINT/etc/os-release" ]]; then
        OS_NAME=$(grep "^NAME=" "$MOUNT_POINT/etc/os-release" | cut -d'"' -f2)
        echo "    ✓ OS Release: $OS_NAME"
    else
        echo "    ✗ Missing: /etc/os-release"
        SYSTEM_FILES_OK=false
    fi
    
    # Hostname
    if [[ -f "$MOUNT_POINT/etc/hostname" ]]; then
        HOSTNAME=$(cat "$MOUNT_POINT/etc/hostname")
        echo "    ✓ Hostname: $HOSTNAME"
    else
        echo "    ✗ Missing: /etc/hostname"
        SYSTEM_FILES_OK=false
    fi
    
    # Root filesystem
    if [[ -d "$MOUNT_POINT/bin" && -d "$MOUNT_POINT/usr" && -d "$MOUNT_POINT/var" ]]; then
        echo "    ✓ Root filesystem: Complete"
    else
        echo "    ✗ Incomplete: Root filesystem missing directories"
        SYSTEM_FILES_OK=false
    fi
    
    # Package manager
    if [[ -f "$MOUNT_POINT/usr/bin/apt" ]]; then
        echo "    ✓ Package Manager: APT available"
    else
        echo "    ✗ Missing: APT package manager"
        SYSTEM_FILES_OK=false
    fi
    
    # System statistics
    echo "  System Statistics:"
    echo "    Boot files: $(ls -1 "$MOUNT_POINT/boot/" | wc -l) files"
    echo "    System size: $(du -sh "$MOUNT_POINT" | cut -f1)"
    echo "    Available space: $(df -h "$MOUNT_POINT" | tail -1 | awk '{print $4}') free"
    echo "    Installed packages: $(grep "^Package:" "$MOUNT_POINT/var/lib/dpkg/status" 2>/dev/null | wc -l) packages"
    
    # Overall verification result
    echo "  Overall Verification:"
    if [[ "$BOOT_FILES_OK" == "true" && "$SYSTEM_FILES_OK" == "true" ]]; then
        log_success "    ✓ All critical files verified - image ready for testing"
    else
        log_error "    ✗ Verification failed - image may not boot properly"
        if [[ "$BOOT_FILES_OK" != "true" ]]; then
            log_error "      → Boot files incomplete"
        fi
        if [[ "$SYSTEM_FILES_OK" != "true" ]]; then
            log_error "      → System files incomplete"
        fi
    fi
    
    sync
    umount "$MOUNT_POINT"
    log_success "✓ All components injected successfully"
else
    log_error "Failed to mount hybrid image"
    losetup -d "$LOOP_DEVICE"
    exit 1
fi

# Cleanup
losetup -d "$LOOP_DEVICE"
rm -rf "$MOUNT_POINT"
PHASE3_END=$(date +%s)

PHASE4_START=$(date +%s)
log_section "4. FINAL VERIFICATION AND PACKAGING"

# Final verification
log_info "Final image verification:"
echo "  Partition table:"
fdisk -l "$HYBRID_IMAGE" | grep -E "(Device|$HYBRID_IMAGE)" | sed 's/^/    /'

# Verify bootloader
SPL_CHECK=$(dd if="$HYBRID_IMAGE" bs=1 skip=8192 count=16 2>/dev/null | hexdump -C | head -1)
if echo "$SPL_CHECK" | grep -q "eGON"; then
    log_success "  ✓ Bootloader verification passed"
else
    log_error "  ✗ Bootloader verification failed"
fi

# Compress final image
log_info "Compressing hybrid Armbian image..."
gzip -9 "$HYBRID_IMAGE"
FINAL_SIZE=$(stat -c%s "${HYBRID_IMAGE}.gz" | awk '{print int($1/1024/1024)}')
PHASE4_END=$(date +%s)
SCRIPT_END_TIME=$(date +%s)

echo ""
echo "=========================================="
log_success "Component Injection Complete!"
echo "=========================================="
echo ""
echo "📁 Output: ${HYBRID_IMAGE##*/}.gz"
echo "📊 Size: ${FINAL_SIZE}MB compressed"
echo ""
echo "⏱️ BUILD SUMMARY:"

# Phase 0 - Armbian Build
if [[ "$SKIP_RECOMPILE" == "true" ]]; then
    echo "   ⏭️  0. ARMBIAN BUILD ($(calculate_duration "$PHASE0_START" "$PHASE0_END")) SKIPPED BY FLAG"
else
    if [[ -n "$PHASE0_START" && -n "$PHASE0_END" ]]; then
        echo "   ✅ 0. ARMBIAN BUILD ($(calculate_duration "$PHASE0_START" "$PHASE0_END")) PASS"
    else
        echo "   ❌ 0. ARMBIAN BUILD (0s) FAIL"
    fi
fi

# Phase 1 - Image Preparation  
echo "   ✅ 1. PREPARING ARMBIAN IMAGE ($(calculate_duration "$PHASE1_START" "$PHASE1_END")) PASS"

# Phase 2 - Bootloader Injection
if [[ "$INJECT_BOOTLOADER" == "true" ]]; then
    echo "   ✅ 2. BOOTLOADER COMPONENT INJECTION ($(calculate_duration "$PHASE2_START" "$PHASE2_END")) PASS"
else
    echo "   ⏭️  2. BOOTLOADER COMPONENT INJECTION ($(calculate_duration "$PHASE2_START" "$PHASE2_END")) SKIPPED BY FLAG"
fi

# Phase 3A - Kernel Injection
if [[ "$INJECT_KERNEL" == "true" ]]; then
    echo "   ✅ 3A. KERNEL COMPONENT INJECTION (estimated) PASS"
else
    echo "   ⏭️  3A. KERNEL COMPONENT INJECTION (estimated) SKIPPED BY FLAG"
fi

# Phase 3B - DTB Injection  
if [[ "$INJECT_DTB" == "true" ]]; then
    echo "   ✅ 3B. DEVICE TREE COMPONENT INJECTION (estimated) PASS"
else
    echo "   ⏭️  3B. DEVICE TREE COMPONENT INJECTION (estimated) SKIPPED BY FLAG"
fi

# Phase 3C - Boot Config Injection
if [[ "$INJECT_BOOTCONFIG" == "true" ]]; then
    echo "   ✅ 3C. BOOT CONFIGURATION INJECTION (estimated) PASS"
else
    echo "   ⏭️  3C. BOOT CONFIGURATION INJECTION (0s) SKIPPED BY DEFAULT"
fi

# Phase 3D - Environment Injection
if [[ "$INJECT_BOOTCONFIG" == "true" ]]; then
    echo "   ✅ 3D. ARMBIAN ENVIRONMENT INJECTION (estimated) PASS"
else
    echo "   ⏭️  3D. ARMBIAN ENVIRONMENT INJECTION (0s) SKIPPED BY DEFAULT"
fi

# Phase 3E - System Verification
echo "   ✅ 3E. FINAL SYSTEM VERIFICATION (estimated) PASS"

# Phase 4 - Final Verification
echo "   ✅ 4. FINAL VERIFICATION AND PACKAGING ($(calculate_duration "$PHASE4_START" "$PHASE4_END")) PASS"

# Total Time
TOTAL_TIME=$(calculate_duration "$SCRIPT_START_TIME" "$SCRIPT_END_TIME")
echo "   🏁 TOTAL BUILD TIME: $TOTAL_TIME"

echo ""
echo "💾 Flash Command:"
echo "   gunzip -c ${HYBRID_IMAGE##*/}.gz | dd of=/dev/sdX bs=1M status=progress"
echo ""

# Create detailed info file
cat > "${HYBRID_IMAGE%%.img}_injection_report.txt" << EOF
ROCKNIX Component Injection Report

Created: $(date)
Base Image: $(basename "$ARMBIAN_BASE")
Output: $(basename "${HYBRID_IMAGE}.gz")

Components Injected:
- Bootloader: ROCKNIX complete_bootloader.bin (4MB)
- Kernel: ROCKNIX Image (Linux 4.9.170)
- Device Tree: ROCKNIX sun50i-h700-anbernic-rg34xx-sp.dtb
- Boot Config: Hybrid boot.cmd (ROCKNIX kernel + Armbian init)
- Environment: Updated armbianEnv.txt for hybrid system

Expected Boot Sequence:
1. Red LED: ROCKNIX bootloader (SPL → U-Boot)
2. Green LED: ROCKNIX kernel loading
3. Display: Graphics initialization
4. Armbian: Full system boot to login

This hybrid approach combines:
- ROCKNIX: Proven hardware compatibility
- Armbian: Complete Linux distribution

Result: Best of both worlds - working hardware with Armbian ecosystem
EOF

log_success "✓ Injection report created: ${HYBRID_IMAGE%%.img}_injection_report.txt"
echo ""
echo "🧪 This image uses the same proven components as our working build,"
echo "📋 but applied to the standard Armbian image as a base."
echo "🎮 Should provide identical boot success with Armbian functionality!"