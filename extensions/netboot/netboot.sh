#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Igor Velkov
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# Netboot: produce kernel + DTB + extlinux.conf + rootfs archive/export tree for TFTP/NFS root
# boot without local storage. See Developer-Guide_Netboot.md for server setup
# (tftpd-hpa + nfs-kernel-server + router DHCP options) and for the
# `netboot_artifacts_ready` hook used to auto-deploy artifacts to a server.
#
# Variables:
#   NETBOOT_SERVER            IP of the NFS server baked into nfsroot=. If
#                             empty, APPEND uses nfsroot=<path>,tcp,v3 with no
#                             server, and the kernel takes the NFS server from
#                             DHCP siaddr (the boot-server field of DHCPOFFER)
#                             at boot. Per-host rootfs paths live in the
#                             per-board pxelinux.cfg files; the server is a
#                             single network-wide value (set via dnsmasq
#                             `dhcp-boot`/`next-server`, ISC `next-server`,
#                             etc.). DHCP option 17 (root-path) is no longer
#                             consulted in this mode — option 17 is a
#                             network-wide singleton (one path for all
#                             clients) which doesn't scale to multi-board
#                             setups.
#   NETBOOT_TFTP_PREFIX       Path prefix inside TFTP root. Default:
#                             armbian/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}
#   NETBOOT_NFS_PATH          Absolute NFS path of rootfs on the server.
#                             Default depends on NETBOOT_HOSTNAME — see below.
#   NETBOOT_HOSTNAME          Per-host deployment. When set, default NFS path
#                             becomes /srv/netboot/rootfs/hosts/<hostname>
#                             (each machine owns a full writable rootfs copy).
#                             When empty, shared/${LINUXFAMILY}/${BOARD}/... is used.
#   NETBOOT_CLIENT_MAC        Client MAC (aa:bb:cc:dd:ee:ff or aa-bb-cc-dd-ee-ff).
#                             Tags the generated PXE config so multiple build
#                             variants coexist on one TFTP root without
#                             overwriting each other. Filename layout:
#                                 set    → `01-<mac>.<board>-<branch>-<release>[-<hostname>]`
#                                 unset  → `<board>-<branch>-<release>[-<hostname>].example`
#                             Neither is a valid PXELINUX fallback path — the
#                             operator picks the active variant by symlinking
#                             it to `default-<arch>-<board>` (or `01-<mac>`
#                             without suffix). Rebuilding one variant does not
#                             touch the active link.
#   ROOTFS_COMPRESSION        gzip | zstd | zst | none. Empty defers to the
#                             default in rootfs-to-image.sh. `none` requires
#                             ROOTFS_EXPORT_DIR (archive step is skipped).
#   ROOTFS_EXPORT_DIR         Optional rsync-target for the rootfs tree.
#                             Relative           → ${SRC}/output/netboot-export/<value>
#                             Absolute under base → kept as-is
#                             Absolute elsewhere → bind-mounted into the
#                                                  container at the same path
#                                                  (target must exist on host).
#                             System roots (`/`, `/etc`, `/usr`, ...) and
#                             `..` segments are rejected. A non-empty target
#                             without the .netboot_export_marker stamp at its
#                             root is refused (refuses to clobber an unrelated
#                             Linux tree); pass NETBOOT_EXPORT_FORCE=yes to
#                             override.
#   NETBOOT_EXPORT_FORCE      Set to "yes" to allow overwriting a non-empty
#                             ROOTFS_EXPORT_DIR that lacks the
#                             .netboot_export_marker stamp (rsync --delete
#                             will clobber whatever is there).
#   NETBOOT_ROOTDELAY         Seconds the initramfs NFS-mount script waits
#                             before retrying a failed mount (passed as
#                             `rootdelay=N` in the kernel cmdline; consumed
#                             by /usr/share/initramfs-tools/scripts/nfs).
#                             Empty (default) leaves the upstream 180s.
#                             Lower (e.g. 30) speeds up boot failure on a
#                             dead NFS server in trusted labs. Does NOT
#                             affect the `Waiting up to 180 secs for end0`
#                             netdev wait — that one is hardcoded in
#                             initramfs-tools scripts/functions:395.
#
# Hook:
#   netboot_artifacts_ready   Called after all artifacts are staged. Exposed
#                             context: NETBOOT_TFTP_OUT, NETBOOT_TFTP_PREFIX,
#                             NETBOOT_NFS_PATH, NETBOOT_PXE_FILE,
#                             NETBOOT_ROOTFS_ARCHIVE (may be empty if
#                             ROOTFS_COMPRESSION=none), plus BOARD/LINUXFAMILY/
#                             BRANCH/RELEASE. Use it from userpatches to rsync
#                             to a netboot server, unpack the rootfs archive,
#                             etc. For builder-as-NFS-server workflows prefer
#                             ROOTFS_EXPORT_DIR to skip the archive step.

