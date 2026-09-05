#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Reference implementation of two complementary deploy hooks:
#
#   1. `netboot_artifacts_ready` — fired by netboot.sh after a full image
#      build, ships the staged TFTP tree and the rootfs archive.
#   2. `artifact_ready` (with WHAT=kernel) — fired by core after a stand-
#      alone `compile.sh kernel ...` run, unpacks the linux-image .deb and
#      ships vmlinuz/dtbs to TFTP plus /lib/modules/<ver>/ to the NFS rootfs
#      so the next netboot grabs a coherent kernel+modules pair (avoids
#      `BPF: Invalid name_offset` from split-BTF mismatches between vmlinux
#      and out-of-sync .ko files).
#
# Not auto-loaded. Enable with ENABLE_EXTENSIONS=netboot-deploy —
# the netboot extension is pulled in automatically below.
#
# SSH authentication: this hook shells out to ssh/rsync with default
# OpenSSH behavior. Two ways to feed credentials into a Docker build:
#
#   * Interactive — `DOCKER_PASS_SSH_AGENT=yes` forwards the host
#     ssh-agent socket. The agent must be live at build time and the
#     socket reachable by the container user.
#
#   * Batch / CI — bind-mount a single private key into the container
#     with NETBOOT_DEPLOY_SSH_KEY=<path>. A host-side hook adds the
#     matching `--mount` argument; inside the container the key is
#     copied to a root-owned scratch path before use, since OpenSSH
#     refuses identity files whose owner is neither root nor the
#     current user (the host file stays owned by the invoking user).
#
# Variables:
#   NETBOOT_DEPLOY_SSH           SSH target, e.g. root@netboot.local
#   NETBOOT_DEPLOY_TFTP_ROOT     Absolute TFTP root on the server.
#                                Default: /srv/netboot/tftp
#   NETBOOT_DEPLOY_TFTP_DELETE   yes|no — rsync --delete on TFTP tree.
#                                Default: yes (TFTP mirrors the build exactly).
#                                Set to 'no' when the TFTP root is shared
#                                with other unrelated deployments.
#   NETBOOT_DEPLOY_NFS_DELETE    yes|no — wipe NETBOOT_NFS_PATH before tar-
#                                extracting the new rootfs. Default: no
#                                (preserve-on-top — see 'Rootfs handling'
#                                below). Set to 'yes' for CI / immutable
#                                workflows where the booted rootfs must
#                                match the build artifact bit-for-bit;
#                                clears any stale files left over from
#                                packages dropped or paths renamed
#                                between rebuilds.
#   NETBOOT_DEPLOY_EXCLUDE_FILE  Optional rsync --exclude-from file applied
#                                to the TFTP sync. For rootfs updates, use
#                                your own rsync step instead — see README.
#   NETBOOT_DEPLOY_SUDO          yes|no — run remote rsync/mkdir/tar under
#                                `sudo -n`. Default: no. Required when the
#                                SSH account is not root: NFS-rootfs writes
#                                (tar untar with --numeric-owner/xattrs and
#                                /lib/modules rsync) keep ownership intact
#                                only with effective root; without it the
#                                export gets rewritten under the login uid
#                                and the next netboot fails on permission
#                                mismatches. The hook probes the remote uid
#                                before each NFS-side operation and aborts
#                                with a precise error when uid != 0 and
#                                NETBOOT_DEPLOY_SUDO=no. Needs passwordless
#                                sudo for rsync, mkdir, and tar on the server.
#   NETBOOT_DEPLOY_SSH_KEY       Path to a private key file. The hook bind-
#                                mounts the file read-only at the same path
#                                inside the container, copies it to a root-
#                                owned scratch path on first use, and adds
#                                `-i <scratch>` to the ssh command line.
#                                Use for batch/CI runs without a live agent.
#   NETBOOT_DEPLOY_SSH_KNOWN_HOSTS
#                                Path to a known_hosts file on the build host.
#                                Default: ${HOME}/.ssh/known_hosts if present
#                                (auto-pickup of an interactive workflow's
#                                known_hosts), otherwise unset. The hook
#                                bind-mounts the file into the container at
#                                /root/.ssh/known_hosts:ro so ssh inside docker
#                                inherits the operator's already-trusted hosts.
#                                For CI without a populated ${HOME}/.ssh, set
#                                this to a path with a pre-populated file (e.g.
#                                via `ssh-keyscan -H target` in a pipeline step
#                                or as a secret). Mutually exclusive with
#                                NETBOOT_DEPLOY_SSH_TOFU=yes.
#   NETBOOT_DEPLOY_SSH_TOFU      yes|no — defaults to "no". When "yes" the
#                                hook switches ssh to ephemeral TOFU mode:
#                                `-o UserKnownHostsFile=/dev/null
#                                  -o StrictHostKeyChecking=accept-new`.
#                                Each connection learns the host key fresh
#                                and forgets it — no setup needed and no
#                                MITM protection. For home-lab / trusted-
#                                segment use only. Mutually exclusive with
#                                NETBOOT_DEPLOY_SSH_KNOWN_HOSTS / a
#                                pre-existing ${HOME}/.ssh/known_hosts.
#   NETBOOT_DEPLOY_SSH_OPTS      Extra ssh options applied to both ssh and
#                                rsync. Default: `-o BatchMode=yes`. Strict
#                                by design: BatchMode + the implicit
#                                StrictHostKeyChecking=ask refuses unknown or
#                                changed host keys. Use the dedicated
#                                NETBOOT_DEPLOY_SSH_KNOWN_HOSTS or
#                                NETBOOT_DEPLOY_SSH_TOFU for host-identity
#                                control; this variable stays for arbitrary
#                                other tweaks (timeouts, ProxyCommand, …).
#                                Caveat: the value is split on whitespace;
#                                option arguments containing spaces or
#                                quotes (e.g. ProxyCommand="ssh -W ..."
#                                or UserKnownHostsFile="/tmp/known hosts")
#                                will be mangled. For such options, place
#                                them in ~/.ssh/config (visible to ssh via
#                                DOCKER_PASS_SSH_AGENT or via your own
#                                bind-mount of a config file).
#
# Rootfs handling:
#   If NETBOOT_ROOTFS_ARCHIVE is a file, it is uploaded and untarred into
#   NETBOOT_NFS_PATH. With NETBOOT_DEPLOY_NFS_DELETE=no (default), removed
#   files from earlier builds stay on disk and per-host state (ssh host
#   keys, machine-id, /home) is preserved across redeploys. With
#   NETBOOT_DEPLOY_NFS_DELETE=yes the target is wiped first, so the booted
#   rootfs matches the produced image bit-for-bit at the cost of any
#   on-target state. For per-host preservation under DELETE=yes, keep that
#   state on a separate NFS mount layered on top of the rootfs export.
#
#   When ROOTFS_COMPRESSION=none is used together with ROOTFS_EXPORT_DIR,
#   there is no archive to ship — the builder has already written straight
#   into the export. This hook then only deploys TFTP.
#

