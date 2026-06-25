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

	# Check the binary we deployed is there. If not, panic, as we've lost control.
	if [[ ! -f "${dst_target}" ]]; then
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

		# aarch64 host + armhf target: always defer to the handler. It decides native
		# COMPAT vs qemu-arm and is idempotent across every binfmt_misc state, so it must
		# run even when qemu-arm is already registered (the common packaged-host case) —
		# otherwise the native-COMPAT path is skipped and a stale qemu-arm is never repaired.
		if [[ "${host_arch}" == "aarch64" && "${wanted_arch}" == "arm" ]]; then
			prepare_host_binfmt_qemu_cross_arm64_host_armhf_target
		elif [[ ! -e "/proc/sys/fs/binfmt_misc/qemu-${wanted_arch}" || ! -e "/usr/share/binfmts/qemu-${wanted_arch}" ]]; then
			display_alert "Updating binfmts" "update-binfmts --enable qemu-${wanted_arch}" "debug"
			run_host_command_logged update-binfmts --enable "qemu-${wanted_arch}" "&>" "/dev/null" || display_alert "Failed to update binfmts" "update-binfmts --enable qemu-${wanted_arch}" "err" # log & continue on failure
		fi
	done
}

function prepare_host_binfmt_qemu_cross_arm64_host_armhf_target() {
	declare armhf_probe="/usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3"
	declare prefer_native="${PREFER_NATIVE_ARMHF:-yes}"
	declare qemu_arm_was_enabled=0

	# Snapshot qemu-arm state — drives both COMPAT probe and trust-existing.
	if [[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]] &&
		[[ "$(head -n1 /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null)" == "enabled" ]]; then
		qemu_arm_was_enabled=1
	fi

	# COMPAT probe must run with qemu-arm OFF, otherwise kernel routes
	# armhf exec through qemu and the probe lies. Temp-disable, probe,
	# restore on failure. `arch-test arm` is unreliable (probes ARMv5,
	# COMPAT needs ≥v7); ld-linux-armhf comes from gcc-arm-linux-gnueabihf
	# (armbian host dep for armhf|all). Toggle needs CAP_SYS_ADMIN — present
	# in Armbian's docker_cli_prepare_launch; if /proc is read-only anyway,
	# skip the probe gracefully and trust existing qemu-arm.
	if [[ "${prefer_native}" == "yes" ]] && [[ -x "${armhf_probe}" ]]; then
		declare toggle_ok=1
		if ((qemu_arm_was_enabled)); then
			echo 0 > /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null || toggle_ok=0
		fi
		if ((toggle_ok)) && "${armhf_probe}" --help > /dev/null 2>&1; then
			display_alert "Host kernel can run armhf natively (CONFIG_COMPAT)" "qemu-arm left disabled if it was on" "info"
			return 0
		fi
		if ((qemu_arm_was_enabled && toggle_ok)); then
			echo 1 > /proc/sys/fs/binfmt_misc/qemu-arm ||
				exit_with_error "Failed to restore qemu-arm after failed native armhf probe"
		fi
	fi

	# Native COMPAT unavailable (or opt-out via PREFER_NATIVE_ARMHF=no).
	# Trust existing qemu-arm registration only if it actually executes —
	# `enabled` flag alone doesn't tell us the interpreter is runnable
	# (stale path, removed package). Validate via arch-test.
	if ((qemu_arm_was_enabled)); then
		if command -v arch-test > /dev/null 2>&1 && arch-test arm > /dev/null 2>&1; then
			display_alert "qemu-arm enabled and functional" "trusting existing setup" "debug"
			return 0
		fi
		display_alert "qemu-arm enabled but execution probe failed" "stale registration — reconfiguring" "warn"
	fi

	# ld-linux-armhf may be absent on cross builds whose target isn't
	# armhf (gcc-arm-linux-gnueabihf isn't pulled in then). Fall back to
	# arch-test to avoid degraded host-capability detection on those
	# flows; on Ampere CAX it reports false-negative but the probe above
	# already covered the armhf-target case where it matters most.
	if [[ ! -x "${armhf_probe}" ]] && command -v arch-test > /dev/null 2>&1 && arch-test arm > /dev/null 2>&1; then
		display_alert "Host can run armhf (arch-test fallback)" "no qemu-arm setup needed" "debug"
		return 0
	fi

	# No native COMPAT — need qemu-arm. Prefer a packaged descriptor
	# (qemu-user-binfmt on resolute installs `/usr/bin/qemu-arm`;
	# qemu-user-static elsewhere uses the -static suffix). Overwriting
	# it would break the resolute interpreter path.
	if [[ -f /usr/share/binfmts/qemu-arm ]]; then
		# Three-step recovery: re-import the descriptor into binfmt-support's
		# admin DB (handles stale/empty DB where --enable would fail with
		# "not in database"); --enable activates the format; force-sync via
		# /proc afterwards if the kernel entry was externally toggled to 0.
		run_host_command_logged update-binfmts --import qemu-arm 2> /dev/null || true
		run_host_command_logged update-binfmts --enable qemu-arm || true
		[[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]] && echo 1 > /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null || true
		if [[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]] &&
			[[ "$(head -n1 /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null)" == "enabled" ]]; then
			_verify_qemu_arm_executes
			display_alert "qemu-arm enabled via packaged descriptor" "leaving package-provided setup intact" "debug"
			return 0
		fi
		exit_with_error "/usr/share/binfmts/qemu-arm exists but qemu-arm could not be enabled — packaged interpreter likely missing. Reinstall qemu-user-binfmt (resolute) / qemu-user-static, or remove the descriptor and retry."
	fi

	# Kernel entry exists but disabled, no descriptor on host. The kernel
	# keeps the magic/mask in memory once registered; only the enabled
	# flag toggles. Try `echo 1 > /proc/...` before giving up — that
	# repairs the common "someone toggled it off" state without needing
	# the descriptor file back.
	if [[ -e /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
		echo 1 > /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null || true
		if [[ "$(head -n1 /proc/sys/fs/binfmt_misc/qemu-arm 2> /dev/null)" == "enabled" ]]; then
			_verify_qemu_arm_executes
			display_alert "qemu-arm re-enabled via /proc" "kernel state restored without descriptor" "debug"
			return 0
		fi
		exit_with_error "qemu-arm kernel entry present but cannot be re-enabled and no descriptor to re-register from. Reinstall qemu-user-binfmt / qemu-user-static and retry."
	fi

	# Apple-Silicon-like (no COMPAT, no qemu pkg): hand-roll the descriptor.
	display_alert "arm64 host can't run armhf natively (no CONFIG_COMPAT?)" "importing+enabling qemu-arm" "debug"
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
	run_host_command_logged update-binfmts --import qemu-arm
	run_host_command_logged update-binfmts --enable qemu-arm

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Debugging arch-test" "full output" "debug"
		run_host_command_logged arch-test || true
	fi
	_verify_qemu_arm_executes
	display_alert "arm 32-bit emulation on arm64" "has been set up via qemu-arm" "cachehit"
}

# Helper: confirm qemu-arm interpreter actually runs an armhf binary.
# `update-binfmts --enable` and an `enabled` flag in /proc only attest
# registration state, not runtime executability — a stale interpreter
# path or removed package slips through and fails later in chroot. Run
# `arch-test arm` here so we fail fast at host-prepare time.
function _verify_qemu_arm_executes() {
	if ! command -v arch-test > /dev/null 2>&1; then
		display_alert "qemu-arm runtime verification skipped" "arch-test not available on host" "warn"
		return 0
	fi
	if arch-test arm > /dev/null 2>&1; then
		return 0
	fi
	exit_with_error "qemu-arm registered but armhf execution fails. Interpreter likely broken (stale path, removed package, missing qemu-arm-static). Reinstall qemu-user-binfmt (resolute) / qemu-user-static and retry."
}