function extension_prepare_config__netboot_defaults_and_validate() {
	# Keep non-nfs-root builds (ext4/btrfs/...) unaffected by this extension.
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	declare -g NETBOOT_SERVER="${NETBOOT_SERVER:-}"
	# nfs-root has no local storage — prevent boot partition creation (and the
	# resulting phantom /boot fstab entry whose UUID points at nothing).
	# $MOUNT/boot/ remains accessible via the bind mount from $SDCARD (line 394
	# of partitioning.sh), so pre_umount_final_image__900 still finds kernel/DTB.
	# The early return above keeps this safe for non-nfs-root builds.
	# shellcheck disable=SC2034 # BOOTSIZE is read by armbian core (skips /boot partition)
	declare -g BOOTSIZE=0
	declare -g NETBOOT_HOSTNAME="${NETBOOT_HOSTNAME:-}"
	declare -g NETBOOT_CLIENT_MAC="${NETBOOT_CLIENT_MAC:-}"
	declare -g NETBOOT_ROOTDELAY="${NETBOOT_ROOTDELAY:-}"
	if [[ -n "${NETBOOT_ROOTDELAY}" && ! "${NETBOOT_ROOTDELAY}" =~ ^[0-9]+$ ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_ROOTDELAY must be a non-negative integer (got '${NETBOOT_ROOTDELAY}')"
	fi
	# Declared unconditionally so later `[[ -n "${NETBOOT_CLIENT_MAC_NORMALIZED}" ]]`
	# checks remain safe under `set -u` when no MAC is configured.
	declare -g NETBOOT_CLIENT_MAC_NORMALIZED=""
	# Build-flavor suffix lets default TFTP/NFS/PXE layouts coexist for the
	# same board/release/branch when several flavors are built (CLI vs
	# minimal vs desktop). Declared global so the post-build hook that
	# composes pxe_tag and the deploy hook can pick it up. Only applied to
	# defaults — user-supplied NETBOOT_TFTP_PREFIX / NETBOOT_NFS_PATH are
	# honored verbatim. Computed here (early) because BUILD_MINIMAL /
	# BUILD_DESKTOP are static config inputs, not derived from family
	# sourcing — safe to inspect in extension_prepare_config.
	declare -g _NETBOOT_FLAVOR=""
	if [[ "${BUILD_MINIMAL:-no}" == "yes" ]]; then
		_NETBOOT_FLAVOR="-min"
	elif [[ "${BUILD_DESKTOP:-no}" == "yes" ]]; then
		_NETBOOT_FLAVOR="-desktop"
	fi

	if [[ -n "${NETBOOT_CLIENT_MAC}" ]]; then
		NETBOOT_CLIENT_MAC_NORMALIZED="${NETBOOT_CLIENT_MAC//:/-}"
		NETBOOT_CLIENT_MAC_NORMALIZED="${NETBOOT_CLIENT_MAC_NORMALIZED,,}"
		if [[ ! "${NETBOOT_CLIENT_MAC_NORMALIZED}" =~ ^[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}$ ]]; then
			exit_with_error "${EXTENSION}: NETBOOT_CLIENT_MAC must look like aa:bb:cc:dd:ee:ff (got '${NETBOOT_CLIENT_MAC}')"
		fi
	fi

	# Disambiguate per-host artifact names so two host-specific builds for the
	# same board/release/branch don't overwrite each other's
	# ${version}-netboot-tftp / ${version}-rootfs.* on the builder. Append to
	# the EXTRA_IMAGE_SUFFIXES array, not the scalar — do_main_configuration
	# rebuilds the final EXTRA_IMAGE_SUFFIX from this array and declares it
	# readonly, so writes to the scalar from here are silently overwritten
	# before calculate_image_version() runs.
	if [[ -n "${NETBOOT_HOSTNAME}" ]]; then
		EXTRA_IMAGE_SUFFIXES+=("_${NETBOOT_HOSTNAME}")
	elif [[ -n "${NETBOOT_CLIENT_MAC_NORMALIZED}" ]]; then
		EXTRA_IMAGE_SUFFIXES+=("_${NETBOOT_CLIENT_MAC_NORMALIZED}")
	fi

	# Fail-fast on bad ROOTFS_COMPRESSION/ROOTFS_EXPORT_DIR combos before debootstrap,
	# not hours later in create_image_from_sdcard_rootfs. The default itself lives
	# in rootfs-to-image.sh; here we only validate values the user actually set.
	case "${ROOTFS_COMPRESSION:-}" in
		"" | gzip | zstd | zst | none) ;;
		*) exit_with_error "${EXTENSION}: unknown ROOTFS_COMPRESSION: '${ROOTFS_COMPRESSION:-}' (expected: gzip|zstd|zst|none)" ;;
	esac
	if [[ "${ROOTFS_COMPRESSION:-}" == "none" && -z "${ROOTFS_EXPORT_DIR:-}" ]]; then
		exit_with_error "${EXTENSION}: ROOTFS_COMPRESSION=none requires ROOTFS_EXPORT_DIR (otherwise nothing is produced)"
	fi

	_netboot_normalize_export_dir
}