enable_extension netboot

# netboot-deploy implies ROOTFS_TYPE=nfs-root. Set it in host_pre_docker_launch
# so main-config.sh's case "$ROOTFS_TYPE" block (FIXED_IMAGE_SIZE=256 etc.)
# evaluates it correctly after relaunch. extension_prepare_config below is
# the fallback for the non-relaunch path (PREFER_DOCKER=no), where the case
# block has already run with the ext4 default; mirror its defaults manually.
function host_pre_docker_launch__050_netboot_deploy_imply_nfs_root() {
	if [[ "${ROOTFS_TYPE:-}" != "nfs-root" ]]; then
		display_alert "${EXTENSION}: implying ROOTFS_TYPE=nfs-root" \
			"was '${ROOTFS_TYPE:-unset}'; injecting into relaunch args" "info"
		declare -g ROOTFS_TYPE="nfs-root"
		ARMBIAN_CLI_FINAL_RELAUNCH_ARGS+=("ROOTFS_TYPE=nfs-root")
	fi
}

function extension_prepare_config__050_netboot_deploy_imply_nfs_root() {
	if [[ "${ROOTFS_TYPE:-}" != "nfs-root" ]]; then
		display_alert "${EXTENSION}: forcing ROOTFS_TYPE=nfs-root" \
			"was '${ROOTFS_TYPE:-unset}'; mirroring nfs-root case-block defaults" "info"
		declare -g ROOTFS_TYPE="nfs-root"
		declare -g FIXED_IMAGE_SIZE="${FIXED_IMAGE_SIZE:-256}"
	fi
}

# Probe the deploy target before docker launch — so missing SSH credentials,
# pasword-locked sudo, or a read-only/non-existent TFTP root surface in the
# first 5 seconds instead of after a 30-50 minute kernel build. The probe is
# `touch + rm` of a per-PID scratch path under NETBOOT_DEPLOY_TFTP_ROOT, which
# exercises the same auth chain (ssh + optional sudo + filesystem write) that
# the real deploy will need later. Set NETBOOT_DEPLOY_PROBE=no to skip — every
# safety check is occasionally the obstacle (jumphost weirdness, custom
# ProxyCommand, target that disallows file creation under TFTP root but
# allows rsync via a wrapper, …). Default: yes.
function extension_prepare_config__060_netboot_deploy_probe_target() {
	[[ -n "${NETBOOT_DEPLOY_SSH:-}" ]] || return 0
	if [[ "${NETBOOT_DEPLOY_PROBE:-yes}" != "yes" ]]; then
		display_alert "${EXTENSION}: skipping deploy probe" \
			"NETBOOT_DEPLOY_PROBE=${NETBOOT_DEPLOY_PROBE} (you'll only learn at deploy time if creds are wrong)" "warn"
		return 0
	fi
	declare tftp_root="${NETBOOT_DEPLOY_TFTP_ROOT:-/srv/netboot/tftp}"
	# Mirror the actual deploy hook's SSH options. extension_prepare_config
	# fires inside the container after docker relaunch, where ssh's default
	# ~/.ssh/known_hosts already resolves to the file that
	# host_pre_docker_launch__netboot_deploy_mount_known_hosts bind-mounts
	# at /root/.ssh/known_hosts — so no explicit UserKnownHostsFile is
	# needed for the non-TOFU case. TOFU still passes /dev/null +
	# accept-new explicitly. -o ConnectTimeout=5 goes first (OpenSSH
	# applies the first occurrence of an option) so the probe stays
	# bounded even if the user's SSH_OPTS doesn't set ConnectTimeout.
	declare probe_extra=""
	if [[ "${NETBOOT_DEPLOY_SSH_TOFU:-no}" == "yes" ]]; then
		probe_extra="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new"
	fi
	# shellcheck disable=SC2206 # word-split intentional, user gives a shell-style string
	declare -a probe_cmd=(ssh -o ConnectTimeout=5 ${probe_extra} ${NETBOOT_DEPLOY_SSH_OPTS:--o BatchMode=yes})
	# Mirror the deploy hook's scratch-key dance: OpenSSH refuses identity
	# files whose owner is neither root nor the current user, and a key
	# bind-mounted from the host keeps the host user's ownership. Without
	# this the probe would reject valid CI/batch credentials that the
	# real deploy (which copies into a scratch path) handles fine. Clean
	# up right after the probe — extension_prepare_config runs in the
	# caller's scope, so a trap would leak.
	declare probe_scratch_key=""
	if [[ -n "${NETBOOT_DEPLOY_SSH_KEY:-}" ]]; then
		if [[ ! -f "${NETBOOT_DEPLOY_SSH_KEY}" ]]; then
			exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KEY set but not visible in container" \
				"${NETBOOT_DEPLOY_SSH_KEY}"
		fi
		probe_scratch_key="$(mktemp -p /tmp "netboot-deploy-probe-key.XXXXXX")"
		cp "${NETBOOT_DEPLOY_SSH_KEY}" "${probe_scratch_key}"
		chmod 600 "${probe_scratch_key}"
		probe_cmd+=(-i "${probe_scratch_key}")
	fi
	declare sudo_prefix=""
	[[ "${NETBOOT_DEPLOY_SUDO:-no}" == "yes" ]] && sudo_prefix="sudo -n "
	# Quote remote path for any POSIX shell (same idiom as the deploy hook below).
	declare q_probe="'${tftp_root//\'/\'\\\'\'}/.netboot-deploy-probe.${BASHPID}'"
	display_alert "${EXTENSION}: probing deploy target" \
		"ssh ${NETBOOT_DEPLOY_SSH} (sudo=${NETBOOT_DEPLOY_SUDO:-no}) → touch+rm ${tftp_root}/.netboot-deploy-probe.*" "info"
	# Capture stderr to a tempfile so a failed probe surfaces the real ssh
	# diagnostic ('Permission denied (publickey)', 'Host key verification
	# failed', 'Connection refused', 'sudo: a terminal is required', …)
	# instead of just a generic «check all of these things».
	declare probe_stderr_file
	probe_stderr_file=$(mktemp -t netboot-deploy-probe-stderr.XXXXXX)
	if ! "${probe_cmd[@]}" "${NETBOOT_DEPLOY_SSH}" \
		"${sudo_prefix}touch ${q_probe} && ${sudo_prefix}rm -f ${q_probe}" 2> "${probe_stderr_file}"; then
		declare probe_stderr
		probe_stderr=$(head -c 4096 "${probe_stderr_file}" | sed 's/[[:space:]]*$//')
		rm -f "${probe_stderr_file}" "${probe_scratch_key}"
		exit_with_error "${EXTENSION}: deploy probe failed" \
			"ssh '${NETBOOT_DEPLOY_SSH}' cannot create+remove a file under '${tftp_root}'. ssh stderr: ${probe_stderr:-<empty>}. Check NETBOOT_DEPLOY_SSH_KEY, sudo NOPASSWD, target dir existence/permissions, host-key trust (NETBOOT_DEPLOY_SSH_KNOWN_HOSTS or NETBOOT_DEPLOY_SSH_TOFU). Bypass with NETBOOT_DEPLOY_PROBE=no."
	fi
	rm -f "${probe_stderr_file}" "${probe_scratch_key}"
}

