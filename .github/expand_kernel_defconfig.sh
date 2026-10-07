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
		# Not released yet: use the latest rc tag of this version, never another version
		rm -rf "${src}"
		mainline="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
		tag="$(git ls-remote --tags --refs "${mainline}" "v${version}-rc*" | sed 's|.*refs/tags/||' | sort -V | tail -n 1)"
		[[ -n "${tag}" ]] || {
			echo "No source for linux-${version}" >&2
			exit 1
		}
		git clone -q --depth 1 --branch "${tag}" "${mainline}" "${src}"
	fi
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' "${in}" | sort -u > "${work}/wanted"
wanted="$(wc -l < "${work}/wanted")"

# Pick the architecture that keeps the most explicit settings. Require a clear
# winner that keeps at least 90%, else the checker would assess another architecture.
best="" best_kept=-1 second_kept=-1
for arch in arm64 arm x86 riscv loongarch; do
	mkdir -p "${work}/${arch}"
	cp "${in}" "${work}/${arch}/.config"
	make -s -C "${src}" O="${work}/${arch}" ARCH="${arch}" olddefconfig > /dev/null 2>&1 || continue
	kept="$(grep -cxFf "${work}/wanted" "${work}/${arch}/.config" || true)"
	if ((kept > best_kept)); then
		second_kept="${best_kept}" best="${arch}" best_kept="${kept}"
	elif ((kept > second_kept)); then
		second_kept="${kept}"
	fi
done

if [[ -z "${best}" ]] || ((best_kept * 10 < wanted * 9 || best_kept == second_kept)); then
	echo "${in}: cannot identify the architecture (best ${best:-none} kept ${best_kept}/${wanted})" >&2
	exit 1
fi
echo "${in}: linux-${version}, ARCH=${best}, kept ${best_kept}/${wanted} settings" >&2
cp "${work}/${best}/.config" "${out}"