# Resolve ROOTFS_EXPORT_DIR into a path the build will actually rsync into:
#   - relative              → confined under ${SRC}/output/netboot-export/<value>
#                             so `rsync --delete` cannot escape that subtree.
#   - absolute under base   → kept as-is.
#   - absolute elsewhere    → kept as-is and bind-mounted into the container
#                             at the same path (see host_pre_docker_launch
#                             hook below). System roots are rejected.
#
# Called on both the host (lazily from host_pre_docker_launch hooks, since
# extension_prepare_config only runs inside docker post-relaunch) and inside
# the container (where ${SRC}=/armbian). The host pass propagates ${SRC} via
# _NETBOOT_HOST_SRC --env so the in-container pass recognises a host-base
# path and translates it to the container-base path instead of re-prefixing.
function _netboot_normalize_export_dir() {
	[[ -z "${ROOTFS_EXPORT_DIR:-}" ]] && return 0

	case "${ROOTFS_EXPORT_DIR}" in
		*..*) exit_with_error "${EXTENSION}: ROOTFS_EXPORT_DIR must not contain '..'" "${ROOTFS_EXPORT_DIR}" ;;
	esac

	declare host_src="${_NETBOOT_HOST_SRC:-${SRC}}"

	if [[ "${ROOTFS_EXPORT_DIR}" != /* ]]; then
		declare -g ROOTFS_EXPORT_DIR="${SRC}/output/netboot-export/${ROOTFS_EXPORT_DIR}"
	elif [[ "${ROOTFS_EXPORT_DIR}" == "${SRC}/output/netboot-export" ||
		"${ROOTFS_EXPORT_DIR}" == "${SRC}/output/netboot-export/"* ]]; then
		: # already in the current ${SRC}'s base
	elif [[ "${ROOTFS_EXPORT_DIR}" == "${host_src}/output/netboot-export" ||
		"${ROOTFS_EXPORT_DIR}" == "${host_src}/output/netboot-export/"* ]]; then
		declare rest="${ROOTFS_EXPORT_DIR#"${host_src}"/output/netboot-export}"
		declare -g ROOTFS_EXPORT_DIR="${SRC}/output/netboot-export${rest}"
	else
		declare -g _NETBOOT_EXPORT_DIR_EXTERNAL=yes
	fi

	# Validate the resolved filesystem target for *every* path shape — relative,
	# absolute under-base, host-base translated, and absolute external. The
	# under-base branches would otherwise skip the blacklist/non-empty-target
	# guard, and `rsync --delete` could wipe an unrelated tree under the
	# netboot-export base. readlink -m also follows symlinks under the base
	# so a misaimed symlink there cannot escape into /etc, /srv/... etc.
	declare resolved
	resolved="$(readlink -m "${ROOTFS_EXPORT_DIR}" 2> /dev/null || echo "${ROOTFS_EXPORT_DIR}")"
	_netboot_validate_external_export_dir "${resolved}"
}

function _netboot_validate_external_export_dir() {
	declare path="${1:-${ROOTFS_EXPORT_DIR}}"
	# Blacklist of system roots that must never become ROOTFS_EXPORT_DIR.
	declare -ag NETBOOT_EXPORT_DIR_BLACKLIST=(
		/ /etc /usr /bin /sbin /lib /lib64 /boot
		/proc /sys /dev /run /tmp /var/log /var/run
	)
	call_extension_method "netboot_export_dir_blacklist" <<- 'NETBOOT_BL_DOC'
		*adjust the list of system roots forbidden as ROOTFS_EXPORT_DIR*
		Override or extend NETBOOT_EXPORT_DIR_BLACKLIST in your userpatches
		extension or hook function before the build descends into debootstrap.
	NETBOOT_BL_DOC

	declare entry
	for entry in "${NETBOOT_EXPORT_DIR_BLACKLIST[@]}"; do
		[[ "${path}" == "${entry}" ||
			"${path}" == "${entry}/"* ]] || continue
		exit_with_error "${EXTENSION}: ROOTFS_EXPORT_DIR overlaps blacklisted system path" \
			"'${path}' inside '${entry}'"
	done

	# Refuse to clobber a non-empty target that does not carry our own
	# netboot-export marker. /etc/os-release is too generic — any Linux tree
	# (Debian server, Ubuntu chroot, ...) has it. A dedicated marker placed
	# at the rootfs root by post_customize_image__netboot_install_export_marker
	# is specific to "this directory is a netboot-export tree we wrote earlier
	# and may overwrite". A freshly-created bind-mountpoint is empty and passes.
	if [[ -d "${path}" ]] &&
		[[ -n "$(ls -A "${path}" 2> /dev/null)" ]] &&
		[[ ! -f "${path}/.netboot_export_marker" ]] &&
		[[ "${NETBOOT_EXPORT_FORCE:-no}" != "yes" ]]; then
		exit_with_error "${EXTENSION}: ROOTFS_EXPORT_DIR is non-empty and lacks .netboot_export_marker" \
			"rsync --delete would clobber '${path}'; pass NETBOOT_EXPORT_FORCE=yes to override"
	fi
}

# Compute defaults for `NETBOOT_TFTP_PREFIX` and `NETBOOT_NFS_PATH` lazily,
# at hook time, instead of in `extension_prepare_config`. The naive default
# `armbian/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}` references
# `${LINUXFAMILY}`, which is populated late in the config dispatch (see
# `change-tracking: after defaulting LINUXFAMILY to BOARDFAMILY` in build
# logs); evaluating the default in `extension_prepare_config` on a kernel-only
# `compile.sh kernel ...` flow can capture an empty `${LINUXFAMILY}` and bake
# `armbian//${BOARD}/...` into the prefix. Calling this from the consuming
# hooks (artifact_collect, rootfs_archive_deploy, kernel_artifact_deploy)
# guarantees the values reflect the populated config snapshot.
function _netboot_compute_runtime_defaults() {
	declare -g NETBOOT_TFTP_PREFIX="${NETBOOT_TFTP_PREFIX:-armbian/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}${_NETBOOT_FLAVOR:-}}"
	# TFTP_PREFIX is appended to the staging root with `mkdir -p`; a `..` segment would
	# walk out of it and let an extension scribble onto arbitrary paths under FINALDEST.
	case "${NETBOOT_TFTP_PREFIX}" in
		*..*) exit_with_error "${EXTENSION}: NETBOOT_TFTP_PREFIX must not contain '..'" "${NETBOOT_TFTP_PREFIX}" ;;
	esac

	if [[ -n "${NETBOOT_HOSTNAME:-}" ]]; then
		declare -g NETBOOT_NFS_PATH="${NETBOOT_NFS_PATH:-/srv/netboot/rootfs/hosts/${NETBOOT_HOSTNAME}}"
	else
		declare -g NETBOOT_NFS_PATH="${NETBOOT_NFS_PATH:-/srv/netboot/rootfs/shared/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}${_NETBOOT_FLAVOR:-}}"
	fi
	if [[ "${NETBOOT_NFS_PATH}" != /* ]]; then
		exit_with_error "${EXTENSION}: NETBOOT_NFS_PATH must be an absolute path (got '${NETBOOT_NFS_PATH}')"
	fi
}

# Empty stub so the framework loads this file on the host phase. Required when
# `netboot` is auto-enabled later inside the container (e.g. via ROOTFS_TYPE=
# nfs-root): without a host-side dispatch point, host_pre_docker_launch hooks
# defined below would never be registered before docker launch, and the
# bind-mount of the export symlink would silently no-op.
function add_host_dependencies__netboot_stub() {
	:
}

# Builder-as-NFS-server: when ${SRC}/output/netboot-export is a symlink to an
# external directory (e.g. /srv/netboot/rootfs on the local NFS server), bind-
# mount the symlink target into the container at the same absolute path. This
# way the symlink resolves identically inside and outside the container, and
# rsync from inside (running as docker-root, no userns-remap) writes directly
# into the NFS export tree with original ownership preserved. The export step
# is a plain rsync — it copies file-by-file regardless of source/destination
# filesystem (no FICLONE / reflink path); incremental rebuilds rsync only
# changed files, which is where the actual time savings come from.
function host_pre_docker_launch__netboot_bindmount_export_symlink() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	# Skip when the build will not rsync into the export tree — bind-mounting the
	# NFS root into docker has no purpose without ROOTFS_EXPORT_DIR set.
	[[ -n "${ROOTFS_EXPORT_DIR:-}" ]] || return 0
	# Owns only the under-base export workflow. Absolute-external exports are
	# bind-mounted by host_pre_docker_launch__netboot_bindmount_external_export
	# at the narrow target path; doing it here too would also expose the wider
	# symlink target (e.g. all of /srv/netboot/rootfs) inside docker.
	_netboot_normalize_export_dir
	[[ "${ROOTFS_EXPORT_DIR}" == "${SRC}/output/netboot-export" ||
		"${ROOTFS_EXPORT_DIR}" == "${SRC}/output/netboot-export/"* ]] || return 0
	declare link="${SRC}/output/netboot-export"
	[[ -L "${link}" ]] || return 0
	declare target
	target="$(readlink -f "${link}" 2> /dev/null || true)"
	if [[ -z "${target}" || ! -d "${target}" ]]; then
		exit_with_error "${EXTENSION}: ${link} is a dangling symlink" "target='${target:-<unresolved>}'"
	fi
	# `--mount` CSV has no escape syntax — reject paths with commas.
	if [[ "${target}" == *,* ]]; then
		exit_with_error "${EXTENSION}: symlink target must not contain a comma" "${target}"
	fi
	display_alert "${EXTENSION}: bind-mounting NFS export root into container" "${target}" "info"
	DOCKER_EXTRA_ARGS+=("--mount" "type=bind,source=${target},target=${target}")
}

# Propagate host-side ${SRC} (and the external-path flag) into the container
# so the in-docker pass of _netboot_normalize_export_dir recognises a path
# already normalised against the host's ${SRC} and translates it to the
# container's /armbian base instead of stacking the prefix.
function host_pre_docker_launch__netboot_propagate_normalize_state() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	DOCKER_EXTRA_ARGS+=("--env" "_NETBOOT_HOST_SRC=${SRC}")
	if [[ "${_NETBOOT_EXPORT_DIR_EXTERNAL:-}" == "yes" ]]; then
		DOCKER_EXTRA_ARGS+=("--env" "_NETBOOT_EXPORT_DIR_EXTERNAL=yes")
	fi
}

# Builder-as-NFS-server, no-symlink variant: when ROOTFS_EXPORT_DIR is an
# absolute path outside ${SRC}/output/netboot-export, bind-mount it into the
# container at the same absolute path. rsync from inside writes directly into
# the host export tree with original ownership/xattrs preserved.
function host_pre_docker_launch__netboot_bindmount_external_export() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	# extension_prepare_config runs only inside docker (post-relaunch), so
	# normalize on the host here to set _NETBOOT_EXPORT_DIR_EXTERNAL before
	# the propagate_normalize_state hook (alphabetically later) reads it.
	# Idempotent: a no-op when already normalised.
	_netboot_normalize_export_dir
	[[ "${_NETBOOT_EXPORT_DIR_EXTERNAL:-}" == "yes" ]] || return 0
	declare target="${ROOTFS_EXPORT_DIR}"
	if [[ "${target}" == *,* ]]; then
		exit_with_error "${EXTENSION}: ROOTFS_EXPORT_DIR must not contain a comma" "${target}"
	fi
	# Target must exist on the host: docker bind-mount needs the source path,
	# and creating it here is unreliable (the parent is often root-owned NFS
	# tree while the build runs as the regular user pre-docker).
	if [[ ! -d "${target}" ]]; then
		exit_with_error "${EXTENSION}: ROOTFS_EXPORT_DIR does not exist on host" \
			"create '${target}' (with ownership writable by the build user) before launching the build"
	fi
	display_alert "${EXTENSION}: bind-mounting external export dir into container" "${target}" "info"
	DOCKER_EXTRA_ARGS+=("--mount" "type=bind,source=${target},target=${target}")
}

# Ensure NFS-root client support is built into the kernel.
function custom_kernel_config__netboot_enable_nfs_root() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	opts_y+=("ROOT_NFS" "NFS_FS" "NFS_V3" "IP_PNP" "IP_PNP_DHCP")
}

# Stamp the rootfs root with a netboot-export marker. The soft guard in
# _netboot_validate_external_export_dir uses this file to recognise a
# previously-exported armbian rootfs at ROOTFS_EXPORT_DIR and allow
# rsync --delete to overwrite it on the next build. Anything else
# (a stranger's Debian/Ubuntu tree at the same path) lacks the marker
# and gets refused unless NETBOOT_EXPORT_FORCE=yes. Created in $SDCARD
# so the rsync that exports the rootfs tree carries it along.
function post_customize_image__netboot_install_export_marker() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	cat > "${SDCARD}/.netboot_export_marker" <<- 'NETBOOT_EXPORT_MARKER'
		This file marks an Armbian netboot rootfs export.

		When this file is present at the root of ROOTFS_EXPORT_DIR, the
		netboot extension's safety guard treats the directory as a
		previously-exported armbian rootfs and lets a subsequent build
		overwrite it (rsync --delete) silently — the expected workflow
		for incremental rebuilds against the same NFS export tree.

		When this file is absent and the directory is non-empty, the
		guard refuses to write into it, to prevent accidentally wiping
		an unrelated Linux tree that happened to land at the same path.
		Pass NETBOOT_EXPORT_FORCE=yes to override the refusal.

		Created by: extensions/netboot/netboot.sh
	NETBOOT_EXPORT_MARKER
}

# armbian-resize-filesystem tries to grow the root fs on first boot via resize2fs.
# On an NFS-mounted root that's always meaningless (and would error) — strip the
# systemd enablement symlink so the unit never runs.
function post_customize_image__netboot_disable_resize_filesystem() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	display_alert "${EXTENSION}: disabling armbian-resize-filesystem.service" "meaningless on NFS root" "info"
	run_host_command_logged find "${SDCARD}/etc/systemd/system/" \
		-name "armbian-resize-filesystem.service" -type l -delete
}

# /etc/profile.d/armbian-check-first-login.sh launches the armbian-firstlogin
# whiptail wizard (root password → user → locale …) when /root/.not_logged_in_yet
# exists. On a default (empty) trigger the wizard would demand interactive input
# on the first login — inconvenient when iterating on netboot images. When the
# file is non-empty it contains PRESET_* keys (e.g. from the preset-firstrun
# extension) that let the wizard complete non-interactively, so we leave it alone.
function post_customize_image__netboot_skip_firstlogin_wizard() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	[[ -f "${SDCARD}/root/.not_logged_in_yet" ]] || return 0
	if [[ -s "${SDCARD}/root/.not_logged_in_yet" ]]; then
		display_alert "${EXTENSION}: keeping /root/.not_logged_in_yet" "non-empty — presets detected (e.g. preset-firstrun)" "info"
		return 0
	fi
	display_alert "${EXTENSION}: removing empty /root/.not_logged_in_yet" "wizard would block first login without presets" "info"
	run_host_command_logged rm -f "${SDCARD}/root/.not_logged_in_yet"
}

# Suppress the update-initramfs probe warning:
#   W: Couldn't identify type of root file system '/dev/nfs' for fsck hook
# fsck is not applicable to NFS-mounted roots, and the warning otherwise
# repeats on every initramfs rebuild (our own request_root_path + watchdog
# hooks below, plus any later kernel package upgrade on the booted host).
# Drop the snippet before the subsequent update-initramfs calls so they
# pick it up.
function post_customize_image__netboot_disable_initramfs_fsck() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0

	declare conf_d="${SDCARD}/etc/initramfs-tools/conf.d/netboot-no-fsck"
	display_alert "${EXTENSION}: installing initramfs.conf.d snippet" "FSCKFIX=no — silence /dev/nfs fsck warning" "info"
	run_host_command_logged install -D -m 0644 \
		"${EXTENSION_DIR}/files/initramfs-conf.d/netboot-no-fsck" "${conf_d}"
}

# Fix ROOTSERVER in initramfs for path-only nfsroot= boots. The stock
# 70-net-conf dhcpcd-hook sets ROOTSERVER to the default gateway (new_routers),
# which makes /scripts/nfs in initramfs-tools mount the rootfs from the wrong
# host. Our 71-netboot-rootpath hook reads the actual boot server from
# /proc/net/pnp (written by the kernel IP-Config from DHCP siaddr) and appends
# it last, so shell-source semantics in /scripts/nfs pick it over the gateway.
#
# Without this hook, nfs-root mounts attempt the gateway and time out.
function post_customize_image__netboot_request_root_path() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0

	declare dhcpcd_hook="${SDCARD}/usr/share/initramfs-tools/dhcpcd-hooks/71-netboot-rootpath"
	declare initramfs_hook="${SDCARD}/etc/initramfs-tools/hooks/netboot-rootpath"

	# Always install/overwrite both hooks so stale copies from earlier
	# revisions are replaced unconditionally (same idiom as the watchdog
	# hook installer below).
	display_alert "${EXTENSION}: installing dhcpcd hook" "71-netboot-rootpath records ROOTSERVER from /proc/net/pnp for nfsroot=" "info"
	run_host_command_logged install -D -m 0755 \
		"${EXTENSION_DIR}/files/dhcpcd-hooks/71-netboot-rootpath" "${dhcpcd_hook}"

	display_alert "${EXTENSION}: installing initramfs hook" "netboot-rootpath bundles 71-netboot-rootpath into uInitrd" "info"
	run_host_command_logged install -D -m 0755 \
		"${EXTENSION_DIR}/files/initramfs-hooks/netboot-rootpath" "${initramfs_hook}"

	# Kernel install ran update-initramfs earlier without our hooks present,
	# so rebuild now to ensure the uInitrd we ship over TFTP carries them.
	display_alert "${EXTENSION}: rebuilding initramfs" "to include 71-netboot-rootpath ROOTSERVER fix" "info"
	chroot_sdcard update-initramfs -u
}

function post_customize_image__netboot_initramfs_watchdog() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0

	declare premount="${SDCARD}/etc/initramfs-tools/scripts/init-premount/zz-netboot-watchdog"
	declare cancel="${SDCARD}/etc/initramfs-tools/scripts/nfs-bottom/zz-netboot-watchdog-cancel"

	# Always install/overwrite both hooks so stale copies from earlier revisions
	# (e.g. init-bottom/zz-netboot-watchdog-cancel) are replaced unconditionally.
	display_alert "${EXTENSION}: installing initramfs watchdog" "reboot after 10 min NFS hang" "info"
	run_host_command_logged install -D -m 0755 \
		"${EXTENSION_DIR}/files/initramfs-scripts/init-premount/zz-netboot-watchdog" "${premount}"
	run_host_command_logged install -D -m 0755 \
		"${EXTENSION_DIR}/files/initramfs-scripts/nfs-bottom/zz-netboot-watchdog-cancel" "${cancel}"
	display_alert "${EXTENSION}: rebuilding initramfs" "to include NFS watchdog" "info"
	chroot_sdcard update-initramfs -u
}

function pre_umount_final_image__900_collect_netboot_artifacts() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	_netboot_compute_runtime_defaults

	# shellcheck disable=SC2154 # ${version} is a readonly global set in create_image_from_sdcard_rootfs
	declare tftp_out="${FINALDEST}/${version}-netboot-tftp"
	declare tftp_prefix_dir="${tftp_out}/${NETBOOT_TFTP_PREFIX}"
	declare pxe_dir="${tftp_out}/pxelinux.cfg"
	# Wipe the per-prefix subtree first: cp below is additive, so on an
	# incremental rebuild a removed DTB or stale uInitrd from the previous
	# build would persist and the later BOOT_FDT_FILE sanity check would
	# validate against that stale tree. pxe_dir/ is intentionally NOT wiped —
	# it is admin-managed (multi-board TFTP root).
	run_host_command_logged rm -rf "${tftp_prefix_dir}"
	run_host_command_logged mkdir -pv "${tftp_prefix_dir}/dtb" "${pxe_dir}"

	# Kernel image: arm64 uses Image, armv7 uses zImage. Preserve source basename
	# so U-Boot `booti`/`bootz` still picks the right path via image header.
	declare kernel_src="" kernel_name=""
	if [[ -f "${MOUNT}/boot/Image" ]]; then
		kernel_src="${MOUNT}/boot/Image"
		kernel_name="Image"
	elif [[ -f "${MOUNT}/boot/zImage" ]]; then
		kernel_src="${MOUNT}/boot/zImage"
		kernel_name="zImage"
	elif [[ -n "${IMAGE_INSTALLED_KERNEL_VERSION:-}" && -f "${MOUNT}/boot/vmlinuz-${IMAGE_INSTALLED_KERNEL_VERSION}" ]]; then
		kernel_src="${MOUNT}/boot/vmlinuz-${IMAGE_INSTALLED_KERNEL_VERSION}"
		# vmlinuz-* is a generic bzImage/Image; prefer Image for arm64, zImage otherwise
		[[ "${ARCH}" == "arm64" ]] && kernel_name="Image" || kernel_name="zImage"
	fi
	[[ -n "${kernel_src}" ]] || exit_with_error "${EXTENSION}: kernel image not found under ${MOUNT}/boot"
	run_host_command_logged cp -v "${kernel_src}" "${tftp_prefix_dir}/${kernel_name}"

	# Stage DTBs only if the rootfs actually has them. linux-dtb is an ARM-only
	# deb; x86 and kernels built without KERNEL_BUILD_DTBS produce no /boot/dtb.
	declare dtb_payload=""
	if [[ -d "${MOUNT}/boot/dtb" ]]; then
		run_host_command_logged cp -a "${MOUNT}/boot/dtb/." "${tftp_prefix_dir}/dtb/"
		dtb_payload="dtb/"
	fi

	declare initrd_line=""
	if [[ -f "${MOUNT}/boot/uInitrd" ]]; then
		run_host_command_logged cp -v "${MOUNT}/boot/uInitrd" "${tftp_prefix_dir}/uInitrd"
		initrd_line="INITRD ${NETBOOT_TFTP_PREFIX}/uInitrd"
	fi

	# extlinux APPEND is passed verbatim to the kernel — U-Boot does not expand
	# ${var} inside it. With NETBOOT_SERVER set we bake the literal IP into
	# nfsroot=. Without it we emit nfsroot=<path>,tcp,v3 (no server) and the
	# kernel resolves the NFS server from DHCP siaddr at boot. Per-host paths
	# live in the per-board pxelinux.cfg file; the server is a single
	# network-wide DHCP value.
	declare nfsroot_param=" nfsroot=${NETBOOT_NFS_PATH},tcp,v3"
	if [[ -n "${NETBOOT_SERVER}" ]]; then
		nfsroot_param=" nfsroot=${NETBOOT_SERVER}:${NETBOOT_NFS_PATH},tcp,v3"
	fi

	# Initramfs NFS-mount retry delay (scripts/nfs:89 `delay=${ROOTDELAY:-180}`).
	# Empty NETBOOT_ROOTDELAY → kernel cmdline omits the param → upstream 180s
	# applies. Validation of numeric form happens in extension_prepare_config.
	declare rootdelay_param=""
	[[ -n "${NETBOOT_ROOTDELAY}" ]] && rootdelay_param=" rootdelay=${NETBOOT_ROOTDELAY}"

	# Intentionally no `console=` in APPEND: hardcoding a baud (e.g. 115200)
	# breaks boards like helios64 which run at 1500000. Kernel resolves console
	# from DTB `/chosen/stdout-path`; `earlycon` keeps the early output.

	# BOOT_FDT_FILE unset (e.g. helios64) → emit FDTDIR so U-Boot resolves via
	# its own ${fdtfile}. When no DTB tree was staged at all, skip FDT/FDTDIR
	# entirely so the PXE stanza never points at an empty TFTP directory —
	# mirrors the extlinux fallback in lib/functions/rootfs/distro-agnostic.sh.
	declare fdt_line=""
	if [[ -n "${BOOT_FDT_FILE:-}" && "${BOOT_FDT_FILE}" != "none" ]]; then
		# K3/BeagleBone boards declare BOOT_FDT_FILE with a .dts suffix (e.g.
		# ti/k3-am625-beagleplay.dts); in the TFTP tree we ship the compiled .dtb.
		# Normalize so the PXE stanza references a file that actually exists.
		declare fdt_file="${BOOT_FDT_FILE}"
		[[ "${fdt_file}" == *.dts ]] && fdt_file="${fdt_file%.dts}.dtb"
		# Fail fast if the DTB the PXE stanza points at is missing from the
		# staged tree. Otherwise U-Boot would silently fail `load … ${fdtfile}`
		# at boot time and drop to a prompt.
		if [[ ! -f "${tftp_prefix_dir}/dtb/${fdt_file}" ]]; then
			exit_with_error "${EXTENSION}: BOOT_FDT_FILE not found in staged TFTP dtb tree" "${fdt_file}"
		fi
		fdt_line="FDT ${NETBOOT_TFTP_PREFIX}/dtb/${fdt_file}"
	elif [[ -n "${dtb_payload}" ]]; then
		fdt_line="FDTDIR ${NETBOOT_TFTP_PREFIX}/dtb"
	fi

	# Tag the PXE config file with the same coordinates that name the kernel
	# image and rootfs tree (board / branch / release [ / hostname ]) so that
	# multiple build variants can coexist in pxelinux.cfg/ without overwriting
	# each other on every rebuild. Names like `helios64-edge-resolute.example`
	# or `01-aa-bb-cc-dd-ee-ff.helios64-edge-trixie` are NOT valid PXELINUX
	# fallback paths; the operator picks the active variant by symlinking it
	# into `default-<arch>-<board>` (or `01-<mac>` without the suffix). This
	# also means rebuilding one release doesn't touch the active link.
	declare pxe_tag="${BOARD}-${BRANCH}-${RELEASE}${_NETBOOT_FLAVOR}"
	[[ -n "${NETBOOT_HOSTNAME}" ]] && pxe_tag="${pxe_tag}-${NETBOOT_HOSTNAME}"
	declare pxe_file
	if [[ -n "${NETBOOT_CLIENT_MAC_NORMALIZED}" ]]; then
		pxe_file="01-${NETBOOT_CLIENT_MAC_NORMALIZED}.${pxe_tag}"
	else
		pxe_file="${pxe_tag}.example"
	fi

	cat > "${pxe_dir}/${pxe_file}" <<- EXTLINUX_CONF
		# Generated by ${EXTENSION} for ${BOARD} ${BRANCH} ${RELEASE}
		# Target NFS path: ${NETBOOT_NFS_PATH}
		DEFAULT armbian
		TIMEOUT 30
		PROMPT 0

		LABEL armbian
		    MENU LABEL Armbian ${BOARD} ${BRANCH} ${RELEASE} (netboot)
		    KERNEL ${NETBOOT_TFTP_PREFIX}/${kernel_name}${fdt_line:+
		    ${fdt_line}}${initrd_line:+
		    ${initrd_line}}
		    APPEND root=/dev/nfs${nfsroot_param} ip=dhcp rw rootwait${rootdelay_param} earlycon loglevel=7 panic=3
	EXTLINUX_CONF

	display_alert "${EXTENSION}: artifacts ready" "${tftp_out}" "info"
	display_alert "${EXTENSION}: TFTP payload" "${NETBOOT_TFTP_PREFIX}/ (${kernel_name}${dtb_payload:+, ${dtb_payload}}${initrd_line:+, uInitrd})" "info"
	display_alert "${EXTENSION}: PXE config" "pxelinux.cfg/${pxe_file}" "info"
	display_alert "${EXTENSION}: target NFS path" "${NETBOOT_NFS_PATH}" "info"

	# Expose TFTP/PXE context for the deploy hook. The rootfs archive path is
	# not known yet — it is produced after pre_umount_final_image, so the
	# actual netboot_artifacts_ready dispatch happens in post_create_rootfs_archive.
	# shellcheck disable=SC2034 # exposed as netboot_artifacts_ready hook context
	declare -g NETBOOT_TFTP_OUT="${tftp_out}"
	# shellcheck disable=SC2034 # exposed as netboot_artifacts_ready hook context
	declare -g NETBOOT_PXE_FILE="${pxe_file}"
}

# Dispatched after the rootfs archive / export tree is fully produced, so
# ${ROOTFS_ARCHIVE_PATH} is populated (or deliberately empty when
# ROOTFS_COMPRESSION=none). At this point every netboot artifact exists on
# disk and deploy hooks can safely rsync/ship them.
function post_create_rootfs_archive__900_netboot_deploy() {
	[[ "${ROOTFS_TYPE}" == "nfs-root" ]] || return 0
	_netboot_compute_runtime_defaults

	# shellcheck disable=SC2034 # exposed as netboot_artifacts_ready hook context
	declare -g NETBOOT_ROOTFS_ARCHIVE="${ROOTFS_ARCHIVE_PATH:-}"

	call_extension_method "netboot_artifacts_ready" <<- 'NETBOOT_HOOK_DOC'
		*called after netboot TFTP tree and rootfs are staged*
		Implementations can rsync ${NETBOOT_TFTP_OUT} to a TFTP server, extract
		${NETBOOT_ROOTFS_ARCHIVE} into ${NETBOOT_NFS_PATH} on an NFS server, etc.
		When the build host IS the NFS server, prefer ROOTFS_EXPORT_DIR (skips
		the archive step and writes straight into the export path).
		Exposed context: NETBOOT_TFTP_OUT, NETBOOT_TFTP_PREFIX, NETBOOT_PXE_FILE,
		NETBOOT_NFS_PATH, NETBOOT_ROOTFS_ARCHIVE (may be empty), NETBOOT_HOSTNAME,
		NETBOOT_CLIENT_MAC, plus BOARD, LINUXFAMILY, BRANCH, RELEASE.
	NETBOOT_HOOK_DOC
}
