#!/usr/bin/env bash
# Extension: jethub-burn
# Automatically converts Armbian .img into burn image after build

function run_after_build__999_jethub_burn() {

    local IMG_GLOB DTS_NAME BINS_SUBDIR
    case "$BOARD" in
        jethubj80)
            IMG_GLOB="Armbian-*Jethubj80*.img"
            DTS_NAME="meson-gxl-s905w-jethome-jethub-j80.dts"
            BINS_SUBDIR="j80"
            ;;
        jethubj100)
            IMG_GLOB="Armbian-*Jethubj100*.img"
            DTS_NAME="meson-axg-jethome-jethub-j100.dts"
            BINS_SUBDIR="j100"
            ;;
        jethubj200)
            IMG_GLOB="Armbian-*Jethubj200*.img"
            DTS_NAME="meson-sm1-jethome-jethub-j200.dts"
            BINS_SUBDIR="j200"
            ;;
        *)
            display_alert "jethub-burn" "Unsupported board: ${BOARD}" "error"
            echo "Supported boards: jethubj80, jethubj100, jethubj200"
            exit 1
            ;;
    esac

    BOARD_NAME="${BOARD_NAME:-$BOARD}"

    display_alert "jethub-burn" "Preparing burn conversion for ${BOARD_NAME}" "info"

    local IMAGES_DIR="${SRC}/output/images"
    local DEBS_DIR="${SRC}/output/debs"
    local TOOLS_DIR="${SRC}/extensions/jethub-burn-tools"

    local MAKE_BURN="${TOOLS_DIR}/make_burn.sh"
    local PACKER="${TOOLS_DIR}/tools/aml_image_v2_packer_new"
    local BINS_DIR="${TOOLS_DIR}/bins/${BINS_SUBDIR}"
    local IMAGE_CFG="${TOOLS_DIR}/bins/image.armbian.cfg"
    local DTS_DIR="${TOOLS_DIR}/dts"

    local IMG_PATH
    IMG_PATH=$(find "${IMAGES_DIR}" -type f -name "${IMG_GLOB}" | sort | tail -n 1)

    if [[ -z "${IMG_PATH}" ]]; then
        display_alert "jethub-burn" "Burn conversion skipped: no image found matching '${IMG_GLOB}'" "wrn"
        return 0
    fi

    display_alert "jethub-burn" "Creating burn image from $(basename "${IMG_PATH}")" "info"

    [[ -x "${MAKE_BURN}" ]] || exit_with_error "make_burn.sh not executable: ${MAKE_BURN}"
    [[ -x "${PACKER}"    ]] || exit_with_error "Packer not executable: ${PACKER}"
    [[ -r "${IMAGE_CFG}" ]] || exit_with_error "Image config not found: ${IMAGE_CFG}"
    [[ -d "${BINS_DIR}"  ]] || exit_with_error "Bins dir not found: ${BINS_DIR}"
    [[ -r "${BINS_DIR}/DDR.USB" && -r "${BINS_DIR}/UBOOT.USB" && -r "${BINS_DIR}/platform.conf" ]] \
        || exit_with_error "bins/${BINS_SUBDIR} is incomplete (need DDR.USB, UBOOT.USB, platform.conf)"
    [[ -r "${DTS_DIR}/${DTS_NAME}" ]] || exit_with_error "DTS not found: ${DTS_DIR}/${DTS_NAME}"

    local UBOOT_DEB
    UBOOT_DEB=$(ls ${DEBS_DIR}/linux-u-boot-${BOARD}-*.deb 2>/dev/null | sort -V | tail -n1)

    if [[ -z "$UBOOT_DEB" ]]; then
        exit_with_error "U-Boot deb not found by pattern linux-u-boot-${BOARD}-*.deb in ${DEBS_DIR}"
    fi

    local TMP="${SRC}/.tmp/jethub-burn.$$"
    mkdir -p "${TMP}/deb-uboot"
    dpkg -x "${UBOOT_DEB}" "${TMP}/deb-uboot" || exit_with_error "dpkg -x U-Boot failed"

    local UBOOT_BIN
    UBOOT_BIN=$(find "${TMP}/deb-uboot/usr/lib" -type f -name "u-boot.nosd.bin" | head -n1)
    [[ -f "${UBOOT_BIN}" ]] || exit_with_error "u-boot.nosd.bin not found inside ${UBOOT_DEB}"

    BINS_DIR="${BINS_DIR}" IMAGE_CFG="${IMAGE_CFG}" \
    PACKER_PATH="${PACKER}" UBOOT_BIN="${UBOOT_BIN}" \
    DTS_DIR="${DTS_DIR}" DTS_NAME="${DTS_NAME}" \
    bash "${MAKE_BURN}" "${IMG_PATH}" "${BOARD}"
    local rc=$?

    rm -rf "${TMP}"

    if (( rc == 0 )); then
        display_alert "jethub-burn" "Burn image created (see output/images)" "ok"
    else
        exit_with_error "Burn image creation failed (rc=${rc})"
    fi
}

