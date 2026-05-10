#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function deploy_qemu_binary_to_chroot() {
	declare chroot_target="${1}" caller="${2}"
	display_alert "deploy_qemu_binary_to_chroot" "deploy_qemu_binary_to_chroot '${chroot_target}' during '${caller}'" "debug"

	# Only deploy the binary if we're actually building a non-native architecture.
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native build" "not deploying qemu binary during ${caller}" "debug"
		return 0
	fi

	# Native armhf path is active: kernel binfmt_elf executes 32-bit ARM ELF via
	# CONFIG_COMPAT, no qemu-arm-static needed inside the chroot.
	if [[ "${ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF:-no}" == "yes" ]]; then
		display_alert "Native armhf via binfmt_elf" "skipping qemu binary deployment during ${caller}" "info"
		return 0
	fi

	# Source: try the historical name first (qemu-<arch>-static), fall back
	# to the bare name shipped by Ubuntu resolute's qemu-user-binfmt package
	# (e.g. /usr/bin/qemu-aarch64).
	declare qemu_no_suffix="${QEMU_BINARY%-static}"
	declare src_host=""
	if [[ -f "/usr/bin/${QEMU_BINARY}" ]]; then
		src_host="/usr/bin/${QEMU_BINARY}"
	elif [[ -f "/usr/bin/${qemu_no_suffix}" ]]; then
		src_host="/usr/bin/${qemu_no_suffix}"
	else
		exit_with_error "Missing qemu binary on host: tried /usr/bin/${QEMU_BINARY} and /usr/bin/${qemu_no_suffix}"
	fi

	# Destination: deploy under both names so the chroot resolves whichever
	# path the host's binfmt registration points at — the older qemu-user-
	# static package registers /usr/bin/qemu-<arch>-static, while resolute's
	# qemu-user-binfmt registers /usr/bin/qemu-<arch>.
	declare dst_target="${chroot_target}/usr/bin/${QEMU_BINARY}"
	declare dst_target_alt="${chroot_target}/usr/bin/${qemu_no_suffix}"
	declare dst_target_bkp="${dst_target}.armbian.orig"
	declare dst_target_alt_bkp="${dst_target_alt}.armbian.orig"

	# Assume we're getting a clean base to work with. Namely, we count on the rootfs cache to _not_ have left a dangling binary.
	# If the dst_target already exists, it means the target actually has the qemu-static package installed.
	# In that case, we preserve the original binary; it will be restored by the undeploy.
	if [[ -f "${dst_target}" ]]; then
		display_alert "Preserving existing qemu binary" "${QEMU_BINARY} during ${caller}" "info"
		run_host_command_logged mv -v "${dst_target}" "${dst_target_bkp}"
	fi
	if [[ "${dst_target}" != "${dst_target_alt}" && -f "${dst_target_alt}" ]]; then
		display_alert "Preserving existing qemu binary" "${qemu_no_suffix} during ${caller}" "info"
		run_host_command_logged mv -v "${dst_target_alt}" "${dst_target_alt_bkp}"
	fi

	display_alert "Deploying qemu-user-static binary to chroot" "${QEMU_BINARY} during ${caller} (from ${src_host})" "info"
	run_host_command_logged cp -pv "${src_host}" "${dst_target}"
	if [[ "${dst_target}" != "${dst_target_alt}" ]]; then
		run_host_command_logged cp -pv "${src_host}" "${dst_target_alt}"
	fi

	return 0
}

