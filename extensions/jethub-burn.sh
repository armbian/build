#!/usr/bin/env bash
# Extension: jethub-burn
# Automatically converts Armbian .img into burn image after build

# Download and prepare tools
function bootstrap_tools() {
  local repo_url="https://github.com/jethome-iot/jethome-tools.git"
  local ref="commit:87be932dceb6135c99dfc5a105a6345eff954f2c"
  local name="jethub-burn"
  local base="${SRC}/cache/sources/${name}"

  display_alert "jethub-burn" "Fetching jethome-tools (${ref})..." "info"
  fetch_from_repo "${repo_url}" "${name}" "${ref}"

  local packer_path
  packer_path="$(find "${base}" -maxdepth 12 -type f -path '*/tools/aml_image_v2_packer_new' -print -quit)"
  [[ -n "${packer_path}" ]] || exit_with_error "aml_image_v2_packer_new not found under ${base}"

  declare -g TOOLS_DIR="$(dirname "$(dirname "${packer_path}")")"
  declare -g PACKER="${packer_path}"
  declare -g BINS_DIR="${TOOLS_DIR}/bins"
  declare -g DTS_DIR="${TOOLS_DIR}/dts"
  declare -g DTBTOOLS_DIR="${TOOLS_DIR}/dtbtools"
  declare -g IMAGE_CFG="${BINS_DIR}/image.armbian.cfg"

  display_alert "jethub-burn" "Tools ready (packer: ${PACKER})" "ok"
}

# Build burn image
function make_burn__run() {
  local -r input_img="$1"
  local -r board="$2"
  local -r dts_name="$3"
  local -r bins_subdir="$4"
  local -r uboot_bin="$5"

  local -r bins="${BINS_DIR}/${bins_subdir}"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local -r OUT_IMG="${DESTIMG}/${version}.burn.img"

  display_alert "make_burn" "Building burn image for ${board}" "info"

  # build _aml_dtb.PARTITION
  mkdir -p "$tmpdir/dts"
  cp "$DTS_DIR/$dts_name"          "$tmpdir/dts/$dts_name"
  cp "$DTS_DIR/partition_arm.dtsi" "$tmpdir/dts/partition_arm.dtsi"
  sed -i 's#partition\.dtsi#partition_arm.dtsi#g' "$tmpdir/dts/$dts_name"

  cpp -nostdinc -I "$DTS_DIR" -I "$DTS_DIR/include" -undef -x assembler-with-cpp "$tmpdir/dts/$dts_name" "$tmpdir/${dts_name}.pre"
  dtc -I dts -O dtb -p 0x1000 -qqq "$tmpdir/${dts_name}.pre" -o "$tmpdir/board.dtb"

  cc -O2 -o "$tmpdir/dtbTool" "$DTBTOOLS_DIR/dtbTool.c"
  "$tmpdir/dtbTool" -o "$tmpdir/_aml_dtb.PARTITION" "$tmpdir"
  display_alert "make_burn" "_aml_dtb.PARTITION built" "info"

  display_alert "make_burn" "Extracting partitions (losetup -P)..." "info"
  local loopdev
  loopdev="$(losetup --find --show -P "$input_img")" || exit_with_error "losetup failed for $input_img"
  trap 'losetup -d "$loopdev" 2>/dev/null || true; rm -rf "$tmpdir"' RETURN

  local i=1 found=0
  for p in $(ls -1 "${loopdev}"p* 2>/dev/null | sort -V); do
    found=1
    display_alert "make_burn" "Copying $(basename "$p") → part-$i.img" "info"
    dd if="$p" of="$tmpdir/part-$i.img" bs=4M status=none || exit_with_error "dd failed for $p"
    i=$((i+1))
  done
  [[ $found -eq 1 ]] || exit_with_error "No partitions detected on $input_img"

  cp "$bins/platform.conf" "$tmpdir/"
  cp "$bins/DDR.USB"       "$tmpdir/"
  cp "$bins/UBOOT.USB"     "$tmpdir/"
  cp "$IMAGE_CFG"          "$tmpdir/image.cfg"
  cp "$uboot_bin"          "$tmpdir/u-boot.bin"

  display_alert "make_burn" "Packing burn image..." "info"
  "$PACKER" -r "$tmpdir/image.cfg" "$tmpdir" "$OUT_IMG" || exit_with_error "Image pack FAILED"

  [[ -f "$OUT_IMG" ]] || exit_with_error "Burn image not produced"
  display_alert "make_burn" "Burn image created: $(basename "$OUT_IMG")" "ok"
}

function post_build_image__900_jethub_burn() {
  [[ -z $version ]] && exit_with_error "version is not set"

  local -r original_image_file="${DESTIMG}/${version}.img"
  [[ -f "$original_image_file" ]] || exit_with_error "Original image not found: $original_image_file"

  local dts_name bins_subdir
  case "${BOARD}" in
    jethubj80)  dts_name="meson-gxl-s905w-jethome-jethub-j80.dts";  bins_subdir="j80"  ;;
    jethubj100) dts_name="meson-axg-jethome-jethub-j100.dts";       bins_subdir="j100" ;;
    jethubj200) dts_name="meson-sm1-jethome-jethub-j200.dts";       bins_subdir="j200" ;;
    *) exit_with_error "Unsupported board: ${BOARD} (supported: j80, j100, j200)";;
  esac

  display_alert "Converting image to Amlogic burn format" "jethub-burn :: ${BOARD}" "info"

  bootstrap_tools

  local -r debs_dir="${SRC}/output/debs"
  local uboot_deb uboot_bin
  uboot_deb=$(find "${debs_dir}" -maxdepth 1 -type f -name "linux-u-boot-${BOARD}-*.deb" | sort -V | tail -n1)
  [[ -n "${uboot_deb}" ]] || exit_with_error "u-boot deb not found for ${BOARD}"
  local tmp_dir; tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN
  mkdir -p "${tmp_dir}/deb-uboot"
  dpkg -x "${uboot_deb}" "${tmp_dir}/deb-uboot"
  uboot_bin=$(find "${tmp_dir}/deb-uboot/usr/lib" -type f -name "u-boot.nosd.bin" | head -n1)
  [[ -n "${uboot_bin}" ]] || exit_with_error "u-boot.nosd.bin not found in deb"

  make_burn__run "${original_image_file}" "${BOARD}" "${dts_name}" "${bins_subdir}" "${uboot_bin}"

  display_alert "jethub-burn" "Burn image prepared (pre-checksum stage)" "ok"
}
