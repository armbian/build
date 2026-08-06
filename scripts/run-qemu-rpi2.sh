#!/usr/bin/env bash
# Boot the rpi2b Armbian image in QEMU (raspi2b machine) for smoke-testing
# this board/family without real hardware.
#
# Armbian doesn't deploy a separate kernel/DTB alongside the disk image --
# everything lives inside the single .img's own /boot/firmware FAT
# partition (see config/sources/families/bcm2836.conf). QEMU's raspi2b
# machine doesn't emulate the Pi's GPU boot ROM chain, so this script has
# to extract vmlinuz + the DTB from that partition first, then hand them
# to QEMU directly via -kernel/-dtb, with the *whole* image still attached
# as the emulated SD card for the root filesystem.
#
# Deliberately does NOT use losetup/mount: some CI containers have no
# /dev/loop-control access and aren't privileged. Uses `sfdisk -d` to read
# the MBR straight out of the image file (no device node needed), `dd` to
# slice out just the boot partition's bytes, and `mtools` to read files
# out of that FAT partition directly as a plain file -- no mount, no loop
# device, no root required at all.
#
# Prerequisites:
#   - qemu-system-arm, mtools, util-linux (sfdisk -- present by default on
#     any Debian/Ubuntu base), xz-utils if the image is .img.xz
#   - A completed build: ./compile.sh BOARD=rpi2b BRANCH=current
#     BUILD_MINIMAL=yes KERNEL_ONLY=no RELEASE=bookworm
#
# Usage:
#   ./scripts/run-qemu-rpi2.sh
#   ./scripts/run-qemu-rpi2.sh --net          # user-mode networking (SSH fwd :2222)
#   ./scripts/run-qemu-rpi2.sh --net --daemon   # background; serial -> logs/qemu-rpi2-serial.log
#   ./scripts/run-qemu-rpi2.sh --image /path/to/some.img
#
# Expect serial console on stdout. First-boot credentials: root / 1234
# (Armbian's own stock unconfigured default -- change it, don't ship it).
#
# Verified end-to-end: kernel boots, both partitions are detected, ext4
# root filesystem mounts, init launches. Required the devicetree fix in
# patch/kernel/bcm2836-current/ -- without it, boot panics unable to
# mount root (see that patch's commit message for the full root cause).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARMBIAN_BUILD_DIR="${ARMBIAN_BUILD_DIR:-${ROOT}}"
WORK_DIR="${ROOT}/tmp-work"

IMAGE=""
NET=0
DAEMON=0
SSH_PORT="${RPI2_QEMU_SSH_PORT:-2222}"
SERIAL_LOG="${ROOT}/logs/qemu-rpi2-serial.log"
PID_FILE="${ROOT}/logs/qemu-rpi2.pid"

usage() { sed -n '1,26p' "$0"; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		--net)
			NET=1
			shift
			;;
		--daemon)
			DAEMON=1
			shift
			;;
		--image)
			shift
			IMAGE="${1:?--image requires a path}"
			shift
			;;
		*)
			echo "error: unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

for tool in qemu-system-arm sfdisk mcopy dd; do
	command -v "$tool" > /dev/null 2>&1 || {
		echo "error: $tool not found" >&2
		exit 1
	}
done

if [[ -z "$IMAGE" ]]; then
	images_dir="${ARMBIAN_BUILD_DIR}/output/images"
	# -iname, not -name: Armbian's own output naming title-cases the board
	# name (e.g. "Armbian-unofficial_..._Rpi2b_bookworm_....img"), so a
	# case-sensitive glob for "rpi2b" never matches. Confirmed via a real
	# CI run failing here on 2026-08-05 with the build otherwise succeeded.
	IMAGE="$(find "$images_dir" -maxdepth 1 -type f \( -iname '*rpi2b*.img' -o -iname '*rpi2b*.img.xz' \) | sort | tail -n1)"
	if [[ -z "$IMAGE" ]]; then
		echo "error: no rpi2b image found under $images_dir" >&2
		echo "Build it first: ./compile.sh BOARD=rpi2b BRANCH=current BUILD_MINIMAL=yes KERNEL_ONLY=no RELEASE=bookworm" >&2
		exit 1
	fi
fi