# Host-side: bind-mount the chosen private key into the build container
# before Docker starts. The file is mounted read-only at the same path
# the host uses, so a deploy hook running as root inside the container
# can read it (CAP_DAC_OVERRIDE) and copy it to a root-owned scratch
# path before handing it to ssh.
function host_pre_docker_launch__netboot_deploy_mount_ssh() {
	[[ -n "${NETBOOT_DEPLOY_SSH_KEY:-}" ]] || return 0
	declare host_key
	host_key="$(realpath "${NETBOOT_DEPLOY_SSH_KEY}" 2> /dev/null || true)"
	if [[ -z "${host_key}" || ! -f "${host_key}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KEY not found or not a file" \
			"${NETBOOT_DEPLOY_SSH_KEY}"
	fi
	# `--mount` CSV has no escape syntax — reject paths with commas.
	if [[ "${host_key}" == *,* ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KEY path must not contain a comma" \
			"${host_key}"
	fi
	# Normalize the variable to the resolved path so the in-container deploy
	# hook checks the same file we bind-mounted (a symlinked input would
	# otherwise be reported as missing inside the container).
	declare -g NETBOOT_DEPLOY_SSH_KEY="${host_key}"
	display_alert "${EXTENSION}: mount SSH key" "${host_key}" "info"
	DOCKER_EXTRA_ARGS+=("--mount" "type=bind,source=${host_key},target=${host_key},readonly")
}

# Host-side: bind-mount a known_hosts file into the container so ssh inside
# docker has a host-identity store. Three scenarios — see the variable docs at
# the top of this file:
#   - NETBOOT_DEPLOY_SSH_KNOWN_HOSTS=<path>: explicit (CI / unusual location)
#   - default + ${HOME}/.ssh/known_hosts on host: auto-pickup (interactive)
#   - NETBOOT_DEPLOY_SSH_TOFU=yes: ephemeral, no mount needed (handled at
#     ssh invocation time via UserKnownHostsFile=/dev/null)
# KNOWN_HOSTS and TOFU=yes are mutually exclusive — refuse to ambiguate.
function host_pre_docker_launch__netboot_deploy_mount_known_hosts() {
	[[ -n "${NETBOOT_DEPLOY_SSH:-}" ]] || return 0
	declare tofu="${NETBOOT_DEPLOY_SSH_TOFU:-no}"
	declare khosts="${NETBOOT_DEPLOY_SSH_KNOWN_HOSTS:-}"
	# Auto-pickup only when neither is explicitly set.
	if [[ -z "${khosts}" && "${tofu}" != "yes" && -f "${HOME}/.ssh/known_hosts" ]]; then
		khosts="${HOME}/.ssh/known_hosts"
	fi
	if [[ "${tofu}" == "yes" && -n "${khosts}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_TOFU=yes is incompatible with a known_hosts source" \
			"pick one: TOFU (ephemeral, /dev/null + accept-new) OR KNOWN_HOSTS (strict, file-based identity). \$HOME/.ssh/known_hosts auto-pickup also counts; unset NETBOOT_DEPLOY_SSH_KNOWN_HOSTS or move/rename your host known_hosts to disambiguate."
	fi
	[[ -n "${khosts}" ]] || return 0
	declare host_kh
	host_kh="$(realpath "${khosts}" 2> /dev/null || true)"
	if [[ -z "${host_kh}" || ! -f "${host_kh}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KNOWN_HOSTS not found or not a file" \
			"${khosts}"
	fi
	if [[ "${host_kh}" == *,* ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KNOWN_HOSTS path must not contain a comma" \
			"${host_kh}"
	fi
	declare -g NETBOOT_DEPLOY_SSH_KNOWN_HOSTS="${host_kh}"
	display_alert "${EXTENSION}: mount known_hosts" "${host_kh}" "info"
	DOCKER_EXTRA_ARGS+=("--mount" "type=bind,source=${host_kh},target=/root/.ssh/known_hosts,readonly")
}

# NFS-side writes (tar untar with --numeric-owner/xattrs, /lib/modules rsync)
# preserve ownership only when the remote shell runs as uid 0. With
# NETBOOT_DEPLOY_SUDO=no and a non-root login, the write succeeds but the
# export gets rewritten under the login uid — the next netboot panics on
# broken permissions. Probe `id -u` over the same SSH path the deploy will
# use and fail fast when uid != 0 and sudo is off; sudo -n is the documented
# elevation escape hatch and skips the probe.
#
# Reads ${ssh_opts[@]}, ${NETBOOT_DEPLOY_SSH}, ${NETBOOT_DEPLOY_SUDO} from
# the calling hook's local scope (bash dynamic scoping). Kept as a top-level
# helper so both deploy hooks share one implementation.
function _netboot_deploy_require_remote_root() {
	declare context="$1"
	[[ "${NETBOOT_DEPLOY_SUDO}" == "yes" ]] && return 0
	declare remote_uid="" uid_stderr_file
	uid_stderr_file=$(mktemp -t netboot-deploy-uid-stderr.XXXXXX)
	# Capture stdout (the uid) and stderr (ssh banners like
	# "Warning: Permanently added 'host' (ED25519) ..." under
	# StrictHostKeyChecking=accept-new) separately, so the literal
	# uid comparison below is not poisoned by ssh diagnostic lines.
	if ! remote_uid=$(ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" 'id -u' 2> "${uid_stderr_file}"); then
		declare uid_stderr
		uid_stderr=$(head -c 4096 "${uid_stderr_file}" | sed 's/[[:space:]]*$//')
		rm -f "${uid_stderr_file}"
		exit_with_error "${EXTENSION}: cannot probe remote uid before ${context}" \
			"ssh '${NETBOOT_DEPLOY_SSH}' 'id -u' failed: ${uid_stderr:-<empty>}"
	fi
	rm -f "${uid_stderr_file}"
	if [[ "${remote_uid}" != "0" ]]; then
		exit_with_error "${EXTENSION}: ${context} requires effective root on '${NETBOOT_DEPLOY_SSH}'" \
			"remote uid=${remote_uid}, NETBOOT_DEPLOY_SUDO=no. Set NETBOOT_DEPLOY_SUDO=yes (with passwordless sudo for tar/rsync/mkdir on the server) or log in as root; otherwise tar --numeric-owner / xattrs / NFS-rootfs writes rewrite ownership under uid=${remote_uid} and break the next boot."
	fi
}

function netboot_artifacts_ready__deploy_to_remote_server() (
	# Run the body in a subshell so an EXIT trap can clean up scratch_key
	# on every failure path (set -e abort, exit_with_error, …) without
	# stomping armbian's outer RETURN trace handler. `()` makes the function
	# body itself a subshell — no extra indent or refactor needed.
	declare scratch_key=""
	trap '[[ -n "${scratch_key:-}" && -f "${scratch_key}" ]] && rm -f "${scratch_key}"' EXIT

	declare NETBOOT_DEPLOY_SSH="${NETBOOT_DEPLOY_SSH:-}"
	declare NETBOOT_DEPLOY_TFTP_ROOT="${NETBOOT_DEPLOY_TFTP_ROOT:-/srv/netboot/tftp}"
	declare NETBOOT_DEPLOY_TFTP_DELETE="${NETBOOT_DEPLOY_TFTP_DELETE:-yes}"
	declare NETBOOT_DEPLOY_NFS_DELETE="${NETBOOT_DEPLOY_NFS_DELETE:-no}"
	declare NETBOOT_DEPLOY_EXCLUDE_FILE="${NETBOOT_DEPLOY_EXCLUDE_FILE:-}"
	declare NETBOOT_DEPLOY_SUDO="${NETBOOT_DEPLOY_SUDO:-no}"
	declare NETBOOT_DEPLOY_SSH_KEY="${NETBOOT_DEPLOY_SSH_KEY:-}"
	declare NETBOOT_DEPLOY_SSH_TOFU="${NETBOOT_DEPLOY_SSH_TOFU:-no}"
	# Strict-by-default: BatchMode=yes + implicit StrictHostKeyChecking=ask
	# fails on unknown/changed host keys instead of silently trusting. Identity
	# is supplied via either NETBOOT_DEPLOY_SSH_KNOWN_HOSTS (bind-mounted in
	# the host hook above) or NETBOOT_DEPLOY_SSH_TOFU=yes (ephemeral, below).
	declare NETBOOT_DEPLOY_SSH_OPTS="${NETBOOT_DEPLOY_SSH_OPTS:--o BatchMode=yes}"
	# TOFU mode: forget the host key after each connection. /dev/null is a
	# standard idiom — ssh "writes" the new key there, accept-new lets the
	# session proceed, no persistence, no MITM detection. Mutually exclusive
	# with KNOWN_HOSTS bind-mount (enforced in the host hook).
	if [[ "${NETBOOT_DEPLOY_SSH_TOFU}" == "yes" ]]; then
		NETBOOT_DEPLOY_SSH_OPTS+=" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new"
	fi

	if [[ -z "${NETBOOT_DEPLOY_SSH}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH is required"
	fi

	# Fail-fast on a broken partial-deploy state: if NETBOOT_ROOTFS_ARCHIVE
	# is set but the file does not exist, something went wrong upstream
	# (compression step crashed, path miscomputed, file deleted between
	# build and deploy). Letting the deploy proceed would publish the new
	# TFTP payload (kernel + dtb + uInitrd) without refreshing the NFS
	# rootfs — the next boot mounts a stale rootfs against a fresh kernel
	# and panics on missing modules / mismatched libc. Catch it before
	# any remote I/O so the server is never left in this inconsistent
	# half-state. An empty NETBOOT_ROOTFS_ARCHIVE is a legitimate
	# "ROOTFS_EXPORT_DIR-only" case and falls through to the empty-archive
	# branch later.
	if [[ -n "${NETBOOT_ROOTFS_ARCHIVE:-}" && ! -f "${NETBOOT_ROOTFS_ARCHIVE}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_ROOTFS_ARCHIVE is set but file missing" \
			"${NETBOOT_ROOTFS_ARCHIVE}"
	fi

	# If a private key file was bind-mounted by the host hook, copy it to
	# a scratch path with root ownership — OpenSSH refuses identity files
	# whose owner is neither root nor the current user. Fail fast if the
	# user requested a key but the host hook did not (or could not) make
	# it visible inside the container; silently falling back to agent or
	# default identities would mask a misconfiguration.
	if [[ -n "${NETBOOT_DEPLOY_SSH_KEY}" ]]; then
		if [[ ! -f "${NETBOOT_DEPLOY_SSH_KEY}" ]]; then
			exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KEY set but not visible in container" \
				"${NETBOOT_DEPLOY_SSH_KEY}"
		fi
		scratch_key="$(mktemp -p /tmp "netboot-deploy-key.XXXXXX")"
		cp "${NETBOOT_DEPLOY_SSH_KEY}" "${scratch_key}"
		chmod 600 "${scratch_key}"
		NETBOOT_DEPLOY_SSH_OPTS="-i ${scratch_key} ${NETBOOT_DEPLOY_SSH_OPTS}"
	fi

	# Validate exclude file inside the container — host paths reach the
	# build only if explicitly bind-mounted, which this hook does not do.
	if [[ -n "${NETBOOT_DEPLOY_EXCLUDE_FILE}" && ! -f "${NETBOOT_DEPLOY_EXCLUDE_FILE}" ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_EXCLUDE_FILE not visible in container" \
			"${NETBOOT_DEPLOY_EXCLUDE_FILE}"
	fi

	declare sudo_prefix=""
	[[ "${NETBOOT_DEPLOY_SUDO}" == "yes" ]] && sudo_prefix="sudo -n "

	# Word-split SSH_OPTS intentionally: user provides a shell-style string.
	# shellcheck disable=SC2206
	declare -a ssh_opts=(${NETBOOT_DEPLOY_SSH_OPTS})

	# `--mkpath` (rsync 3.2.3+) creates missing parent directories on the
	# receiver — needed for a fresh TFTP root or a new board family.
	# pxelinux.cfg is admin-managed: the build only stages files it
	# generated (01-<mac> if NETBOOT_CLIENT_MAC, <board>-<branch>-<release>
	# .example unconditionally), so it rsync's without --delete to keep
	# operator-owned entries.
	declare -a rsync_base=(-av --mkpath -e "ssh ${NETBOOT_DEPLOY_SSH_OPTS}")
	[[ -n "${NETBOOT_DEPLOY_EXCLUDE_FILE}" ]] && rsync_base+=(--exclude-from="${NETBOOT_DEPLOY_EXCLUDE_FILE}")
	[[ "${NETBOOT_DEPLOY_SUDO}" == "yes" ]] && rsync_base+=(--rsync-path="sudo -n rsync")

	declare -a rsync_payload=("${rsync_base[@]}")
	if [[ "${NETBOOT_DEPLOY_TFTP_DELETE}" == "yes" ]]; then
		if [[ -n "${NETBOOT_TFTP_PREFIX}" ]]; then
			rsync_payload+=(--delete)
		else
			display_alert "${EXTENSION}: skip rsync --delete" \
				"NETBOOT_TFTP_PREFIX is empty; --delete on the TFTP root would clobber other boards" "warn"
		fi
	fi

	# Publish order — TFTP/NFS coherence (codex P2):
	#   1. NFS rootfs untar first — tar/disk/xattr failures abort before
	#      any boot artifact reaches the server, so the board never finds
	#      a fresh kernel paired with a stale rootfs.
	#   2. TFTP payload via per-PID staging dir + atomic mv-swap, so a
	#      mid-rsync interruption or partial leftovers never appear under
	#      the live ${PREFIX}.
	#   3. pxelinux.cfg — references the just-swapped ${PREFIX} paths.

	# Stage 1 — NFS rootfs. The "set but missing" case was already
	# rejected by the fail-fast check above; reaching here with a
	# non-empty value implies the file exists.
	if [[ -n "${NETBOOT_ROOTFS_ARCHIVE}" ]]; then
		declare archive_name="${NETBOOT_ROOTFS_ARCHIVE##*/}"
		# Suffix the scratch path with this shell's BASHPID + a random token so
		# parallel deploys of the same artifact to the same server cannot wipe
		# each other's upload between rsync and tar. Plain ${archive_name} is a
		# fixed path — A's `rm` after unpack would delete B's still-uploading
		# file. We deliberately *don't* call `mktemp` over SSH: that would add a
		# round-trip and a stray file if we crash between mktemp and the rsync
		# that overwrites it. BASHPID+RANDOM is collision-free in practice and
		# costs zero remote calls.
		declare remote_archive="/tmp/${archive_name}.${BASHPID}.${RANDOM}"

		display_alert "${EXTENSION}: upload rootfs archive" \
			"${archive_name} -> ${NETBOOT_DEPLOY_SSH}:${remote_archive}" "info"
		run_host_command_logged_raw rsync -av -e "ssh ${NETBOOT_DEPLOY_SSH_OPTS}" \
			"${NETBOOT_ROOTFS_ARCHIVE}" \
			"${NETBOOT_DEPLOY_SSH}:${remote_archive}"

		_netboot_deploy_require_remote_root "rootfs archive untar into ${NETBOOT_NFS_PATH}"
		display_alert "${EXTENSION}: unpack into NFS export" \
			"${NETBOOT_NFS_PATH}" "info"
		# Quote remote-side values for any POSIX shell: wrap in single
		# quotes and replace each embedded ' with '\''. Avoids the bash-
		# only $'…' form that printf '%q' may emit for control chars,
		# so the remote sh (dash/ash/bash) parses paths reliably.
		declare q_nfs_path q_remote_archive
		q_nfs_path="'${NETBOOT_NFS_PATH//\'/\'\\\'\'}'"
		q_remote_archive="'${remote_archive//\'/\'\\\'\'}'"
		# Opt-in pre-wipe: when DELETE=yes, drop every entry under
		# ${NFS_PATH} before unpack so files that disappeared from the
		# rebuild (purged packages, renamed configs, stale modules)
		# don't survive into the next boot. `find -mindepth 1 -delete`
		# preserves the directory itself (its inode/permissions stay
		# under whoever owns the NFS export), and is silent on an
		# empty/nonexistent path.
		if [[ "${NETBOOT_DEPLOY_NFS_DELETE}" == "yes" ]]; then
			display_alert "${EXTENSION}: clear NFS export before unpack" \
				"${NETBOOT_DEPLOY_SSH}:${NETBOOT_NFS_PATH}/" "info"
			run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
				"test -d ${q_nfs_path} && ${sudo_prefix}find ${q_nfs_path} -mindepth 1 -delete ; true"
		fi
		# tar -p alone restores mode bits but ignores xattrs/ACLs even if the
		# archive contains them — extract has its own gating switches. We need
		# --xattrs --xattrs-include='*' to restore security.* (e.g. file caps
		# placed by iputils-ping's postinst), --acls for POSIX ACLs, --selinux
		# for SELinux contexts, and --numeric-owner so user/group resolution
		# uses the archive's numeric IDs (the target's /etc/passwd is what
		# matters at boot, not the deploy host's).
		# Cleanup of the staged archive must run regardless of mkdir/tar
		# outcome — without that, a `set -e` shell on the remote exits on
		# tar failure and leaves the 200–800 MB rootfs archive under /tmp.
		# `&&` keeps mkdir→tar short-circuit; capture the rc, run rm
		# unconditionally, propagate the original rc so Armbian's set -e
		# still aborts on the real failure.
		run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
			"${sudo_prefix}mkdir -p ${q_nfs_path} \
			 && ${sudo_prefix}tar -xp --numeric-owner --xattrs --xattrs-include='*' --acls --selinux -f ${q_remote_archive} -C ${q_nfs_path}; \
			 ret=\$?; rm -f ${q_remote_archive}; exit \${ret}"
	else
		display_alert "${EXTENSION}: no archive" \
			"ROOTFS_EXPORT_DIR path — builder writes directly, skip" "info"
	fi

	# Stage 2 — TFTP payload via staging + atomic mv-swap. Empty
	# ${PREFIX} falls back to direct rsync (same edge case already noted
	# for --delete: sibling-board clobber risk). Staging is pre-populated
	# with a cp -al hard-linked copy of current production so
	# NETBOOT_DEPLOY_TFTP_DELETE=no merge semantics survive — pre-existing
	# admin-placed artifacts are seeded into staging, and the staging-
	# side rsync's --delete (when DELETE=yes) prunes them only when the
	# user opted in.
	if [[ -n "${NETBOOT_TFTP_PREFIX}" ]]; then
		declare tftp_prefix_path="${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}"
		declare staging_path="${tftp_prefix_path}.staging.${BASHPID}.${RANDOM}"
		declare prev_path="${tftp_prefix_path}.prev.${BASHPID}.${RANDOM}"
		declare q_tftp_prefix q_staging_path q_prev_path
		q_tftp_prefix="'${tftp_prefix_path//\'/\'\\\'\'}'"
		q_staging_path="'${staging_path//\'/\'\\\'\'}'"
		q_prev_path="'${prev_path//\'/\'\\\'\'}'"

		run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
			"if ${sudo_prefix}test -d ${q_tftp_prefix}; then ${sudo_prefix}cp -al ${q_tftp_prefix} ${q_staging_path}; fi"

		display_alert "${EXTENSION}: rsync TFTP payload (staged)" \
			"${NETBOOT_TFTP_OUT}/${NETBOOT_TFTP_PREFIX}/ -> ${NETBOOT_DEPLOY_SSH}:${staging_path}/" "info"
		run_host_command_logged_raw rsync "${rsync_payload[@]}" \
			"${NETBOOT_TFTP_OUT}/${NETBOOT_TFTP_PREFIX}/" \
			"${NETBOOT_DEPLOY_SSH}:${staging_path}/"

		# Atomic mv-swap with rollback. If the final mv fails after we
		# moved production aside, restore the original so the live
		# ${PREFIX} is never absent. Same-filesystem rename is sub-
		# second; PXE clients hitting the gap get a no-file (boot retry),
		# not a half-updated payload.
		display_alert "${EXTENSION}: swap staging into production" \
			"${tftp_prefix_path}" "info"
		run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
			"if ${sudo_prefix}test -d ${q_tftp_prefix}; then \
				${sudo_prefix}mv ${q_tftp_prefix} ${q_prev_path} && \
				{ ${sudo_prefix}mv ${q_staging_path} ${q_tftp_prefix} || \
					{ ${sudo_prefix}mv ${q_prev_path} ${q_tftp_prefix}; exit 1; }; } && \
				${sudo_prefix}rm -rf ${q_prev_path}; \
			else \
				${sudo_prefix}mv ${q_staging_path} ${q_tftp_prefix}; \
			fi"
	else
		display_alert "${EXTENSION}: rsync TFTP payload" \
			"${NETBOOT_TFTP_OUT}/${NETBOOT_TFTP_PREFIX}/ -> ${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/" "info"
		run_host_command_logged_raw rsync "${rsync_payload[@]}" \
			"${NETBOOT_TFTP_OUT}/${NETBOOT_TFTP_PREFIX}/" \
			"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/"
	fi

	# Stage 3 — pxelinux.cfg.
	if [[ -d "${NETBOOT_TFTP_OUT}/pxelinux.cfg" ]]; then
		display_alert "${EXTENSION}: rsync pxelinux.cfg" \
			"${NETBOOT_TFTP_OUT}/pxelinux.cfg/ -> ${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/pxelinux.cfg/" "info"
		run_host_command_logged_raw rsync "${rsync_base[@]}" \
			"${NETBOOT_TFTP_OUT}/pxelinux.cfg/" \
			"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/pxelinux.cfg/"
	fi

	display_alert "${EXTENSION}: done" "${NETBOOT_DEPLOY_SSH}" "info"
)

# Standalone-kernel deploy: fired by core's `artifact_ready` after a
# `compile.sh kernel ...` run. No image, no rootfs archive — the canonical
# linux-image-${BRANCH}-${LINUXFAMILY} .deb is unpacked locally; vmlinuz +
# dtbs go to TFTP, /lib/modules/<ver>/ goes to the NFS rootfs.
#
# Scope: kernel + modules only. Initramfs is intentionally NOT regenerated
# here — it depends on the rootfs that was customized at full image build
# time (customize_image hooks, /etc/initramfs-tools tweaks, board-specific
# extensions, userpatches overlay), and that context does not survive on
# the build host past the original image deploy. The configured rootfs now
# lives only on the NFS server, which may be an OpenWRT box or anything
# else that cannot run chroot+update-initramfs. Regenerating from the
# generic post-debootstrap rootfs cache would produce a *different*
# initramfs than the one the full image build would have made — fake.
#
# Therefore: any pre-existing uInitrd on TFTP is removed so U-Boot does
# not load an initramfs whose modules have stale vermagic against the
# new kernel. Boards with built-in boot networking (mvneta, etc.) come
# up cleanly without initramfs via root=/dev/nfs ip=dhcp; boards that
# need modular drivers in initramfs (USB-eth, modular NICs) will fail
# fast at networking — the fix for those is a full image rebuild, not
# a kernel-only refresh.
#
# Closes the split-BTF coherence gap: a fresh kernel was getting paired
# with stale modules in the on-NFS rootfs, producing `BPF: Invalid
# name_offset` spam until a full image rebuild.
function artifact_ready__netboot_kernel_deploy() (
	declare scratch_key=""
	declare scratch_dir=""
	trap '
		[[ -n "${scratch_key:-}" && -f "${scratch_key}" ]] && rm -f "${scratch_key}"
		[[ -n "${scratch_dir:-}" && -d "${scratch_dir}" ]] && rm -rf "${scratch_dir}"
	' EXIT

	# Fire only on standalone `compile.sh kernel ...` runs. A full image build
	# (`compile.sh build ...`) also obtains a kernel artifact internally and
	# triggers `artifact_ready` with WHAT=kernel — letting this hook proceed
	# there would rsync /lib/modules/<ver>/ into the NFS export ahead of the
	# full-image rootfs deploy, which then fails when tar tries to restore the
	# `lib -> usr/lib` usrmerge symlink against the now-existing `lib/`
	# directory. The full image flow already deploys kernel + modules via the
	# rootfs archive in `netboot_artifacts_ready__deploy_to_remote_server`;
	# this kernel-only handler is the optimization for the no-rebuild path.
	[[ "${ARMBIAN_COMMAND:-}" == "kernel" ]] || return 0
	# Filter out kernel-config/kernel-patch interactive sessions and kernel-dtb
	# where modules are not produced; require an SSH target.
	[[ "${WHAT:-}" == "kernel" ]] || return 0
	[[ -n "${NETBOOT_DEPLOY_SSH:-}" ]] || return 0

	# Same defaults and SSH-options shaping as the full-deploy hook above —
	# kept inline rather than refactored into a helper to keep each hook self-
	# contained for readers who jump in from a stack trace.
	declare NETBOOT_DEPLOY_TFTP_ROOT="${NETBOOT_DEPLOY_TFTP_ROOT:-/srv/netboot/tftp}"
	declare NETBOOT_DEPLOY_SUDO="${NETBOOT_DEPLOY_SUDO:-no}"
	declare NETBOOT_DEPLOY_SSH_KEY="${NETBOOT_DEPLOY_SSH_KEY:-}"
	declare NETBOOT_DEPLOY_SSH_TOFU="${NETBOOT_DEPLOY_SSH_TOFU:-no}"
	declare NETBOOT_DEPLOY_SSH_OPTS="${NETBOOT_DEPLOY_SSH_OPTS:--o BatchMode=yes}"
	if [[ "${NETBOOT_DEPLOY_SSH_TOFU}" == "yes" ]]; then
		NETBOOT_DEPLOY_SSH_OPTS+=" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new"
	fi

	if [[ -n "${NETBOOT_DEPLOY_SSH_KEY}" ]]; then
		if [[ ! -f "${NETBOOT_DEPLOY_SSH_KEY}" ]]; then
			exit_with_error "${EXTENSION}: NETBOOT_DEPLOY_SSH_KEY set but not visible in container" \
				"${NETBOOT_DEPLOY_SSH_KEY}"
		fi
		mkdir -p "${SRC}/.tmp"
		scratch_key="$(mktemp -p "${SRC}/.tmp" "netboot-kdeploy-key.XXXXXX")"
		cp "${NETBOOT_DEPLOY_SSH_KEY}" "${scratch_key}"
		chmod 600 "${scratch_key}"
		NETBOOT_DEPLOY_SSH_OPTS="-i ${scratch_key} ${NETBOOT_DEPLOY_SSH_OPTS}"
	fi

	declare sudo_prefix=""
	[[ "${NETBOOT_DEPLOY_SUDO}" == "yes" ]] && sudo_prefix="sudo -n "
	# shellcheck disable=SC2206
	declare -a ssh_opts=(${NETBOOT_DEPLOY_SSH_OPTS})

	# Defaults are computed lazily by netboot.sh — calling here, at hook time,
	# guarantees `${LINUXFAMILY}` is populated before the path is materialized
	# (the same helper is what the full-image deploy hooks call).
	_netboot_compute_runtime_defaults
	[[ -n "${NETBOOT_TFTP_PREFIX:-}" && -n "${NETBOOT_NFS_PATH:-}" ]] ||
		exit_with_error "${EXTENSION}: NETBOOT_TFTP_PREFIX / NETBOOT_NFS_PATH unset after compute" \
			"netboot extension not loaded? check ENABLE_EXTENSIONS contains 'netboot'"

	# Validate effective remote root BEFORE any TFTP-side write. The
	# rsync/sed/ssh sequence below mutates `${NETBOOT_TFTP_PREFIX}/...`
	# (kernel, uInitrd, pxelinux.cfg, dtb/) and only then touches the
	# NFS-side /lib/modules/<ver>/. If we waited until that NFS rsync to
	# discover the SSH user is non-root with NETBOOT_DEPLOY_SUDO=no, the
	# function would abort mid-deploy with the TFTP payload already
	# replaced — boards would PXE the new kernel against stale modules and
	# the very split-BTF coherence this hook exists to guarantee would be
	# broken. Check first, fail atomically.
	_netboot_deploy_require_remote_root "kernel-only deploy"

	# Pick the reversioned linux-image .deb. Source of truth is core's
	# `artifact_map_debs_reversioned[linux-image]`, populated by
	# `artifact_reversion_for_deployment` immediately before
	# `artifact_ready` fires (see lib/functions/artifacts/artifacts-obtain.sh
	# around line 313 and 320). Using the map avoids a filesystem glob,
	# which can match leftover .debs from prior builds since `${DEB_STORAGE}`
	# is not cleaned between runs and would silently pick the alphabetically-
	# first stale match. Quoted index ("linux-image") prevents shfmt from
	# misparsing the hyphen as a minus operator and inserting spaces.
	declare linux_image_basename="${artifact_map_debs_reversioned["linux-image"]:-}"
	if [[ -z "${linux_image_basename}" ]]; then
		exit_with_error "${EXTENSION}: linux-image not in artifact_map_debs_reversioned" \
			"available keys: ${!artifact_map_debs_reversioned[*]}"
	fi
	declare linux_image_deb="${DEB_STORAGE}/${linux_image_basename}"
	if [[ ! -f "${linux_image_deb}" ]]; then
		exit_with_error "${EXTENSION}: linux-image .deb missing on disk after reversion" \
			"${linux_image_deb}"
	fi

	# A linux-image .deb is ~50-100 MB extracted; /tmp on Armbian build hosts
	# is typically tmpfs (RAM-bound) and shared with the kernel build itself.
	# Stay under the project tree — same FS as cache/, generous, predictable.
	mkdir -p "${SRC}/.tmp"
	scratch_dir="$(mktemp -d -p "${SRC}/.tmp" "netboot-kdeploy.XXXXXX")"
	display_alert "${EXTENSION}: unpack kernel deb" \
		"${linux_image_deb##*/} -> ${scratch_dir}" "info"
	run_host_command_logged_raw dpkg-deb -x "${linux_image_deb}" "${scratch_dir}"

	# Single /lib/modules/<ver>/ tree per linux-image deb. Resolve once.
	declare kver=""
	for d in "${scratch_dir}"/lib/modules/*/; do
		[[ -d "${d}" ]] || continue
		kver="${d%/}"
		kver="${kver##*/}"
		break
	done
	if [[ -z "${kver}" ]]; then
		exit_with_error "${EXTENSION}: no kernel version dir under ${scratch_dir}/lib/modules"
	fi

	declare -a rsync_base=(-av --mkpath -e "ssh ${NETBOOT_DEPLOY_SSH_OPTS}")
	[[ "${NETBOOT_DEPLOY_SUDO}" == "yes" ]] && rsync_base+=(--rsync-path="sudo -n rsync")

	# Kernel binary: a raw `linux-image-*.deb` from `make bindeb-pkg` carries
	# `/boot/vmlinuz-<ver>`. The on-target TFTP layout that netboot.sh's own
	# `pre_umount_final_image__900_collect_netboot_artifacts` produces, on the
	# other hand, places the binary directly at `${NETBOOT_TFTP_PREFIX}/Image`
	# (arm64) or `${NETBOOT_TFTP_PREFIX}/zImage` (armv7) — alongside `uInitrd`
	# and `dtb/`. Mirror that exact naming so a kernel refresh overwrites the
	# same path the bootloader fetches, instead of sprouting a `boot/` subdir
	# the bootloader doesn't look in.
	declare kernel_src="${scratch_dir}/boot/vmlinuz-${kver}"
	if [[ ! -f "${kernel_src}" ]]; then
		exit_with_error "${EXTENSION}: ${kernel_src} missing in unpacked deb" \
			"linux-image deb has unexpected layout; expected /boot/vmlinuz-${kver}"
	fi
	# Derive the on-target TFTP filename from NAME_KERNEL — the same source
	# of truth Armbian's arch/family configs use (config/sources/arm64.conf,
	# riscv64.conf, armhf.conf, loong64.conf; families can override, e.g.
	# meson uses uImage). Hardcoding arm64→Image / *→zImage would silently
	# write to the wrong TFTP path on riscv64 (NAME_KERNEL=Image), loong64
	# (vmlinux), and any family-overridden value, leaving the next PXE boot
	# pointed at the previous kernel while only modules got refreshed.
	declare kernel_name="${NAME_KERNEL:-}"
	[[ -n "${kernel_name}" ]] || exit_with_error \
		"${EXTENSION}: NAME_KERNEL not set, cannot pick TFTP filename for kernel-only deploy" \
		"expected from arch (config/sources/<arch>.conf) or family include — sourcing didn't complete?"
	display_alert "${EXTENSION}: rsync kernel to TFTP" \
		"vmlinuz-${kver} -> ${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/${kernel_name}" "info"
	run_host_command_logged_raw rsync "${rsync_base[@]}" \
		"${kernel_src}" \
		"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/${kernel_name}"

	# Drop any pre-existing uInitrd from TFTP. See the function's header
	# comment for the full rationale: kernel-only deploy intentionally does
	# not regenerate initramfs (cannot, without the configured rootfs context),
	# and leaving the previous full-image build's uInitrd next to a fresh
	# kernel would have U-Boot load it and the kernel hit vermagic mismatches
	# inside initramfs's modprobe. Removing it makes U-Boot proceed without
	# initramfs — clean boot on built-in-NIC boards, fail-fast on modular-NIC
	# ones (the operator then knows to do a full image rebuild).
	declare q_uinitrd_path
	q_uinitrd_path="'${NETBOOT_DEPLOY_TFTP_ROOT//\'/\'\\\'\'}/${NETBOOT_TFTP_PREFIX//\'/\'\\\'\'}/uInitrd'"
	display_alert "${EXTENSION}: drop stale uInitrd from TFTP" \
		"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/uInitrd" "info"
	run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
		"${sudo_prefix}rm -f ${q_uinitrd_path}"

	# Also drop the matching `INITRD ${NETBOOT_TFTP_PREFIX}/uInitrd` stanza
	# from any pxelinux.cfg/* that still references it. U-Boot's PXE/extlinux
	# loader (boot/pxe_utils.c, get_relfile_envaddr) aborts a label with
	# "Skipping ... for failure retrieving initrd" when INITRD is specified
	# but the file is gone — so dropping just the file would brick the next
	# PXE boot instead of letting it fall back to an initramfs-less boot.
	# Match only lines whose path equals exactly `${NETBOOT_TFTP_PREFIX}/uInitrd`
	# so labels for unrelated boards/branches/releases under the same
	# admin-shared pxelinux.cfg/ directory are left untouched. `#` as the
	# sed-address delimiter avoids escaping the `/`-rich path inside
	# NETBOOT_TFTP_PREFIX. Trailing `; true` keeps the ssh exit clean when
	# pxelinux.cfg/ does not exist yet (first deploy with no prior full
	# image build, or an admin who keeps PXE configs elsewhere).
	# NETBOOT_TFTP_PREFIX is interpolated into a sed BRE — a custom prefix
	# containing regex metacharacters (`.`, `*`, `[`, `^`, `$`, `\`) would
	# otherwise widen the pattern and silently delete INITRD lines on
	# unrelated PXE entries. We also use `#` as the sed address delimiter
	# below, so escape `#` too. Class-internal `]` goes first to keep the
	# bracket set well-formed.
	declare bre_safe_tftp_prefix
	bre_safe_tftp_prefix="$(printf '%s' "${NETBOOT_TFTP_PREFIX}" | sed 's#[]\\/.*^$#[]#\\&#g')"
	declare initrd_pattern q_initrd_pattern q_pxelinux_dir
	initrd_pattern="^[[:space:]]*INITRD[[:space:]][[:space:]]*${bre_safe_tftp_prefix}/uInitrd[[:space:]]*\$"
	q_initrd_pattern="'${initrd_pattern//\'/\'\\\'\'}'"
	q_pxelinux_dir="'${NETBOOT_DEPLOY_TFTP_ROOT//\'/\'\\\'\'}/pxelinux.cfg'"
	display_alert "${EXTENSION}: drop matching INITRD line from pxelinux.cfg" \
		"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/pxelinux.cfg/* (INITRD ${NETBOOT_TFTP_PREFIX}/uInitrd)" "info"
	run_host_command_logged_raw ssh "${ssh_opts[@]}" "${NETBOOT_DEPLOY_SSH}" \
		"test -d ${q_pxelinux_dir} && ${sudo_prefix}find ${q_pxelinux_dir} -type f -exec sed -i '\\#'${q_initrd_pattern}'#d' {} + ; true"

	# DTBs: linux-image deb stages them under /usr/lib/linux-image-<ver>/.
	# netboot.sh on a full image rebuild flattens them into ${NETBOOT_TFTP_PREFIX}/dtb/
	# (e.g. dtb/rockchip/rk3399-helios64.dtb). Reproduce that layout exactly so
	# the bootloader's `fdt_addr_r=...; load tftp ${fdt_addr_r} ${tftp_prefix}/dtb/<vendor>/<board>.dtb`
	# keeps working. Skip silently when the deb has no dtbs (KERNEL_BUILD_DTBS=no, x86).
	#
	# --delete mirrors the full-image deploy: dtb/ lives entirely under the
	# board+branch+release-scoped NETBOOT_TFTP_PREFIX, so pruning here only
	# touches DTBs that disappeared from this kernel's package — a renamed
	# or removed BOOT_FDT_FILE would otherwise keep loading a stale DTB
	# against the fresh kernel, the exact coherence gap this hook closes.
	if [[ -d "${scratch_dir}/usr/lib/linux-image-${kver}" ]]; then
		declare -a rsync_dtbs=("${rsync_base[@]}" --delete)
		display_alert "${EXTENSION}: rsync dtbs to TFTP" \
			"usr/lib/linux-image-${kver}/ -> ${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/dtb/" "info"
		run_host_command_logged_raw rsync "${rsync_dtbs[@]}" \
			"${scratch_dir}/usr/lib/linux-image-${kver}/" \
			"${NETBOOT_DEPLOY_SSH}:${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/dtb/"
	fi

	# NFS side: --delete inside this kernel version's /lib/modules/<ver>/
	# only. Stale .ko files from the previous build of *this* kernel are the
	# whole point of this hook (split-BTF coherence). Other kernel versions
	# in /lib/modules/ — e.g. dual-boot setups, older edge alongside current
	# — are untouched. Remote-root precondition is validated up-front at hook
	# entry so this rsync never runs against a partially-deployed TFTP tree.
	declare -a rsync_modules=("${rsync_base[@]}" --delete)
	display_alert "${EXTENSION}: rsync modules to NFS rootfs" \
		"lib/modules/${kver}/ -> ${NETBOOT_DEPLOY_SSH}:${NETBOOT_NFS_PATH}/lib/modules/${kver}/" "info"
	run_host_command_logged_raw rsync "${rsync_modules[@]}" \
		"${scratch_dir}/lib/modules/${kver}/" \
		"${NETBOOT_DEPLOY_SSH}:${NETBOOT_NFS_PATH}/lib/modules/${kver}/"

	display_alert "${EXTENSION}: kernel deploy done" \
		"${NETBOOT_DEPLOY_SSH} (kver=${kver})" "info"
	# Initramfs is not produced here — see the function's header comment.
	# The previous uInitrd was already dropped from TFTP above; this alert
	# exists so the operator sees, in the build log, that initramfs is a
	# concern of the full image build and not of kernel-only deploy.
	display_alert "${EXTENSION}: skipped initramfs refresh" \
		"kernel-only deploy cannot regenerate initramfs (depends on configured rootfs context); for a fresh initramfs do a full image rebuild" "warn"
)