function undeploy_qemu_binary_from_chroot() {
	declare chroot_target="${1}" caller="${2}"
	display_alert "undeploy_qemu_binary_from_chroot" "undeploy_qemu_binary_from_chroot '${chroot_target}' during '${caller}'" "debug"

	# Only deploy the binary if we're actually building a non-native architecture.
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native build" "not deploying qemu binary during ${caller}" "debug"
		return 0
	fi

	declare qemu_no_suffix="${QEMU_BINARY%-static}"
	declare dst_target="${chroot_target}/usr/bin/${QEMU_BINARY}"
	declare dst_target_alt="${chroot_target}/usr/bin/${qemu_no_suffix}"
	declare dst_target_bkp="${dst_target}.armbian.orig"
	declare dst_target_alt_bkp="${dst_target_alt}.armbian.orig"

	# Check the binary we deployed is there. Two reasons it might be missing:
	#   1. ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF was active when the matching deploy
	#      ran, so nothing was copied — graceful no-op.
	#   2. Genuine state loss — panic, we lost control.
	# We must NOT skip the removal solely on the native-armhf flag, because deploy
	# may have run before that flag was set (rootfs-create deploys at line 134,
	# native-armhf flips at line 149); skipping the undeploy in that case leaks
	# the host's qemu-arm-static into the rootfs cache tarball.
	if [[ ! -f "${dst_target}" ]]; then
		if [[ "${ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF:-no}" == "yes" ]]; then
			display_alert "Native armhf via binfmt_elf" "no qemu binary to remove during ${caller}" "debug"
			return 0
		fi
		exit_with_error "Missing qemu binary during undeploy_qemu_binary_from_chroot from ${caller}"
	fi

	# Remove the binary we deployed, and restore the original if we had to preserve it.
	display_alert "Removing qemu-user-static binary from chroot" "${QEMU_BINARY} during ${caller}" "info"
	run_host_command_logged rm -fv "${dst_target}"
	if [[ "${dst_target}" != "${dst_target_alt}" && -f "${dst_target_alt}" ]]; then
		run_host_command_logged rm -fv "${dst_target_alt}"
	fi

	if [[ -f "${dst_target_bkp}" ]]; then
		display_alert "Restoring original qemu binary" "${QEMU_BINARY} during ${caller}" "info"
		run_host_command_logged mv -v "${dst_target_bkp}" "${dst_target}"
	fi
	if [[ "${dst_target}" != "${dst_target_alt}" && -f "${dst_target_alt_bkp}" ]]; then
		display_alert "Restoring original qemu binary" "${qemu_no_suffix} during ${caller}" "info"
		run_host_command_logged mv -v "${dst_target_alt_bkp}" "${dst_target_alt}"
	fi

	return 0
}

# "enable arm binary format so that the cross-architecture chroot environment will work" - classic comment from 2013
# this is called from prepare-host.sh::prepare_host_noninteractive() unconditionally.
function prepare_host_binfmt_qemu() {
	# NEEDS_BINFMT=yes is set by "default build" (image build) and rootfs artifact build, which is what requires binfmt_misc to be working.
	if [[ "${NEEDS_BINFMT:-"no"}" != "yes" ]]; then
		return 0
	fi

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Debugging binfmt - early" "/proc/sys/fs/binfmt_misc/" "debug"
		run_host_command_logged ls -la /proc/sys/fs/binfmt_misc/ || true
	fi

	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native arch build" "target ${ARCH} on host $(dpkg --print-architecture)" "cachehit"
	else
		prepare_host_binfmt_qemu_cross
	fi

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Debugging binfmt - late" "/proc/sys/fs/binfmt_misc/" "debug"
		run_host_command_logged ls -la /proc/sys/fs/binfmt_misc/ || true
	fi

	# Actually test, using `arch-test`, that we can run binaries for the wanted architecture.
	display_alert "checking" "arch-test for '${ARCH}'" "info"
	run_host_command_logged arch-test "${ARCH}"

	# Everything should be either setup or previously correct if we get here.
	return 0
}

# Native armhf on aarch64 host: runtime-disable qemu-arm in binfmt_misc so 32-bit
# ARM ELF falls through to kernel binfmt_elf and runs natively via CONFIG_COMPAT
# (~12× faster than qemu emulation). Killswitch: NATIVE_ARMHF_ON_ARM64=no.
#
# Multi-build coordination is purely kernel-level: each builder holds LOCK_SH on
# /proc/sys/fs/binfmt_misc/qemu-arm; first-arrival `echo 0`, last-out (LOCK_EX-NB
# succeeds → no other SH holders) `echo 1`. No userspace state, no per-builder
# files. Trade-off: an admin's pre-existing `disabled` state is not preserved
# across the build window.

# Read the qemu-arm 'enabled' flag without touching it. Echoes one of:
#   1       — registered and enabled
#   0       — registered and disabled
#   missing — not registered
function _native_armhf_observe_qemu_arm_state() {
	if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
		echo "missing"
		return 0
	fi
	if head -1 /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null | grep -q '^enabled'; then
		echo "1"
	else
		echo "0"
	fi
}

