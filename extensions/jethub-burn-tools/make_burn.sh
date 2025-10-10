#!/usr/bin/env bash
# make_burn.sh — convert Armbian .img to Amlogic burn image (JetHub J200, J100, J80)

set -euo pipefail

if ! declare -F display_alert >/dev/null 2>&1; then
  display_alert() { echo "[$3] $1: $2"; }
fi

if [[ $# -ne 2 ]]; then
  display_alert "make_burn.sh" "Usage: $0 <input.img> <jethubj80|jethubj100>" "error"
  exit 1
fi

INPUT_IMG="$1"
BOARD="$2"

BOARD_NAME="${BOARD_NAME:-$BOARD}"

display_alert "make_burn.sh" "Preparing build for ${BOARD_NAME}" "info"

for var in PACKER_PATH BINS_DIR IMAGE_CFG DTS_DIR DTS_NAME UBOOT_BIN; do
  if [[ -z "${!var:-}" ]]; then
    display_alert "make_burn.sh" "Env $var not set" "error"
    exit 1
  fi
done

[[ -f "$INPUT_IMG"          ]] || { display_alert "make_burn.sh" "Input image not found: $INPUT_IMG" "error"; exit 1; }
[[ -x "$PACKER_PATH"        ]] || { display_alert "make_burn.sh" "Packer not executable: $PACKER_PATH" "error"; exit 1; }
[[ -f "$IMAGE_CFG"          ]] || { display_alert "make_burn.sh" "Image cfg not found: $IMAGE_CFG" "error"; exit 1; }
[[ -d "$BINS_DIR"           ]] || { display_alert "make_burn.sh" "Bins dir not found: $BINS_DIR" "error"; exit 1; }
[[ -r "$BINS_DIR/platform.conf" ]] || { display_alert "make_burn.sh" "platform.conf missing in $BINS_DIR" "error"; exit 1; }
[[ -f "$DTS_DIR/$DTS_NAME"  ]] || { display_alert "make_burn.sh" "DTS not found: $DTS_DIR/$DTS_NAME" "error"; exit 1; }
[[ -f "$DTS_DIR/partition_arm.dtsi" ]] || { display_alert "make_burn.sh" "partition_arm.dtsi not found in $DTS_DIR" "error"; exit 1; }
[[ -f "$UBOOT_BIN"          ]] || { display_alert "make_burn.sh" "U-Boot not found: $UBOOT_BIN" "error"; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT_DIR="$(dirname "$INPUT_IMG")"
IMG_BASE="$(basename "$INPUT_IMG")"
IMG_NAME="${IMG_BASE%.*}"
OUT_IMG="${OUT_DIR}/${IMG_NAME}.burn.img"

display_alert "make_burn.sh" "Creating burn image for ${BOARD_NAME}" "info"

EXT="${INPUT_IMG:(-3)}"
WORK_IMG="$INPUT_IMG"
if [[ "$EXT" == ".xz" ]]; then
  display_alert "make_burn.sh" "Decompressing ${INPUT_IMG}" "info"
  WORK_IMG="${TMP_DIR}/${IMG_NAME}"
  xzcat "$INPUT_IMG" > "$WORK_IMG"
fi

mkdir -p "$TMP_DIR/dts"
cp "$DTS_DIR/$DTS_NAME"            "$TMP_DIR/dts/$DTS_NAME"
cp "$DTS_DIR/partition_arm.dtsi"   "$TMP_DIR/dts/partition_arm.dtsi"

sed -i 's#partition\.dtsi#partition_arm.dtsi#g' "$TMP_DIR/dts/$DTS_NAME"

cpp -nostdinc -I "$DTS_DIR" -I "$DTS_DIR/include" -undef -x assembler-with-cpp \
  "$TMP_DIR/dts/$DTS_NAME" "$TMP_DIR/${DTS_NAME}.pre"
dtc -I dts -O dtb -p 0x1000 -qqq "$TMP_DIR/${DTS_NAME}.pre" -o "$TMP_DIR/board.dtb"
display_alert "make_burn.sh" "DTB compiled successfully" "info"

extract_partition() {
  local img="$1" start="$2" sectors="$3" out="$4"
  dd if="$img" of="$out" bs=512 skip="$start" count="$sectors" status=none
}

FDISK=$(/usr/sbin/fdisk -l "$WORK_IMG" | \
  awk -v img="$(basename "$WORK_IMG")" '
    BEGIN {p=0}
    /Device.*Boot.*Start.*End.*Sectors.*Size.*Id.*Type/ {p=1; next}
    p && $1 ~ img {print $1, $2, $3, $4, $5, $6, $7}
  ')

i=1
while read -r Device Start End Sectors Size Id Type || [[ -n "${Device:-}" ]]; do
  [[ -z "${Device:-}" ]] && continue
  extract_partition "$WORK_IMG" "$Start" "$Sectors" "$TMP_DIR/part-$i.img"
  i=$((i+1))
done <<< "$FDISK"

cp "$BINS_DIR/platform.conf" "$TMP_DIR/"
cp "$BINS_DIR/DDR.USB"       "$TMP_DIR/"
cp "$BINS_DIR/UBOOT.USB"     "$TMP_DIR/"
cp "$IMAGE_CFG"              "$TMP_DIR/image.cfg"
cp "$UBOOT_BIN"              "$TMP_DIR/u-boot.bin"

cc -O2 -o "$TMP_DIR/dtbTool" "$(dirname "$0")/dtbtools/dtbTool.c"
display_alert "make_burn.sh" "Building _aml_dtb.PARTITION..." "info"
"$TMP_DIR/dtbTool" -o "$TMP_DIR/_aml_dtb.PARTITION" "$TMP_DIR"
[[ -s "$TMP_DIR/_aml_dtb.PARTITION" ]] || { display_alert "make_burn.sh" "Failed to create _aml_dtb.PARTITION" "error"; exit 1; }

display_alert "make_burn.sh" "Packing with Amlogic tool..." "info"
"$PACKER_PATH" -r "$TMP_DIR/image.cfg" "$TMP_DIR" "$OUT_IMG"

display_alert "make_burn.sh" "Burn image created successfully $(basename "$OUT_IMG")" "ok"
