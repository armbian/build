# Create UFS aligned image (requires >= Debian 13 (Trixie) Host)
function extension_prepare_config__ufs {
    # Check sfdisk version is >= 2.41 for UFS support
    local sfdisk_version
    sfdisk_version=$(sfdisk --version | awk '/util-linux/ {print $NF}')
    if [[ -z "${sfdisk_version}" ]]; then
        exit_with_error "sfdisk not found - please install util-linux / fdisk >= 2.41 package"
    fi
    if linux-version compare "${sfdisk_version}" lt "2.41"; then
        exit_with_error "UFS extension requires sfdisk >= 2.41 (from util-linux). Current version: ${sfdisk_version}"
    fi
    EXTRA_IMAGE_SUFFIXES+=("-ufs")
    declare -g SECTOR_SIZE=4096
}