function _native_armhf_setup_binfmt_elf() {
	case "${NATIVE_ARMHF_ON_ARM64:-auto}" in
		no | never | disabled) return 1 ;;
	esac

	# Idempotent: callers in rootfs-create.sh and rootfs-image.sh invoke this
	# from both the cache-miss and cache-hit paths.
	[[ "${ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF:-no}" == "yes" ]] && return 0
	[[ "${ARCH}" == "armhf" ]] || return 1
	[[ "$(arch)" == "aarch64" ]] || return 1

	# Pre-flight is unreliable when qemu-arm is enabled (it interprets the
	# arch-test stub); the authoritative check is post-disable below.
	if ! arch-test armhf > /dev/null 2>&1; then
		display_alert "Native armhf via binfmt_elf" "arch-test pre-flight failed; falling back to qemu-arm-static emulation" "info"
		return 1
	fi

	# qemu-arm not registered → native already active, no anchor needed.
	if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
		display_alert "Native armhf via binfmt_elf" "qemu-arm not registered; native armhf already in effect" "info"
		declare -g ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF=yes
		return 0
	fi

	# Group-scoped 2>/dev/null: a bare `exec {fd}< file 2>/dev/null` would
	# persistently redirect THIS shell's stderr (since exec without a command
	# applies redirections to the current shell), silencing every later
	# display_alert that writes to stderr.
	if ! { exec {_native_armhf_lock_fd}< /proc/sys/fs/binfmt_misc/qemu-arm; } 2> /dev/null; then
		display_alert "Native armhf via binfmt_elf" "cannot open binfmt_misc/qemu-arm; falling back to qemu emulation" "wrn"
		return 1
	fi
	if ! flock -s -w 30 "${_native_armhf_lock_fd}"; then
		display_alert "Native armhf via binfmt_elf" "could not acquire shared flock on binfmt_misc/qemu-arm within 30s; falling back to qemu emulation" "wrn"
		exec {_native_armhf_lock_fd}>&-
		unset _native_armhf_lock_fd
		return 1
	fi

	if [[ "$(_native_armhf_observe_qemu_arm_state)" == "1" ]]; then
		if ! echo 0 > /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null; then
			display_alert "Native armhf via binfmt_elf" "could not disable qemu-arm (no CAP_SYS_ADMIN?); falling back to qemu-arm-static emulation" "wrn"
			exec {_native_armhf_lock_fd}>&-
			unset _native_armhf_lock_fd
			return 1
		fi
	fi

	# Register cleanup BEFORE the authoritative arch-test, so a failure
	# there still releases the lock via the trap handler.
	add_cleanup_handler trap_handler_native_armhf_restore_qemu_arm

	# Post-disable check is authoritative: arch-test now faces what the
	# chroot exec will face. False-positive if host kernel lacks COMPAT_VDSO
	# (see extensions/arm64-compat-vdso, PR #9284).
	if ! arch-test armhf > /dev/null 2>&1; then
		display_alert "Native armhf via binfmt_elf" "post-disable verification failed (host kernel lacks COMPAT_VDSO — see extensions/arm64-compat-vdso); restoring and falling back to emulation" "wrn"
		trap_handler_native_armhf_restore_qemu_arm
		return 1
	fi

	display_alert "Native armhf via binfmt_elf" "kernel $(uname -r), aarch64 host with COMPAT_VDSO; qemu-arm disabled, kernel binfmt_elf takes over" "info"
	declare -g ARMBIAN_NATIVE_ARMHF_VIA_BINFMT_ELF=yes
	return 0
}

# Cleanup ordering invariant: this handler must run AFTER cleanups that kill
# the build's subshells (umount / SDCARD / MOUNT teardown). BSD flock is per-
# OFD, so a forked subshell inheriting our SH-fd shares the same lock entry —
# the LOCK_EX-NB probe below would falsely block on the inherited fd of a
# still-alive child. add_cleanup_handler runs in registration order; the
# umount handlers register first, so by the time we run, the docker container
# is dead and its child-tree with it. Verified empirically (SIGINT mid-chroot).
function trap_handler_native_armhf_restore_qemu_arm() {
	[[ -n "${_native_armhf_lock_fd:-}" ]] || return 0
	exec {_native_armhf_lock_fd}>&-
	unset _native_armhf_lock_fd

	[[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]] || return 0

	# Group-scoped 2>/dev/null on the exec — see _native_armhf_setup_binfmt_elf.
	declare last_fd
	if ! { exec {last_fd}< /proc/sys/fs/binfmt_misc/qemu-arm; } 2> /dev/null; then
		return 0
	fi
	if flock -x -n "${last_fd}"; then
		echo 1 > /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null || true
		display_alert "Native armhf via binfmt_elf" "last out; qemu-arm restored to enabled" "info"
	fi
	exec {last_fd}>&-
}

