#!/usr/bin/env bash
#
# Build (optional) and customize an Armbian ABL rootfs image for Oneplus 8t.
# On Linux: runs customizer with sudo. On macOS (Darwin): runs customizer inside Docker.
#
# Usage:
#   ./scripts/build-customized-image.sh [options] <config.yaml> [rootfs.img]
#   Options: --build    run compile.sh build first (BOARD=oneplus-kebab)
#   If rootfs.img is omitted and --build was used, uses latest *.rootfs.img in output/images.
#   If rootfs.img is omitted and --build was not used, finds latest *.rootfs.img in output/images.
#
# Example:
#   ./scripts/build-customized-image.sh --build userpatches/customized-image.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_YAML=""
ROOTFS_IMAGE=""
DO_BUILD=""

usage() {
	echo "Usage: $0 [--build] <config.yaml> [rootfs.img]" >&2
	echo "  --build       Run ./compile.sh build BOARD=oneplus-kebab first (requires BRANCH, RELEASE)" >&2
	echo "  config.yaml   Path to YAML config (e.g. userpatches/customized-image.yaml)" >&2
	echo "  rootfs.img    Optional path to existing *.rootfs.img; else latest in output/images is used" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--build) DO_BUILD=1; shift ;;
		-*) usage ;;
		*)
			if [[ -z "$CONFIG_YAML" ]]; then
				CONFIG_YAML="$1"
			elif [[ -z "$ROOTFS_IMAGE" ]]; then
				ROOTFS_IMAGE="$1"
			else
				usage
			fi
			shift
			;;
	esac
done

[[ -n "$CONFIG_YAML" ]] || usage

# Resolve config path
if [[ ! -f "$CONFIG_YAML" ]]; then
	CONFIG_YAML="${SRC}/${CONFIG_YAML}"
fi
[[ -f "$CONFIG_YAML" ]] || { echo "Error: Config not found: $CONFIG_YAML" >&2; exit 1; }
CONFIG_YAML="$(realpath "$CONFIG_YAML")"

# Build if requested
if [[ -n "$DO_BUILD" ]]; then
	echo "Running build (BOARD=oneplus-kebab)..."
	cd "$SRC"
	./compile.sh build BOARD=oneplus-kebab BRANCH="${BRANCH:-current}" RELEASE="${RELEASE:-noble}"
	cd - >/dev/null
fi

# Resolve rootfs image path
if [[ -z "$ROOTFS_IMAGE" ]]; then
	OUTPUT_IMAGES="${SRC}/output/images"
	[[ -d "$OUTPUT_IMAGES" ]] || { echo "Error: No output/images and no rootfs image path given." >&2; exit 1; }
	# Portable: find latest *.rootfs.img (ls -t by mtime)
	ROOTFS_IMAGE=$(ls -t "$OUTPUT_IMAGES"/*/*.rootfs.img "$OUTPUT_IMAGES"/*.rootfs.img 2>/dev/null | head -1)
	[[ -n "$ROOTFS_IMAGE" && -f "$ROOTFS_IMAGE" ]] || { echo "Error: No *.rootfs.img found in $OUTPUT_IMAGES. Build first or pass path." >&2; exit 1; }
fi
if [[ ! -f "$ROOTFS_IMAGE" ]]; then
	ROOTFS_IMAGE="${SRC}/${ROOTFS_IMAGE}"
fi
[[ -f "$ROOTFS_IMAGE" ]] || { echo "Error: Rootfs image not found: $ROOTFS_IMAGE" >&2; exit 1; }
ROOTFS_IMAGE="$(realpath "$ROOTFS_IMAGE")"

CUSTOMIZER="${SCRIPT_DIR}/customize-image.sh"
[[ -x "$CUSTOMIZER" ]] || { echo "Error: Customizer script not found or not executable: $CUSTOMIZER" >&2; exit 1; }

# On Darwin, run customizer inside Docker (losetup/mount require Linux).
if [[ "$(uname -s)" == "Darwin" ]]; then
	echo "Detected macOS: running customizer inside Docker (requires Docker)."
	if ! command -v docker &>/dev/null; then
		echo "Error: Docker is required on macOS to run the customizer. Install Docker Desktop and try again." >&2
		exit 1
	fi
	# Bind-mount: directory containing rootfs image, config dir, and script dir. Output next to rootfs.
	ROOTFS_DIR="$(dirname "$ROOTFS_IMAGE")"
	CONFIG_DIR="$(dirname "$CONFIG_YAML")"
	# Container will run as root; paths inside container:
	# /work/rootfs.img, /work/config.yaml, /scripts/customize-image.sh, output in /work
	docker run --rm --privileged \
		-v "${ROOTFS_DIR}:/work:rw" \
		-v "${CONFIG_DIR}:/config:ro" \
		-v "${SCRIPT_DIR}:/scripts:ro" \
		-v "/etc/resolv.conf:/etc/resolv.conf:ro" \
		-e "ROOTFS_IMAGE=/work/$(basename "$ROOTFS_IMAGE")" \
		-e "CONFIG_YAML=/config/$(basename "$CONFIG_YAML")" \
		debian:bookworm-slim \
		bash -c '
			apt-get update -qq && apt-get install -y -qq python3-yaml > /dev/null
			/scripts/customize-image.sh "$ROOTFS_IMAGE" "$CONFIG_YAML"
		'
	# Customizer writes to ROOTFS_DIR (e.g. *-customized.rootfs.img), so it appears on host.
	echo "Customized image is in: ${ROOTFS_DIR}"
	exit 0
fi

# Linux: run customizer with sudo if not root
if [[ $EUID -ne 0 ]]; then
	echo "Running customizer with sudo..."
	exec sudo "$CUSTOMIZER" "$ROOTFS_IMAGE" "$CONFIG_YAML"
else
	exec "$CUSTOMIZER" "$ROOTFS_IMAGE" "$CONFIG_YAML"
fi
