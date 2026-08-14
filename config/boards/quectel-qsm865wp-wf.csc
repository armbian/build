# Qualcomm QSM865WP-WF 5G Smart Module - board description
# Qualcomm SM8250 SoC, 8 GB LPDDR5, UFS 3.0 + SD card,
# PCIe2 5G M.2 MHI, PCIe0 QCA6390 WiFi/BT, HDMI via LT9611,
# 2x USB-C (OTG) + USB-A host, 40-pin CAN/SPI/UART headers.
#
# DTS is a SINGLE FILE: patch/kernel/archive/sm8250-6.18/dt/quectel-qsm865wp-wf.dts
# (no separate .dtsi, since this board has no SKU variants to share).

BOARD_NAME="Quectel QSM865WP-WF"
BOARD_VENDOR="quectel"
BOARDFAMILY="sm8250"
# *** MUST CHANGE BEFORE PR ***  set BOARD_MAINTAINER to your GitHub login
BOARD_MAINTAINER="stevenliuit"
INTRODUCED="2026"

# Mainline / LTS kernels
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"

# Bootloader is ABL (Qualcomm Android Boot Loader), no U-Boot for this board
BOOTCONFIG="none"

# Use ABL-style boot image output (matches the sm8250 family default)
enable_extension "image-output-abl"

# ABL boot image: kernel Image + the board DTB + initrd, packaged by mkbootimg
ABL_DTB_LIST=("quectel-qsm865wp-wf")

# Serial console: ttyMSM0 at 115200n8 (UART12 on this board, see aliases)
# The cmdline below is what the ABL image will use as its kernel command line.
BOOTIMG_CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused loglevel=7 panic=30 audit=0 allow_mismatched_32bit_el0 mem_sleep_default=s2idle earlycon=qcom_geni,0xa90000 console=ttyMSM0,115200n8 pcie_pme=nomsi"

# Partition table: GPT for UFS boot devices
IMAGE_PARTITION_TABLE="gpt"

# ARM Trusted Linux firmware set: install the full set so that a650_zap.mbn,
# a650_sqe.fw, a650_gmu.bin are all on the boot partition.
BOARD_FIRMWARE_INSTALL="-full"

# No display by default; HDMI is available if LT9611 is wired.
HAS_VIDEO_OUTPUT="no"

# Disable desktop stack — this is an embedded 5G module, not a desktop board.
FULL_DESKTOP="no"
DESKTOP_AUTOLOGIN="no"
BOOT_LOGO="no"

# Power management: suspend is not stable on most QCom SoCs.
POWER_MANAGEMENT_FEATURES="no"

# Include ufs, nvme, etc. in the default module list (loaded automatically).
# Default works fine; leaving MODULES unset.

# Example of a tweak hook — runs after the base filesystem is built.
# Use only if you actually need to drop extra files / services in.
# function post_family_tweaks_bsp__quectel_qsm865wp_wf_bsp_services() {
#     display_alert "$BOARD" "Add bsp services" "info"
#     mkdir -p "$destination/usr/local/bin/"
#     install -Dm755 "$SRC/packages/bsp/generate-bt-mac-addr/bt-fixed-mac.sh" \
#         "$destination/usr/local/bin/"
# }

# Userspace compatibility check
function quectel_qsm865wp_wf_is_userspace_supported() {
    [[ "${RELEASE}" == "bookworm"  ]] && return 0
    [[ "${RELEASE}" == "trixie"    ]] && return 0
    [[ "${RELEASE}" == "jammy"     ]] && return 0
    [[ "${RELEASE}" == "noble"     ]] && return 0
    return 1
}

function quectel_qsm865wp_wf_is_userspace_supported_alert() {
    if ! quectel_qsm865wp_wf_is_userspace_supported; then
        display_alert "Missing userspace for ${BOARD}" \
            "${RELEASE} does not have the userspace necessary to support ${BOARD}" "warn"
        return 1
    fi
    return 0
}

# Gate any post-tweaks on userspace availability.
function post_family_tweaks__quectel_qsm865wp_wf() {
    quectel_qsm865wp_wf_is_userspace_supported_alert || return 0
    return 0
}