# The actual binfmt manipulations when cross-build is confirmed above.
function prepare_host_binfmt_qemu_cross() {
	local failed_binfmt_modprobe=0

	display_alert "Cross arch build" "target ${ARCH} on host $(dpkg --print-architecture)" "info"

	# Check if binfmt_misc is loaded; if not, try to load it, but don't fail: it might be built in.
	if grep -q "^binfmt_misc" /proc/modules; then
		display_alert "binfmt_misc is already loaded" "binfmt_misc already loaded" "debug"
	else
		display_alert "binfmt_misc is not loaded" "trying to load binfmt_misc" "debug"

		# try to modprobe. if it fails, emit a warning later, but not here.
		# this is for the in-container case, where the host already has the module, but won't let the container know about it.
		modprobe -q binfmt_misc || failed_binfmt_modprobe=1
	fi

	# Now, /proc/sys/fs/binfmt_misc/ has to be mounted. Mount, or fail with a message
	if mountpoint -q /proc/sys/fs/binfmt_misc/; then
		display_alert "binfmt_misc is already mounted" "binfmt_misc already mounted" "debug"
	else
		display_alert "binfmt_misc is not mounted" "trying to mount binfmt_misc" "debug"
		mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc/ || {
			if [[ $failed_binfmt_modprobe == 1 ]]; then
				display_alert "Failed to load binfmt_misc module" "modprobe binfmt_misc failed" "wrn"
			fi
			display_alert "Check your HOST kernel" "CONFIG_BINFMT_MISC=m is required in host kernel" "warn"
			display_alert "Failed to mount" "binfmt_misc /proc/sys/fs/binfmt_misc/" "err"
			exit_with_error "Failed to mount binfmt_misc"
		}
		display_alert "binfmt_misc mounted" "binfmt_misc mounted" "debug"
	fi

	declare host_arch
	host_arch="$(arch)"
	declare -a wanted_arches=("arm" "aarch64" "x86_64" "riscv64" "loongarch64")
	declare -A arch_aliases=(["aarch64"]="arm64" ["x86_64"]="amd64")
	display_alert "Preparing binfmts for arch" "binfmts: host '${host_arch}', wanted arches '${wanted_arches[*]}'" "debug"
	declare wanted_arch arch_alias
	for wanted_arch in "${wanted_arches[@]}"; do
		arch_alias="${arch_aliases["${wanted_arch}"]:-"${wanted_arch}"}"
		display_alert "Preparing binfmts for arch" "wanted arch '${wanted_arch}' alias '${arch_alias}'" "debug"

		if [[ "${host_arch}" == "${wanted_arch}" ]]; then
			continue
		fi

		# Skip wanted_arch=arm preparation entirely when this build doesn't
		# target armhf. The Apple-Silicon helper below mutates global kernel
		# binfmt_misc/qemu-arm state, which is irrelevant for cross builds
		# targeting amd64/riscv64/etc and would needlessly race with any
		# concurrent native-armhf owner on the host.
		if [[ "${host_arch}" == "aarch64" && "${wanted_arch}" == "arm" && "${ARCH}" != "armhf" ]]; then
			display_alert "binfmt qemu-arm" "skipped: target ARCH=${ARCH} doesn't need qemu-arm" "debug"
			continue
		fi

		# Early native-armhf claim. On aarch64 host targeting armhf, try to
		# become or join the native-armhf-via-binfmt_elf owner BEFORE the
		# Apple-Silicon special branch below. The latter mutates global kernel
		# binfmt_misc state via update-binfmts, which races against another
		# concurrent build that holds qemu-arm in its disabled state. Joining
		# (or becoming first) keeps qemu-arm disabled coherently and lets
		# /usr/share/binfmts/qemu-arm absence in this container be a non-issue.
		if [[ "${host_arch}" == "aarch64" && "${wanted_arch}" == "arm" && "${ARCH}" == "armhf" ]]; then
			if _native_armhf_setup_binfmt_elf; then
				display_alert "binfmt qemu-arm" "skipped: native armhf via binfmt_elf is active" "cachehit"
				continue
			fi
			# qemu-arm disabled means another builder native-owns it; route
			# through the guard so we fail fast instead of clobbering.
			if [[ "$(_native_armhf_observe_qemu_arm_state)" == "0" ]]; then
				prepare_host_binfmt_qemu_cross_arm64_host_armhf_target
				continue
			fi
		fi

		if [[ ! -e "/proc/sys/fs/binfmt_misc/qemu-${wanted_arch}" || ! -e "/usr/share/binfmts/qemu-${wanted_arch}" ]]; then
			display_alert "Updating binfmts" "update-binfmts --enable qemu-${wanted_arch}" "debug"

			# special case: some arm64 machines cant' really run armhf binaries natively (Apple Silicon); check if that is the case and forcibly import and enable qemu-arm for them.
			if [[ "${host_arch}" == "aarch64" && "${wanted_arch}" == "arm" ]]; then
				prepare_host_binfmt_qemu_cross_arm64_host_armhf_target
			else
				run_host_command_logged update-binfmts --enable "qemu-${wanted_arch}" "&>" "/dev/null" || display_alert "Failed to update binfmts" "update-binfmts --enable qemu-${wanted_arch}" "err" # log & continue on failure
			fi
		fi
	done
}

