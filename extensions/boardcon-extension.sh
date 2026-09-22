# Thin wrapper that enables Boardcon's external Armbian extension
# (currently used by Boardcon SBC3568 boards).
#
# The actual extension lives in an external repository:
#   https://github.com/boardcon-arm/boardcon_armbian_extension
#
# This wrapper fetches the selected extension branch and enables its
# entrypoint for Boardcon-specific kernel patches, board support,
# and hardware-specific features.

echo "========== Boardcon extension loaded =========="
echo "BOARD=${BOARD}"
echo "BRANCH=${BRANCH}"
echo "SRC=${SRC}"

BOARDCON_EXTENSION_REPO="https://github.com/boardcon-arm/boardcon_armbian_extension"
BOARDCON_EXTENSION_REF="branch:main"

fetch_from_repo \
	"${BOARDCON_EXTENSION_REPO}" \
	"boardcon_armbian_extension" \
	"${BOARDCON_EXTENSION_REF}"


BOARDCON_EXT_DIR="${SRC}/cache/sources/boardcon_armbian_extension"

export BOARDCON_EXT_DIR