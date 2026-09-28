#!/usr/bin/env bash
# Build the Ubuntu GRUB source version found in the reference image.
set -euo pipefail
src=${1:?Armbian source directory required}
jobs=${2:--j4}
work="$src/cache/grub-2.06-2ubuntu16"
downloads="$src/cache/sources/grub-download"
prefix="$work/install"
mkdir -p "$downloads" "$work"
exec 9>"$work/build.lock"
flock 9
if [[ -f $work/build-complete-call-plt && -x $prefix/bin/grub-mkimage && -f $prefix/lib/grub/riscv64-efi/linux.mod ]]; then
	exit 0
fi
base=https://old-releases.ubuntu.com/ubuntu/pool/main/g/grub2
for filename in grub2_2.06-2ubuntu16.dsc grub2_2.06.orig.tar.xz grub2_2.06-2ubuntu16.debian.tar.xz; do
	[[ -f $downloads/$filename ]] || curl --fail --location --retry 3 "$base/$filename" -o "$downloads/$filename"
done
cd "$downloads"
sha256sum --check <<-'EOF_SUM'
	b79ea44af91b93d17cd3fe80bdae6ed43770678a9a5ae192ccea803ebb657ee1  grub2_2.06.orig.tar.xz
	3640d1be94234a98bfa489d1f9f4d227c871037cd39e0a2702ae8781010eac86  grub2_2.06-2ubuntu16.debian.tar.xz
EOF_SUM
if [[ ! -d $work/source ]]; then
	dpkg-source --no-check -x grub2_2.06-2ubuntu16.dsc "$work/source"
fi
cd "$work/source"
# Backport the three-line RISC-V relocation compatibility fix for binutils >= 2.40.
# https://lists.gnu.org/archive/html/grub-devel/2023-02/msg00143.html
python3 - <<-'PY'
	from pathlib import Path
	for filename, expected in (("grub-core/kern/riscv/dl.c", 1), ("util/grub-mkimagexx.c", 2)):
	    path = Path(filename)
	    text = path.read_text()
	    if "case R_RISCV_CALL_PLT:" in text:
	        assert text.count("case R_RISCV_CALL_PLT:") == expected
	        continue
	    assert text.count("case R_RISCV_CALL:") == expected
	    lines = []
	    for line in text.splitlines(keepends=True):
	        lines.append(line)
	        if "case R_RISCV_CALL:" in line:
	            lines.append(line.replace("R_RISCV_CALL:", "R_RISCV_CALL_PLT:"))
	    path.write_text("".join(lines))
PY
PYTHON=python3 ./autogen.sh
mkdir -p "$work/build"
cd "$work/build"
"$work/source/configure" --prefix="$prefix" --target=riscv64-linux-gnu \
	--with-platform=efi --disable-werror --disable-nls --disable-device-mapper \
	--disable-libzfs --disable-grub-mount --disable-efiemu
make "$jobs"
make install
touch "$work/build-complete-call-plt"