function prepare_host_binfmt_qemu_cross_arm64_host_armhf_target() {
	# Conservative guard: refuse to mutate global qemu-arm state if it is
	# observably disabled. That state means another concurrent armbian build
	# is using the native-armhf path and we'd clobber it by re-enabling
	# qemu-arm here. (Reachable only via NATIVE_ARMHF_ON_ARM64=no/never/
	# disabled opt-out — otherwise _native_armhf_setup_binfmt_elf would have
	# already exit'd with the "concurrent native-armhf build" error before
	# we got here.)
	if [[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
		declare observed_qemu_arm
		observed_qemu_arm="$(_native_armhf_observe_qemu_arm_state)"
		if [[ "${observed_qemu_arm}" == "0" ]]; then
			display_alert "binfmt qemu-arm" "registered but observably disabled — another concurrent build likely holds native-armhf; refusing to clobber" "err"
			exit_with_error "qemu-arm globally disabled by another concurrent build; cannot safely re-enable. Wait for it to finish or run on a separate host."
		fi
	fi

	display_alert "Trying to update binfmts - aarch64 mostly does 32-bit sans emulation, but Apple said no" "update-binfmts --enable qemu-${wanted_arch}" "debug"
	run_host_command_logged update-binfmts --enable "qemu-${wanted_arch}" "&>" "/dev/null" "||" "true" # don't fail nor produce output, which can be misleading.

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Debugging arch-test" "full output" "debug"
		run_host_command_logged arch-test "||" true
	fi

	# to check, we use arch-test; will return 0 if _either_ the host can natively run armhf, or if qemu-arm is correctly working.
	# Use armhf (Debian-arch) rather than arm to match the build target and the post-disable check in _native_armhf_setup_binfmt_elf.
	if arch-test armhf; then
		display_alert "Host can run armhf natively or emulation is correctly setup already" "no need to enable qemu-arm" "debug"
	else
		display_alert "arm64 host can't run armhf natively" "importing enabling qemu-arm" "debug"
		cat <<- BINFMT_ARM_MAGIC > /usr/share/binfmts/qemu-arm
			package qemu-user-static
			interpreter /usr/bin/qemu-arm-static
			magic \x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00
			offset 0
			mask \xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff
			credentials yes
			fix_binary no
			preserve yes
		BINFMT_ARM_MAGIC
		run_host_command_logged update-binfmts --import "qemu-${wanted_arch}"
		run_host_command_logged update-binfmts --enable "qemu-${wanted_arch}"

		# Test again using arch-test.
		display_alert "Checking if arm 32-bit emulation on arm64 works after enabling" "qemu-arm emulation" "info"
		run_host_command_logged arch-test armhf
		display_alert "arm 32-bit emulation on arm64" "has been correctly setup" "cachehit"
	fi
}
