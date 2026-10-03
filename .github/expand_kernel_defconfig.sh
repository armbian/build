#!/usr/bin/env bash
#
# Expand an Armbian kernel defconfig to a full .config.
#
# kernel-hardening-checker needs a full .config: it reads the kernel version
# and architecture from its header, and a defconfig omits every default value.
#
# Usage: expand_kernel_defconfig.sh <config> <output .config> [source cache dir]
#
# The kernel version comes from the "# Armbian defconfig generated with X.Y"
# header. The architecture is the one that keeps the most of the defconfig's
# options after olddefconfig. A full .config is copied as is.

set -euo pipefail

in="${1:?config file}"
out="${2:?output file}"
cache="${3:-${RUNNER_TEMP:-/tmp}/kernel-src}"

if head -n 5 "${in}" | grep -q '^# Linux/.* Kernel Configuration'; then
	cp "${in}" "${out}"
	exit 0
fi

version="$(sed -n 's/^# Armbian defconfig generated with \([0-9]*\.[0-9]*\).*/\1/p' "${in}" | head -n 1)"
[[ -n "${version}" ]] || {
	echo "No kernel version in ${in}" >&2
	exit 1
}

src="${cache}/linux-${version}"
if [[ ! -f "${src}/Makefile" ]]; then
	mkdir -p "${src}"
	url="https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x/linux-${version}.tar.xz"
	if ! curl -fsSL "${url}" | tar -xJ --strip-components=1 -C "${src}"; then
		# Not released yet (rc): use mainline
		rm -rf "${src}"
		git clone -q --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git "${src}"
	fi
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
grep -E '^CONFIG_[A-Za-z0-9_]+=' "${in}" | sort -u > "${work}/wanted"

best="" best_kept=-1
for arch in arm64 arm x86 riscv loongarch; do
	mkdir -p "${work}/${arch}"
	cp "${in}" "${work}/${arch}/.config"
	make -s -C "${src}" O="${work}/${arch}" ARCH="${arch}" olddefconfig > /dev/null 2>&1 || continue
	kept="$(grep -cxFf "${work}/wanted" "${work}/${arch}/.config" || true)"
	if ((kept > best_kept)); then
		best="${arch}" best_kept="${kept}"
	fi
done

[[ -n "${best}" ]] || {
	echo "olddefconfig failed for ${in}" >&2
	exit 1
}
echo "${in}: linux-${version}, ARCH=${best}, kept ${best_kept}/$(wc -l < "${work}/wanted") options" >&2
cp "${work}/${best}/.config" "${out}"
