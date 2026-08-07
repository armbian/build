#!/usr/bin/env bash
# Boot the rpi3b Armbian image in QEMU (raspi2b machine -- see below).
# Sibling of scripts/run-qemu-rpi2.sh (armbian/build#10355) -- same
# approach, same reasoning, just retargeted at BCM2837. See that script's
# header for the full rationale; this one only calls out what's actually
# different for rpi3b.
#
# Armbian doesn't deploy a separate kernel/DTB alongside the disk image --
# everything lives inside the single .img's own /boot/firmware FAT
# partition (see config/sources/families/bcm2837.conf). QEMU's raspi
# machine models don't emulate the Pi's GPU boot ROM chain, so this script
# has to extract vmlinuz + the DTB from that partition first, then hand
# them to QEMU directly via -kernel/-dtb, with the *whole* image still
# attached as the emulated SD card for the root filesystem.
#
# Deliberately does NOT use losetup/mount -- same CI-container constraint
# as run-qemu-rpi2.sh (no /dev/loop-control access, unprivileged). Uses
# `sfdisk -d` to read the MBR straight out of the image file, `dd` to slice
# out just the boot partition's bytes, and `mtools` to read files out of
# that FAT partition directly as a plain file -- no mount, no loop device,
# no root required at all.
#
# This board is primarily meant for real-hardware testing (see
# config/boards/rpi3b.wip -- confirmed booting on a physical Pi 3 Model B),
# but running it under QEMU first as a CI smoke test catches build-level
# breakage (wrong patch paths, missing configs, etc.) before ever touching
# real hardware, same value rpi2's QEMU step already provides.
#
# Boots via -M raspi2b, not raspi3b -- confirmed directly (2026-08-07) that
# QEMU's raspi3b machine is hardcoded AArch64-only: there's no auto-detect
# of a 32-bit zImage the way real Pi 3/4 firmware does (that was a wrong
# assumption in an earlier version of this script). Feeding it our 32-bit
# armhf kernel just parks the CPU at PC=0x200 in AArch64 EL2 forever, zero
# serial output, confirmed live via the QEMU monitor's `info registers`.
# Only raspi2b supports AArch32 kernels in QEMU. That's fine here: bcm2836
# and bcm2837 share the same peripheral memory map (DMA, MMC/SD, PL011
# UART, mailbox all initialize identically), confirmed by manually booting
# this exact rpi3b kernel+DTB under raspi2b -- reaches /sbin/init cleanly,
# same path rpi2 already takes. This is a QEMU testing-only substitution;
# it has no bearing on real hardware, which boots the 32-bit kernel natively.
#
# Prerequisites:
#   - qemu-system-arm (not qemu-system-aarch64 -- see above)
#   - qemu-utils (qemu-img), mtools, util-linux (sfdisk -- present by
#     default on any Debian/Ubuntu base), xz-utils if the image is .img.xz
#   - A completed build: ./compile.sh BOARD=rpi3b BRANCH=current BUILD_MINIMAL=yes KERNEL_ONLY=no RELEASE=bookworm
#
# Usage:
#   ./scripts/run-qemu-rpi3.sh
#   ./scripts/run-qemu-rpi3.sh --net          # user-mode networking (SSH fwd :2222)
#   ./scripts/run-qemu-rpi3.sh --net --daemon   # background; serial -> logs/qemu-rpi3-serial.log
#   ./scripts/run-qemu-rpi3.sh --image /path/to/some.img
#
# Expect serial console on stdout. First-boot credentials: root / 1234
# (Armbian's own stock unconfigured default -- change it, don't ship it).
#
# Verified two ways as of 2026-08-07:
#   1. Real hardware: this image boots clean on a physical Pi 3 Model B --
#      dmesg shows bcm2835-dma initializing, mmc0 detecting the real SD
#      card, no warnings or errors, stable shell over SSH.
#   2. Under QEMU (this script, raspi2b): DMA (bcm2835-dma), MMC/SD
#      (sdhost-bcm2835), and PL011 UART all init cleanly, root mounts,
#      /sbin/init runs -- same path as rpi2's own fix (dma-ranges gap,
#      patch/kernel/archive/bcm2837-6.18/). Reaching an actual login
#      prompt under QEMU is much slower than rpi2's own ~200s (a heavily
#      loaded CI runner pushed this well past 20 minutes in testing) --
#      budget generously if scripting a wait loop around this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARMBIAN_BUILD_DIR="${ARMBIAN_BUILD_DIR:-${ROOT}/.armbian-build}"
WORK_DIR="${ROOT}/tmp-work"

IMAGE=""
NET=0
DAEMON=0
SSH_PORT="${RPI3_QEMU_SSH_PORT:-2222}"
SERIAL_LOG="${ROOT}/logs/qemu-rpi3-serial.log"
PID_FILE="${ROOT}/logs/qemu-rpi3.pid"

usage() {
	cat <<-'EOF'
		Usage:
		  ./scripts/run-qemu-rpi3.sh
		  ./scripts/run-qemu-rpi3.sh --net          # user-mode networking (SSH fwd :2222)
		  ./scripts/run-qemu-rpi3.sh --net --daemon   # background; serial -> logs/qemu-rpi3-serial.log
		  ./scripts/run-qemu-rpi3.sh --image /path/to/some.img

		Expect serial console on stdout. First-boot credentials: root / 1234
		(Armbian's own stock unconfigured default -- change it, don't ship it).
	EOF
}

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