mkdir -p "$WORK_DIR"
RAW_IMG="${WORK_DIR}/$(basename "${IMAGE%.xz}")"
if [[ "$IMAGE" == *.xz ]]; then
	if [[ ! -f "$RAW_IMG" || "$IMAGE" -nt "$RAW_IMG" ]]; then
		echo "Decompressing $(basename "$IMAGE") -> $RAW_IMG"
		xzcat "$IMAGE" > "${RAW_IMG}.tmp"
		mv "${RAW_IMG}.tmp" "$RAW_IMG"
	fi
else
	cp -f "$IMAGE" "$RAW_IMG"
fi

# QEMU's raspi2b SD controller requires a power-of-2 size; round up.
size_mib=$(($(stat -c %s "$RAW_IMG") / 1048576 + 1))
pow2_mib=1
while ((pow2_mib < size_mib)); do pow2_mib=$((pow2_mib * 2)); done
qemu-img resize -f raw "$RAW_IMG" "${pow2_mib}M" > /dev/null

# Extract vmlinuz + DTB from the image's first (FAT, /boot/firmware)
# partition -- no loop device, no mount, no root. sfdisk reads the MBR
# directly from the image file; dd slices out just that partition's bytes
# (sfdisk reports sector counts, sector size is always 512 for these
# images); mtools reads files out of the resulting FAT partition image
# as a plain file.
part1_line="$(sfdisk -d "$RAW_IMG" 2>/dev/null | grep -E '^\S+1\s*:')"
[[ -n "$part1_line" ]] || {
	echo "error: could not read partition 1 from $RAW_IMG via sfdisk -d" >&2
	exit 1
}
start_sector="$(grep -oE 'start=\s*[0-9]+' <<< "$part1_line" | grep -oE '[0-9]+')"
size_sectors="$(grep -oE 'size=\s*[0-9]+' <<< "$part1_line" | grep -oE '[0-9]+')"
BOOT_PART_IMG="${WORK_DIR}/rpi2b-boot-partition.img"
dd if="$RAW_IMG" of="$BOOT_PART_IMG" bs=512 skip="$start_sector" count="$size_sectors" status=none

KERNEL="${WORK_DIR}/rpi2b-vmlinuz"
DTB="${WORK_DIR}/rpi2b.dtb"
mcopy -n -i "$BOOT_PART_IMG" ::vmlinuz "$KERNEL"
mcopy -n -i "$BOOT_PART_IMG" ::bcm2836-rpi-2-b.dtb "$DTB"

QEMU_OPTS=(
	-M raspi2b
	-m 1024
	-kernel "$KERNEL"
	-dtb "$DTB"
	-drive "file=${RAW_IMG},if=sd,format=raw"
	# TCG-under-QEMU workarounds: raspi2b needs 4 vCPUs but its SMP
	# timer/IPI emulation trips RCU stalls under TCG, and dwc_otg's
	# FIQ-based DMA path hangs the emulated USB controller.
	-append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw rootwait maxcpus=1 dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0"
	-display none
)

if [[ "$DAEMON" -eq 1 ]]; then
	mkdir -p "$(dirname "$SERIAL_LOG")"
	QEMU_OPTS+=(-serial "file:${SERIAL_LOG}")
	QEMU_OPTS+=(-daemonize)
else
	QEMU_OPTS+=(-serial stdio)
fi

if [[ "$NET" -eq 1 ]]; then
	# NOT VERIFIED: assumes the built image carries a usb-net-capable
	# driver (e.g. cdc_ether) for QEMU's emulated USB NIC. Armbian's
	# default module set for this board hasn't been checked.
	QEMU_OPTS+=(
		-netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
		-device "usb-net,netdev=net0"
	)
fi

if [[ "$DAEMON" -eq 1 ]]; then
	echo "Booting rpi2b in background (serial: ${SERIAL_LOG})"
	qemu-system-arm "${QEMU_OPTS[@]}"
	sleep 2
	pgrep -f "qemu-system-arm.*raspi2b.*${RAW_IMG}" | head -1 > "$PID_FILE" || true
	[[ "$NET" -eq 1 ]] && echo "SSH when ready: ssh -p ${SSH_PORT} root@localhost"
	exit 0
fi

echo "Booting rpi2b (serial console; Ctrl-A X to quit QEMU)"
exec qemu-system-arm "${QEMU_OPTS[@]}"
