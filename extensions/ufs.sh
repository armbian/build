# Create UFS aligned image (requires >= Debian 13 (Trixie) Host)
function extension_prepare_config__ufs {
    # Check sfdisk version is >= 2.41 for UFS support
    local sfdisk_version
    if ! command -v sfdisk >/dev/null 2>&1; then
        exit_with_error "sfdisk not found. Please install util-linux (provides sfdisk) >= 2.41."
    fi
    # Extract the util-linux version and strip any non-numeric characters for robustness
    sfdisk_version="$(sfdisk --version 2>/dev/null | awk '/util-linux/ {print $NF}' | tr -cd '0-9.')"
    if [[ -z "${sfdisk_version}" ]]; then
        exit_with_error "Unable to determine util-linux version from 'sfdisk --version'."
    fi
    if linux-version compare "${sfdisk_version}" lt "2.41"; then
        exit_with_error "UFS extension requires sfdisk >= 2.41 (from util-linux). Current version: ${sfdisk_version}"
    fi
    EXTRA_IMAGE_SUFFIXES+=("-ufs")
    declare -g SECTOR_SIZE=4096
}