for tool in qemu-system-arm qemu-img sfdisk mcopy dd; do
	command -v "$tool" > /dev/null 2>&1 || {
		echo "error: $tool not found" >&2
		exit 1
	}
done

if [[ -z "$IMAGE" ]]; then
	images_dir="${ARMBIAN_BUILD_DIR}/output/images"
	if [[ -d "$images_dir" ]]; then
		# -iname, not -name: Armbian's own output naming title-cases the board
		# name (e.g. "Armbian-unofficial_..._Rpi3b_bookworm_....img") -- same
		# case-sensitivity lesson rpi2's script already learned the hard way.
		IMAGE="$(find "$images_dir" -maxdepth 1 -type f \( -iname '*rpi3b*.img' -o -iname '*rpi3b*.img.xz' \) | sort | tail -n1)"
	fi
	if [[ -z "$IMAGE" ]]; then
		echo "error: no rpi3b image found under $images_dir" >&2
		echo "Build it first: ./compile.sh BOARD=rpi3b BRANCH=current BUILD_MINIMAL=yes KERNEL_ONLY=no RELEASE=bookworm" >&2
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

# QEMU's raspi3b SD controller requires a power-of-2 size; round up.
# Ceiling division, not a flat "+1" -- same fix rpi2's script needed.
image_bytes=$(stat -c %s "$RAW_IMG")
size_mib=$(((image_bytes + 1048576 - 1) / 1048576))
pow2_mib=1
while ((pow2_mib < size_mib)); do pow2_mib=$((pow2_mib * 2)); done
qemu-img resize -f raw "$RAW_IMG" "${pow2_mib}M" > /dev/null

# Extract vmlinuz + DTB from the image's first (FAT, /boot/firmware)
# partition -- no loop device, no mount, no root. sfdisk reads the MBR
# directly from the image file; dd slices out just that partition's bytes;
# mtools reads files out of the resulting FAT partition image as a plain
# file.
part1_line="$(sfdisk -d "$RAW_IMG" 2>/dev/null | grep -E '^\S+1\s*:')"
[[ -n "$part1_line" ]] || {
	echo "error: could not read partition 1 from $RAW_IMG via sfdisk -d" >&2
	exit 1
}
start_sector="$(grep -oE 'start=\s*[0-9]+' <<< "$part1_line" | grep -oE '[0-9]+')"
size_sectors="$(grep -oE 'size=\s*[0-9]+' <<< "$part1_line" | grep -oE '[0-9]+')"
BOOT_PART_IMG="${WORK_DIR}/rpi3b-boot-partition.img"
dd if="$RAW_IMG" of="$BOOT_PART_IMG" bs=512 skip="$start_sector" count="$size_sectors" status=none

KERNEL="${WORK_DIR}/rpi3b-vmlinuz"
DTB="${WORK_DIR}/rpi3b.dtb"
mcopy -n -i "$BOOT_PART_IMG" ::vmlinuz "$KERNEL"
mcopy -n -i "$BOOT_PART_IMG" ::bcm2837-rpi-3-b.dtb "$DTB"

QEMU_OPTS=(
	# raspi2b, not raspi3b -- see header comment. QEMU's raspi3b machine is
	# AArch64-only and can't run this 32-bit armhf kernel at all (confirmed:
	# CPU parks at PC=0x200 in EL2, zero serial output, forever). bcm2836
	# and bcm2837 share the same peripheral layout closely enough that
	# raspi2b boots this kernel+DTB cleanly as a QEMU-only stand-in.
	-M raspi2b
	-m 1024
	-kernel "$KERNEL"
	-dtb "$DTB"
	-drive "file=${RAW_IMG},if=sd,format=raw"
	# Same TCG-under-QEMU workarounds as rpi2's script: maxcpus=1 avoids
	# SMP timer/IPI emulation trouble under TCG, dwc_otg's FIQ-based DMA
	# path needs disabling for the emulated USB controller.
	#
	# systemd default-timeout override: carried over from rpi2's fix (same
	# class of very-TCG-slow-boot issue expected here too). Setting both
	# systemd.default_timeout_start_sec and systemd.default_device_timeout_sec
	# -- the latter alone silently did nothing on rpi2 (needs systemd newer
	# than what Debian bookworm ships; unrecognized kernel params are just
	# ignored, no error, so it looked like it should have worked and didn't).
	# systemd.default_timeout_start_sec is the old/universal one that
	# actually governs this timeout. Real hardware wouldn't need this at all.
	-append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw rootwait maxcpus=1 dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0 systemd.default_timeout_start_sec=600 systemd.default_device_timeout_sec=600"
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
	# driver for QEMU's emulated USB NIC. Armbian's default module set
	# for this board hasn't been checked.
	QEMU_OPTS+=(
		-netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
		-device "usb-net,netdev=net0"
	)
fi

if [[ "$DAEMON" -eq 1 ]]; then
	echo "Booting rpi3b in background (serial: ${SERIAL_LOG})"
	qemu-system-arm "${QEMU_OPTS[@]}"
	sleep 2
	pgrep -f "qemu-system-arm.*raspi2b.*${RAW_IMG}" | head -1 > "$PID_FILE" || true
	[[ "$NET" -eq 1 ]] && echo "SSH when ready: ssh -p ${SSH_PORT} root@localhost"
	exit 0
fi

echo "Booting rpi3b (serial console; Ctrl-A X to quit QEMU)"
exec qemu-system-arm "${QEMU_OPTS[@]}"
