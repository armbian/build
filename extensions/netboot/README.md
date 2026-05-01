# Armbian `netboot` extension

Produces a full network-boot payload for a single-board computer: kernel
image, DTB, optional initrd, PXE/extlinux config, and an NFS-exportable
rootfs. After first boot the **kernel/DTB/rootfs all live on the network**
— U-Boot fetches kernel+DTB over TFTP, then mounts root over NFS, no
local SD/eMMC content needed for those. Local storage is still required
for the **bootloader itself**: U-Boot (or SPL+U-Boot) must already be
flashed to the board's boot media (eMMC, SPI flash, dedicated SD, or
factory ROM-loaded), and that bootloader must be configured to attempt
PXE before any local boot target. The operator provisions the bootloader
once; everything past it is network.

For the short overview + variable reference see the companion page in
[armbian-doc](https://github.com/armbian/documentation) (`Developer-Guide_Netboot.md`).
This README holds the long-form guide: upstream constraints, server
setup, network configuration, troubleshooting, end-to-end examples.

## Table of contents

- [Why this exists (hybrid-NFS vs full netboot)](#why-this-exists)
- [Build-time variables](#build-time-variables)
- [Build artifacts matrix](#build-artifacts-matrix)
- [Upstream constraint: U-Boot does not support proxyDHCP](#upstream-constraint-u-boot-does-not-support-proxydhcp)
- [Server side: TFTP + NFS](#server-side-tftp--nfs)
- [Network side: DHCP options 66/67](#network-side-dhcp-options-6667)
- [Builder-as-NFS-server single-step workflow](#builder-as-nfs-server-single-step-workflow)
- [Multi-board / multi-host deployments](#multi-board--multi-host-deployments)
- [First boot and `armbian-firstrun`](#first-boot-and-armbian-firstrun)
- [End-to-end example: helios64](#end-to-end-example-helios64)
- [Troubleshooting](#troubleshooting)

## Why this exists

`ROOTFS_TYPE=nfs` alone produces a hybrid image: kernel and DTB still
live on a local boot partition (SD/eMMC), only `/` comes over NFS.
`ROOTFS_TYPE=nfs-root` takes it further — kernel, DTB and PXE config
are also staged for TFTP, and on every reboot the only thing the target
needs is a network with working DHCP+TFTP+NFS, **plus a PXE-capable
U-Boot already living on its boot media** (eMMC/SPI/dedicated SD).
Provisioning that bootloader is a one-time operator task, outside this
extension's scope; once it's there and configured to try PXE first,
the rest is network. Selecting `nfs-root` is the single switch that
turns this extension on; it is auto-enabled from the core `ROOTFS_TYPE`
dispatch, no separate `ENABLE_EXTENSIONS` flag is needed.

Use cases:

- Read-only / tamper-evident workstations and kiosks.
- SBC clusters where one machine owns the storage and N workers pull
  their rootfs over NFS.
- Development loops where `edit → build → reboot target` should not
  involve flashing or SD-card swaps.
- Boards with damaged or missing eMMC/SD but a working Ethernet PHY.

Local storage (NVMe, USB, swap partition, data disks) can still be
mounted at runtime — the extension only arranges for the *early* boot
to come over the wire.

## Build-time variables

All variables are optional. The only required step is
`ROOTFS_TYPE=nfs-root`; defaults give you a single shared rootfs
per `BOARD × BRANCH × RELEASE` and a tagged
`pxelinux.cfg/<board>-<branch>-<release>.example` file. The tag
matches the kernel/rootfs paths so building several variants for
one board doesn't overwrite each other; the operator picks the
active one by symlinking it to `default-<arch>-<board>` (or
`01-<mac>`) under `pxelinux.cfg/`.

| Variable | Default | Purpose |
|---|---|---|
| `NETBOOT_SERVER` | _(empty)_ | IP of the NFS server baked into `nfsroot=`. When empty, the extension writes `nfsroot=<path>,tcp,v3` (path-only, no server) into APPEND; the kernel resolves the NFS server from DHCP `siaddr` (the boot-server field in the DHCP offer, set via `dhcp-boot` in dnsmasq). The same image then boots against any server the router announces as boot-server without any per-image configuration. Set this when you'd rather hard-code a single server in the PXE config. extlinux does not expand `${serverip}` in APPEND, so a literal placeholder is not an option. |
| `NETBOOT_TFTP_PREFIX` | `armbian/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}<flavor>` | Path prefix inside TFTP root. One board can share one TFTP root with many other boards because each lives under its own prefix. `<flavor>` is `-min` when `BUILD_MINIMAL=yes`, `-desktop` when `BUILD_DESKTOP=yes`, otherwise empty — so CLI / minimal / desktop builds for the same board+branch+release coexist side by side. |
| `NETBOOT_NFS_PATH` | see below | Absolute NFS path of the rootfs on the server. The APPEND line uses exactly this string for `nfsroot=...`. |
| `NETBOOT_HOSTNAME` | _(empty)_ | Per-host deployment. When set, the default `NETBOOT_NFS_PATH` becomes `/srv/netboot/rootfs/hosts/<hostname>` — each machine owns its own writable rootfs copy. When empty, the default is `/srv/netboot/rootfs/shared/${LINUXFAMILY}/${BOARD}/${BRANCH}-${RELEASE}<flavor>` (one image, potentially reused by identical boards). The `<flavor>` rule is the same as for `NETBOOT_TFTP_PREFIX` (`-min` / `-desktop` / empty). |
| `NETBOOT_CLIENT_MAC` | _(empty)_ | Client MAC. The user value accepts either separator and any case (e.g. `aa:BB:cc:DD:ee:FF` or `AA-bb-CC-dd-EE-ff`); the extension normalises it to **lowercase, dash-separated** for filename use — so MAC `aa:BB:cc:DD:ee:FF` becomes `aa-bb-cc-dd-ee-ff`. The build then writes `pxelinux.cfg/01-aa-bb-cc-dd-ee-ff.<board>-<branch>-<release>[-<hostname>]` (tagged file, not a name U-Boot looks up). To activate, symlink it under the U-Boot lookup name `01-aa-bb-cc-dd-ee-ff` (lowercase + dashes — that's exactly what U-Boot's PXELINUX per-MAC fallback resolution requests). The exact generated filename is also exposed via `NETBOOT_PXE_FILE` for `netboot_artifacts_ready` hooks. |
| `ROOTFS_COMPRESSION` | `zstd` | Format of the rootfs archive produced by `create_image_from_sdcard_rootfs`. `zstd` (alias `zst`) → `.tar.zst`, `gzip` → `.tar.gz`, `none` → no archive at all. The `none` case requires `ROOTFS_EXPORT_DIR`. |
| `ROOTFS_EXPORT_DIR` | _(empty)_ | rsync target for the rootfs tree. **Relative** value (e.g. `shared/rockchip64/helios64/edge-trixie`) is confined under `${SRC}/output/netboot-export/<value>` so `rsync --delete` cannot escape that subtree. **Absolute path outside the build tree** (e.g. `/srv/netboot/rootfs/shared/<board>/<branch>-<release>` or `/nfsroot`) is kept as-is and bind-mounted into the container at the same path; rsync writes straight into the host export tree. The directory must exist on the host before the build (typically `sudo mkdir -p` for root-owned NFS roots). Primary use: builder host is also the NFS server — single-step `build → boot` loop, no tar/unpack/rsync hop. System roots (`/`, `/etc`, `/usr`, ...) and `..` segments are rejected. The build stamps a `.netboot_export_marker` at the root of every export tree it writes; a non-empty target without that marker is refused (so `rsync --delete` cannot wipe an unrelated Linux tree at the same path) unless `NETBOOT_EXPORT_FORCE=yes`. |
| `NETBOOT_EXPORT_FORCE` | `no` | Set to `yes` to allow overwriting a non-empty `ROOTFS_EXPORT_DIR` that does not carry the `.netboot_export_marker` stamp (rsync `--delete` will clobber whatever is there). |

### Hook: `netboot_artifacts_ready`

Called from `post_create_rootfs_archive__900_netboot_deploy`, after
the TFTP tree and rootfs archive/export are staged. Exposed context:

| Variable | Meaning |
|---|---|
| `NETBOOT_TFTP_OUT` | Absolute path of the staging directory (`${FINALDEST}/<version>-netboot-tftp`; by default `FINALDEST=output/images`). |
| `NETBOOT_TFTP_PREFIX` | As above. |
| `NETBOOT_NFS_PATH` | As above. |
| `NETBOOT_PXE_FILE` | The tagged file written under `pxelinux.cfg/`: `<board>-<branch>-<release>[-<hostname>].example` or `01-<mac>.<board>-<branch>-<release>[-<hostname>]`. The operator symlinks one of these to the name U-Boot actually looks for (`default-<arch>-<board>`, `default`, or `01-<mac>`). |
| `NETBOOT_ROOTFS_ARCHIVE` | Full path to the produced rootfs archive (empty when `ROOTFS_COMPRESSION=none`). |
| `NETBOOT_HOSTNAME` | Passed through verbatim — no sanitization. Hook code that embeds it in a shell command or a path must quote/escape itself. |
| `NETBOOT_CLIENT_MAC` | The raw user value (`aa:bb:cc:dd:ee:ff` or `aa-bb-cc-dd-ee-ff`). Normalise yourself if you need a specific form. |
| `BOARD`, `LINUXFAMILY`, `BRANCH`, `RELEASE` | Standard build variables. |

Implement this hook in `userpatches/extensions/` to rsync the TFTP
tree to a netboot server, unpack the rootfs archive into the export
path, notify a monitoring system, etc. When the build host is the
NFS server, prefer `ROOTFS_EXPORT_DIR` — the hook then only needs to
handle the TFTP side.

### Reference implementation: `netboot-deploy.sh`

`extensions/netboot/netboot-deploy.sh` ships a worked example of this
hook: it rsyncs the TFTP tree to a remote server over SSH and untars
the rootfs archive into the NFS export. It is **not loaded
automatically** — opt in by adding `netboot-deploy` to the extension
list; it pulls in `netboot` itself:

```sh
DOCKER_PASS_SSH_AGENT=yes \
./compile.sh build BOARD=helios64 BRANCH=edge RELEASE=resolute \
    BUILD_MINIMAL=yes ROOTFS_TYPE=nfs-root NETBOOT_SERVER=192.168.1.10 \
    ENABLE_EXTENSIONS=netboot-deploy \
    NETBOOT_DEPLOY_SSH=root@netboot.local
```

For Docker builds (the default), the SSH client inside the container
needs credentials. Pick one of two paths depending on the workflow:

- **Interactive use — agent forwarding.** Add `DOCKER_PASS_SSH_AGENT=yes`
  (as above). The host `ssh-agent` socket is forwarded into the
  container; the agent must be live and the socket reachable by the
  container user.

- **Batch / CI — bind-mount a key file.** Set
  `NETBOOT_DEPLOY_SSH_KEY=/path/to/key`. The hook mounts the file
  read-only and re-copies it to a root-owned scratch path inside the
  container so OpenSSH accepts it. No agent required.

Without one of those, the `ssh`/`rsync` calls fall back to password
auth and fail under `BatchMode=yes`.

Configuration variables (see the file header for details):

| Variable | Meaning |
|---|---|
| `NETBOOT_DEPLOY_SSH` | SSH target for the netboot server (required). |
| `NETBOOT_DEPLOY_TFTP_ROOT` | TFTP root on the server. Default: `/srv/netboot/tftp`. |
| `NETBOOT_DEPLOY_TFTP_DELETE` | `yes` (default) enables `rsync --delete` on TFTP; set `no` when the TFTP root is shared with unrelated deployments. |
| `NETBOOT_DEPLOY_EXCLUDE_FILE` | Optional `rsync --exclude-from` file applied to the TFTP sync. |
| `NETBOOT_DEPLOY_SUDO` | `yes` runs the remote `rsync`, `mkdir`, and `tar` under `sudo -n`. Default: `no`. Required when the SSH account cannot write to `NETBOOT_DEPLOY_TFTP_ROOT` or `NETBOOT_NFS_PATH` directly. Needs passwordless sudo on the server. |
| `NETBOOT_DEPLOY_SSH_KEY` | Path to a private key file. The hook bind-mounts the file read-only at the same path inside the container, copies it to a root-owned scratch path before use (OpenSSH refuses identity files whose owner is neither root nor the current user), and adds `-i <scratch>` to the ssh command. Use for batch/CI runs without a live ssh-agent. |
| `NETBOOT_DEPLOY_SSH_KNOWN_HOSTS` | Path to a `known_hosts` file on the build host. The hook bind-mounts it into the container at `/root/.ssh/known_hosts:ro`. Default: auto-pickup of `${HOME}/.ssh/known_hosts` if it exists. See "SSH host identity" below for how this composes with the other knobs. |
| `NETBOOT_DEPLOY_SSH_TOFU` | `yes` switches ssh to ephemeral trust-on-first-use: `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new` — each connection learns the host key fresh, persists nothing. For trusted-segment use only. Default: `no`. Mutually exclusive with `NETBOOT_DEPLOY_SSH_KNOWN_HOSTS` (and the `${HOME}/.ssh/known_hosts` auto-pickup). |
| `NETBOOT_DEPLOY_SSH_OPTS` | Extra ssh options applied to both `ssh` and `rsync`. Default: `-o BatchMode=yes`. Strict by design (fails fast on unknown auth and on unknown/changed host keys). Use the dedicated `NETBOOT_DEPLOY_SSH_KNOWN_HOSTS` / `NETBOOT_DEPLOY_SSH_TOFU` for host-identity control; this variable is for arbitrary other tweaks (`ConnectTimeout`, `ProxyCommand`, etc.). |
| `NETBOOT_DEPLOY_PROBE` | `yes` (default) probes the deploy target during host-phase config (ssh + optional sudo + `touch`+`rm` under `NETBOOT_DEPLOY_TFTP_ROOT`). Surfaces missing keys, password-locked sudo, or a read-only/non-existent TFTP root in seconds, before the kernel build. Set `no` to bypass when the probe itself becomes the obstacle (jumphosts, custom `ProxyCommand`, targets that allow rsync via a wrapper but disallow plain `touch`). |

#### SSH host identity

The deploy hook needs to know the SSH host key of the deploy target before
it will ssh/rsync into it. Default behaviour is **strict**: an unknown or
changed host key fails the build instead of silently being trusted. Pick
one of three sources for the key:

| Scenario | What to set | What happens |
|---|---|---|
| **Interactive (your laptop)** | _(nothing — auto)_ | If `${HOME}/.ssh/known_hosts` exists on the build host, it is bind-mounted into docker read-only at `/root/.ssh/known_hosts`. SSH'd to the target manually once → the build inherits that trust. |
| **CI / containers without `${HOME}/.ssh`** | `NETBOOT_DEPLOY_SSH_KNOWN_HOSTS=/path/to/known_hosts` | The given file is bind-mounted into docker. Pre-populate it via `ssh-keyscan -H target >> /path/to/known_hosts` in a CI step (or as a pipeline secret). Survives the build cleanly. |
| **Home lab — trusted segment** | `NETBOOT_DEPLOY_SSH_TOFU=yes` | Adds `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new`. Each connection learns the host key fresh, persists nothing — no setup, no MITM protection. |

`NETBOOT_DEPLOY_SSH_TOFU=yes` is mutually exclusive with the
`NETBOOT_DEPLOY_SSH_KNOWN_HOSTS` mount (and with the auto-pickup
`${HOME}/.ssh/known_hosts`); the build refuses to ambiguate which source
of trust applies. If the auto-pickup gets in the way for a quick TOFU
test, unset it explicitly: `NETBOOT_DEPLOY_SSH_KNOWN_HOSTS=/dev/null`
plus `NETBOOT_DEPLOY_SSH_TOFU=yes` is rejected — move/rename your
`${HOME}/.ssh/known_hosts` instead, or just commit to one mode.

The rootfs archive is untarred into `NETBOOT_NFS_PATH` without wiping
existing content — per-host state (ssh host keys, machine-id,
`/home`) survives rebuilds, but files removed from the source
accumulate. For a clean slate, empty `NETBOOT_NFS_PATH` on the
server between deploys. When `ROOTFS_COMPRESSION=none` is combined
with `ROOTFS_EXPORT_DIR` (builder-as-NFS-server), the archive step
is skipped — only TFTP is deployed.

#### Kernel-only deploy

A narrow optimization for **boards whose boot networking driver is built
into the kernel** (e.g. helios64 mvneta, helios4 mvneta — anything where
`root=/dev/nfs ip=dhcp` works without an initramfs). On such boards a
fresh kernel can be deployed without rebuilding the rootfs or initramfs
at all, which turns a 15-minute full image rebuild into a 10-second
incremental refresh — useful for kernel debugging and config iteration.

Triggered by `compile.sh kernel ...`:

```bash
./compile.sh iav kernel \
    BOARD=helios64 BRANCH=edge \
    ENABLE_EXTENSIONS=netboot,netboot-deploy \
    NETBOOT_DEPLOY_SSH=root@m1
```

The `artifact_ready` handler unpacks the produced
`linux-image-${BRANCH}-${LINUXFAMILY}_*.deb`, rsyncs `vmlinuz` and dtbs
into `${NETBOOT_DEPLOY_TFTP_ROOT}/${NETBOOT_TFTP_PREFIX}/`, syncs
`/lib/modules/${kver}/` (with `--delete`) into the NFS rootfs at
`${NETBOOT_NFS_PATH}/lib/modules/${kver}/`, and **removes any
pre-existing `uInitrd`** from the TFTP prefix.

This closes a coherence gap that otherwise produces `BPF: Invalid
name_offset:N` and `failed to validate module BTF: -22` spam on boot:
split-BTF references in `.ko` modules point to the BTF inside the
running vmlinux; if the kernel image and the modules in `/lib/modules/`
come from different build runs, every match resolves to a wrong string
offset. Coherent kernel + modules deployed together fix it.

**Initramfs is intentionally not regenerated, by design.** Initramfs
content depends on the *configured* rootfs — `customize_image` hooks,
`/etc/initramfs-tools/*` tweaks, board-specific extensions, userpatches
overlay — and that context only exists during a full image build. Past
that build, the configured rootfs lives only on the NFS server, which
may be an OpenWRT box or anything else that cannot run
chroot+update-initramfs. Regenerating from a generic post-debootstrap
rootfs cache would produce a *different* initramfs than the one a full
image build would have made — wrong, not just incomplete.

So the kernel-only deploy drops the previous build's `uInitrd` and lets
the kernel boot without an initramfs:

- **Boards with built-in boot networking**: `root=/dev/nfs ip=dhcp` runs
  directly from kernel — clean boot, every time. Modules under
  `/lib/modules/${kver}/` get loaded later for non-boot-critical drivers
  (WiFi, BT, etc.).
- **Boards needing modular drivers in initramfs** (USB-eth, modular NIC,
  modular SATA, etc.): kernel will fail fast at networking instead of
  silently corrupting later. The fix for those boards is **not** a kernel
  refresh — it is a full image rebuild
  (`compile.sh build ROOTFS_TYPE=nfs-root ...`), which produces a fresh
  initramfs alongside the kernel.

Use the kernel-only path when you know your board falls in the first
category. If unsure, the full image rebuild is always the safe choice.

## Build artifacts matrix

What ends up under `output/images/` for a given combination of
`ROOTFS_TYPE` × `ROOTFS_COMPRESSION` × `ROOTFS_EXPORT_DIR`. Vanilla armbian
behaviour is shown first; the netboot extension only **adds** a TFTP tree
to the picture, it does not replace any of the rootfs/archive outputs.

| `ROOTFS_TYPE` | `ROOTFS_COMPRESSION` | `ROOTFS_EXPORT_DIR` | Produced under `output/images/` |
|---|---|---|---|
| `ext4`/`btrfs`/`f2fs`/`xfs`/`nilfs2` | (n/a) | (n/a) | `<ver>.img[.xz/zst/zip]` + `.txt` + `.sha` (flashable image) |
| `nfs` / `nfs-root` | `none` | _empty_ | **build fails** — `ROOTFS_COMPRESSION=none requires ROOTFS_EXPORT_DIR` (no archive, no rsync target — nothing produced) |
| `nfs` / `nfs-root` | `none` | _set_ | rsync into `${ROOTFS_EXPORT_DIR}/` only (no `<ver>-rootfs.tar.*` archive) |
| `nfs` / `nfs-root` | `zstd`/`zst` (default) | _empty_ | `<ver>-rootfs.tar.zst` archive only |
| `nfs` / `nfs-root` | `zstd`/`zst` | _set_ | `<ver>-rootfs.tar.zst` archive **and** rsync into `${ROOTFS_EXPORT_DIR}/` (both produced) |
| `nfs` / `nfs-root` | `gzip` | _empty_ | `<ver>-rootfs.tar.gz` archive only |
| `nfs` / `nfs-root` | `gzip` | _set_ | `<ver>-rootfs.tar.gz` archive **and** rsync into `${ROOTFS_EXPORT_DIR}/` |

**With this extension loaded**, every `ROOTFS_TYPE=nfs-root` build (auto-enabled
by setting `ROOTFS_TYPE=nfs-root`) **additionally** writes a TFTP tree under
`<ver>-netboot-tftp/` next to whatever rootfs output the row above produces:

```text
<ver>-netboot-tftp/
  pxelinux.cfg/
    <board>-<branch>-<release>[-<hostname>].example       # tagged file (or 01-<mac>.<...> with NETBOOT_CLIENT_MAC)
  <NETBOOT_TFTP_PREFIX>/                                  # default: armbian/<family>/<board>/<branch>-<release>/
    Image                                                 # or zImage on armhf
    dtb/<...>/*.dtb
    uInitrd                                               # only if /boot/uInitrd was produced
```

The TFTP tree is independent of `ROOTFS_COMPRESSION`/`ROOTFS_EXPORT_DIR` — it is
always staged, so even an archive-only build yields a complete TFTP payload that
can be deployed separately (for example via a `netboot_artifacts_ready` hook).

## Upstream constraint: U-Boot does not support proxyDHCP

This is the single most important fact behind the server-side design.
Any tutorial that tells you to set up a "PXE proxy server" next to
your existing router DHCP will not work with U-Boot — it works with
BIOS/UEFI PXE ROMs but not with Das U-Boot's `bootp.c`.

What the U-Boot source (`net/bootp.c`, current master) actually does:

- Sends `vendor-class-identifier = U-Boot.armv8` (or `.armv7`). It
  does **not** send `PXEClient`, so a proxyDHCP server that filters
  on vendor class (the standard case for dnsmasq `dhcp-range=...,proxy`)
  will not answer at all.
- Parses the **first** `DHCPOFFER` it sees. The state machine
  immediately transitions `SELECTING → REQUESTING`:
  ```c
  dhcp_state = REQUESTING;
  dhcp_send_request_packet(bp);
  ```
  A second OFFER from a separate PXE server arriving moments later is
  silently discarded.
- Takes `server-ip` (`siaddr`) from that first OFFER only:
  `net_server_ip = ntohl(bp->bp_siaddr)`. If the router answered
  first with `siaddr = router_ip`, U-Boot will TFTP from the router.
- Never talks to UDP/4011 (Boot Server Discovery), which is the
  second phase of the PXE spec that a proxyDHCP flow depends on.

**Consequence:** any scheme where the router hands out IPs and a
separate server is supposed to add PXE options is architecturally
incompatible with U-Boot without patching the client. The PXE
information (`siaddr`, `bootfile`) must come from the **same** DHCP
server that hands out the IP.

Two supported workarounds:

1. **Put DHCP options 66/67 on the main network DHCP server** (usually
   the router). Works unmodified with upstream U-Boot. Documented
   below. _This is the path the extension is designed around._
2. Persist `serverip` in U-Boot environment via `env set serverip …;
   env save`. This is per-board, brittle (`env` offset can be wiped
   by an image flash), and not something the Armbian build can do for
   you — but it's there if you absolutely cannot touch your DHCP.

## Server side: TFTP + NFS

The minimal production setup is `tftpd-hpa` + `nfs-kernel-server` on
one Linux host. **No DHCP runs on the server.** DHCP lives on the
network router (see next section).

> **GNU tar required on the deploy target.** When the deploy hook
> ships a rootfs archive over SSH, it extracts with
> `tar -xp --xattrs --xattrs-include='*' --acls --selinux`. Busybox tar
> (Alpine, OpenWRT) silently drops xattrs on extract — `security.capability`
> for binaries like `ping`/`mtr` is lost and they fail at runtime
> regardless of host filesystem support. The `--acls`/`--selinux` flags
> are also unrecognized on Busybox. Use a regular Linux distribution
> with GNU tar on the NFS server.

Directory layout:

```text
/srv/netboot/
  tftp/                                      # TFTP root (= TFTP_DIRECTORY)
    pxelinux.cfg/
      <board>-<branch>-<release>.example     # tagged file the build writes; not
                                             # a name U-Boot looks up — must be
                                             # promoted via mv/ln to activate
      default                                # one of the names U-Boot does look up;
                                             # typically a symlink to a .example file
      default-arm-rk3399-helios64            # board-specific fallback (same idea)
      01-aa-bb-cc-dd-ee-ff.<board>-...       # per-MAC tagged variant
      01-aa-bb-cc-dd-ee-ff                   # per-MAC lookup name (symlink to ↑)
    armbian/
      <family>/<board>/<branch>-<release>/
        Image
        uInitrd                              # optional
        dtb/
          rockchip/rk3399-kobol-helios64.dtb
          rockchip/overlay/*.dtbo
  rootfs/
    shared/<family>/<board>/<branch>-<release>/
      etc/ bin/ usr/ ...
    hosts/<hostname>/
      etc/ bin/ usr/ ...
```

### `/etc/default/tftpd-hpa`

```sh
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/netboot/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --ipv4"
```

`--secure` chroots the daemon into `TFTP_DIRECTORY`; `--ipv4` avoids
IPv6 bind conflicts on dual-stack hosts.

### `/etc/exports`

```text
# Replace 192.168.1.0/24 with your own LAN subnet or an explicit
# hostname. Never export netboot rootfs to * — anyone who can reach
# the NFS port gets root-equivalent write access.
/srv/netboot/rootfs          192.168.1.0/24(ro,sync,no_subtree_check,no_root_squash,crossmnt,fsid=0)
/srv/netboot/rootfs/shared   192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/netboot/rootfs/hosts    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

`no_root_squash` is required so the NFS client can write files owned
by UID 0 — which is why the export MUST be restricted to a trusted
subnet or explicit hosts. `crossmnt`/`fsid=0` makes the top-level a
pseudo-root so clients can mount `shared/...` and `hosts/...` paths
directly without needing the top export.

### systemd

```sh
systemctl enable --now tftpd-hpa nfs-kernel-server
exportfs -ra
```

Firewall: UDP/69 (TFTP), TCP/2049 (NFS), plus whatever `rpc.mountd`
and `rpc.statd` bind to if you're using NFSv3 — pin them via
`/etc/default/nfs-kernel-server` and `/etc/default/nfs-common` for a
predictable firewall rule.

## Network side: DHCP options 66/67

This is the only section that changes on the *network* side — the
main DHCP server (usually a router) needs to announce two options for
PXE clients:

- **Option 66** (`tftp-server-name`) — IP or hostname of the TFTP
  server. This ends up as `siaddr`/`serverip` in U-Boot.
- **Option 67** (`bootfile-name`) — the filename U-Boot asks for first
  via `pxe get`. This must be **`default`**, not `pxelinux.cfg/default`
  (see gotcha below).

### OpenWRT (UCI / dnsmasq as DHCP)

```sh
uci set dhcp.@dnsmasq[0].dhcp_boot='default,<tftp-hostname>,<tftp-ip>'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

Example for a server reachable as `m1` / `192.168.1.125`:

```sh
uci set dhcp.@dnsmasq[0].dhcp_boot='default,m1,192.168.1.125'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

The three fields are `bootfile,servername,siaddr`. `servername` is
informational (populates the `sname` DHCP field); `siaddr` is what
U-Boot actually uses.

**LuCI has no UI for `dhcp_boot`.** The "DHCP-Options" field in
*Network → DHCP and DNS → Advanced Settings* is a different mechanism
(`list dhcp_option`) and cannot express option 66/67 cleanly. The only
way to see / change `dhcp_boot` is via UCI/SSH or by reading
`/etc/config/dhcp` directly.

### NFS server resolution for an empty `NETBOOT_SERVER`

Options 66/67 above only handle the **TFTP** stage. The kernel still
needs to know which NFS server to mount as `/`. Two ways:

1. **Bake it into the image**: set `NETBOOT_SERVER=<ip>` at build time;
   the extension writes a fixed `nfsroot=<server>:<path>,tcp,v3` into
   the PXE config. The router only needs options 66/67.
2. **Use DHCP `siaddr`** (the default when `NETBOOT_SERVER` is empty):
   the extension writes `nfsroot=<path>,tcp,v3` (no server) into APPEND.
   At boot the kernel's IP-Config resolves the NFS server from the
   `siaddr` field of the DHCP offer (the boot-server field). Set this on
   the router via `dhcp-boot` / `next-server` in dnsmasq:

```sh
# OpenWRT / dnsmasq via UCI — set siaddr to the NFS server
uci set dhcp.@dnsmasq[0].dhcp_boot='default,nfsserver,192.168.1.x'
uci commit dhcp && /etc/init.d/dnsmasq restart

# dnsmasq standalone
dhcp-boot=default,nfsserver,192.168.1.x
```

The extension installs a dhcpcd hook (`71-netboot-rootpath`) in the
initramfs that reads the boot server from `/proc/net/pnp` (written by
the kernel IP-Config) and appends it as `ROOTSERVER` to
`/run/net-${interface}.conf`, overriding the default gateway value that
`70-net-conf` writes there. If `/proc/net/pnp` is absent or has no
valid `bootserver` entry the hook clears `ROOTSERVER` explicitly and
logs a warning, so the failure is immediate and visible.

### The `bootfile=default` gotcha

Set the bootfile to `default`, **not** `pxelinux.cfg/default`. U-Boot's
`pxe get` treats the bootfile path as a *directory*, extracts the
directory component as `bootdir`, and then its internal
`get_pxelinux_path()` prefixes `pxelinux.cfg/` again. So:

- bootfile = `default` → bootdir = `""` → requests become
  `pxelinux.cfg/01-<mac>`, `pxelinux.cfg/<hex-ip>`, `pxelinux.cfg/default`
  — correct paths, `tftpd-hpa` finds them.
- bootfile = `pxelinux.cfg/default` → bootdir = `pxelinux.cfg/` →
  requests become `pxelinux.cfg/pxelinux.cfg/01-<mac>`, and so on —
  doubled prefix, `tftpd-hpa` returns file-not-found for everything.

### Other DHCP servers

The same two options translate directly:

- **isc-dhcp-server**: `next-server <ip>; filename "default";` inside
  the relevant subnet or host stanza.
- **dnsmasq standalone**: `dhcp-boot=default,<hostname>,<ip>` in
  `dnsmasq.conf`.
- **Mikrotik/RouterOS**: `/ip dhcp-server network set [find] boot-file-name=default next-server=<ip>`.
- **EdgeOS / VyOS**: `set service dhcp-server shared-network-name <N>
  subnet <cidr> bootfile-name default` and
  `bootfile-server <ip>`.
- **Windows DHCP Server**: Scope Options → 066 (Boot Server Host Name)
  + 067 (Bootfile Name), value `default`.

## Builder-as-NFS-server single-step workflow

When the machine building the image is also the NFS server for the
target, you can skip the archive entirely: build straight into the
export directory.

Point `ROOTFS_EXPORT_DIR` straight at the NFS export tree. Any
absolute path outside the build tree works; the extension bind-mounts
it into the container at the same absolute path. The in-container
rsync (running as docker-root, no userns-remap) writes files with
their original ownership preserved — exactly what NFS-mounted root
filesystems need. The export step is a plain `rsync`; it copies
file-by-file, so on a multi-GiB rootfs expect minutes (cache and
incremental updates make repeat builds much faster).

Alternative for sites that prefer keeping export paths inside the
build tree: symlink `output/netboot-export` to the NFS root once and
use a relative `ROOTFS_EXPORT_DIR=shared/...`. The symlink does not
survive `rm -rf output/` and similar cleanups, so the absolute-path
form is the safer default for unattended workflows.

```sh
# One-time, only if you go the symlink route. Run from the Armbian
# checkout root, or replace `$PWD` with the absolute checkout path.
ln -s /srv/netboot/rootfs "$PWD/output/netboot-export"
```

Without either approach everything still works — the artefacts just
sit under `output/netboot-export/` inside the checkout and you rsync
them out later (which downgrades ownership and copies bytes).

```sh
./compile.sh build \
  BOARD=helios64 BRANCH=edge RELEASE=trixie \
  BUILD_MINIMAL=yes \
  ROOTFS_TYPE=nfs-root \
  NETBOOT_SERVER=192.168.1.125 \
  NETBOOT_HOSTNAME=helios64-a \
  NETBOOT_CLIENT_MAC=aa:bb:cc:dd:ee:ff \
  ROOTFS_COMPRESSION=none \
  ROOTFS_EXPORT_DIR=hosts/helios64-a
```

What happens:

- `ROOTFS_COMPRESSION=none` skips the tar/gzip step. No `*.tar.gz`
  appears under `output/images/`.
- `ROOTFS_EXPORT_DIR=hosts/helios64-a` expands to
  `${SRC}/output/netboot-export/hosts/helios64-a` on the host side;
  rsync (`-aHWh -AXS --numeric-ids`, falling back to bare
  `--numeric-ids` only on nilfs2 which has no xattr support) populates
  it from the chroot, preserving permissions, hardlinks, ACLs (`-A`),
  xattrs incl. file capabilities (`-X`), sparse holes (`-S`) and
  numeric ownership.
- In Docker builds `ROOTFS_EXPORT_DIR` resolves under
  `${SRC}/output/netboot-export/...` (inside the container `${SRC}`
  expands to `/armbian`, so the same path works on both sides). When
  `output/netboot-export` is a symlink to an external root (e.g.
  `/srv/netboot/rootfs` on a builder-as-NFS-server), the extension
  bind-mounts that target into the container at its **original
  absolute path** so the symlink resolves identically inside and out.
  Native builds work the same — just no docker hop.
- `pre_umount_final_image__900_collect_netboot_artifacts` still
  produces the TFTP tree at
  `${FINALDEST}/<version>-netboot-tftp/armbian/<family>/<board>/<branch>-<release>/`
  (by default under `output/images/`) — you rsync that into your TFTP
  root as usual.

Requirements:

- The export directory must be writable by the build process (root in
  most setups — `compile.sh` escalates via sudo).
- Disk budget: roughly 1.5 GB per `BUILD_MINIMAL` rootfs, more for
  desktop images. Multiply by the number of `hosts/<hostname>`
  directories.
- `ROOTFS_COMPRESSION=none` without `ROOTFS_EXPORT_DIR` is rejected
  early (in `extension_prepare_config`) — otherwise nothing would be
  produced at all.

When this workflow does **not** fit:

- Builder and NFS server are different machines with no shared mount.
  Use `ROOTFS_COMPRESSION=gzip|zstd` and rsync/ssh the archive via a
  `netboot_artifacts_ready` hook (or by hand).
- Two parallel builds targeting the same `ROOTFS_EXPORT_DIR` — rsync
  will clobber each other. Use distinct directories (a per-host
  layout already gives you that).

## Multi-board / multi-host deployments

Armbian does not have a universal image. The smallest unit is
`BOARD × BRANCH × RELEASE`, and even among boards in the same SoC
family the BSP (`armbian-bsp-cli-*`) is per-board. Plan sharing
accordingly:

| Share | x86 ↔ arm64 | rockchip64 ↔ meson64 | helios64 ↔ rock5b |
|---|---|---|---|
| Kernel image | impossible (different arch) | different kernel packages | different kernels |
| DTB | x86 doesn't use DTBs | different DTB trees | different DTBs |
| rootfs binaries | impossible | technically compatible | technically compatible |
| `armbian-bsp-cli-*` | per-board | per-board | per-board |

Practically, the maximum rootfs sharing is **N physical boards of
identical model**, and even that has caveats (see "identical boards"
below).

Supported patterns:

1. **One board, one image.** Default: `shared/<family>/<board>/<branch>-<release>/`,
   `pxelinux.cfg/default` points at it.
2. **N different boards (different models).** Each in its own
   `shared/<family>/<board>/...`; each board's U-Boot requests
   `01-<mac>` first, so per-MAC PXE configs are the routing mechanism.
   Build each with a different `NETBOOT_CLIENT_MAC`.
3. **N identical boards, per-host rootfs.** `NETBOOT_HOSTNAME=<name>`
   → rootfs lives at `hosts/<name>/`. Each board gets its own copy;
   there are no shared-write conflicts (`/var/log`, `/etc/machine-id`,
   `/etc/ssh/ssh_host_*_key`, etc.). Build once per host, deploy each
   to its own directory.
4. **N identical boards, one rootfs (advanced).** Technically possible
   with a read-only rootfs + tmpfs/overlay over the writable paths,
   but the Armbian build itself does not set this up for you — the
   produced rootfs assumes single-host ownership. If you need this,
   layer a `userpatches/customize-image.sh` that moves `/var`, `/etc`
   and `/home` onto tmpfs/overlay mounts in `/etc/fstab`, and use
   `ro` instead of `rw` in the NFS export + APPEND.

Explicit non-goals:

- One rootfs shared between architectures (x86 + arm64).
- One rootfs shared between SoC families (rockchip64 + meson64 would
  conflict on the BSP and often on kernel ABI).
- "Generic Linux netboot" — that's the job of Debian/Ubuntu
  netinstall images, not Armbian.

## First boot and `armbian-firstrun`

Armbian has two "first boot" mechanisms that matter for netboot. They
are often confused:

| Name | Unit / script | What it does | Netboot treatment |
|---|---|---|---|
| `armbian-firstrun.service` | systemd | Regenerates SSH host keys, calls helper scripts. Non-interactive. | **Kept.** Harmless on NFS root. |
| `armbian-firstlogin` (wizard) | `/etc/profile.d/armbian-check-first-login.sh` on first shell login | Runs the whiptail wizard: root password → create user → timezone → locale. **Interactive unless the trigger file holds `PRESET_*` values for `preset-firstrun`.** | **Conditionally suppressed.** The extension removes `/root/.not_logged_in_yet` during `post_customize_image` **only when it is empty**. A non-empty trigger file (populated by `preset-firstrun` or similar provisioning) is kept so presets still apply non-interactively on first boot. Empty flag removed → wizard skipped, default `root/1234` login continues to work. |

The extension also drops the `armbian-resize-filesystem.service`
enablement symlink — that unit calls `resize2fs` on the root block
device, which does not exist on an NFS root and errors out.

A separate `/boot` partition is not needed for netboot, so the
extension sets `BOOTSIZE=0` to disable it.

**If you want the wizard-set values** (user account, timezone,
locale), bake them into the image at build time:

```sh
# userpatches/customize-image.sh
useradd -m -s /bin/bash -G sudo,netdev alice
echo 'alice:<strong-random-password>' | chpasswd   # or skip this line and rely on SSH key auth only
mkdir -p /home/alice/.ssh
cat > /home/alice/.ssh/authorized_keys <<'KEY'
ssh-ed25519 AAAAC3... alice@laptop
KEY
chown -R alice:alice /home/alice/.ssh
chmod 700 /home/alice/.ssh
chmod 600 /home/alice/.ssh/authorized_keys

ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo 'LANG=en_US.UTF-8' > /etc/default/locale
```

This gives you the same result as running the wizard, without the
interactive hang on first boot. `armbian-firstrun.service` still runs
once on the first boot of a fresh rootfs to generate SSH host keys
(and other unit-of-work helpers); on an NFS root those keys are then
written into the export tree and persist across subsequent reboots —
the host identity is stable, not regenerated each boot.

## End-to-end example: helios64

Target: Helios64 (`rockchip64/helios64`, `edge`/`trixie`,
`ttyS2@1500000`). Builder and NFS server are the same Linux host at
`192.168.1.125`, reachable as `m1`. DHCP is OpenWRT at `192.168.1.1`.

### 1. Server

```sh
apt install tftpd-hpa nfs-kernel-server
cat > /etc/default/tftpd-hpa <<'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/netboot/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --ipv4"
EOF
mkdir -p /srv/netboot/{tftp/pxelinux.cfg,rootfs/shared,rootfs/hosts}
cat >> /etc/exports <<'EOF'
# Restrict to your LAN subnet — see the security note in the
# `/etc/exports` section above. Never use `*` with `no_root_squash`.
/srv/netboot/rootfs          192.168.1.0/24(ro,sync,no_subtree_check,no_root_squash,crossmnt,fsid=0)
/srv/netboot/rootfs/shared   192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/netboot/rootfs/hosts    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF
systemctl enable --now tftpd-hpa nfs-kernel-server
exportfs -ra
```

### 2. Router (OpenWRT)

```sh
ssh root@192.168.1.1 \
  "uci set dhcp.@dnsmasq[0].dhcp_boot='default,m1,192.168.1.125'; \
   uci commit dhcp; /etc/init.d/dnsmasq restart"
```

### 3. Build (single-step, builder = NFS server)

```sh
./compile.sh build \
  BOARD=helios64 BRANCH=edge RELEASE=trixie \
  BUILD_MINIMAL=yes \
  ROOTFS_TYPE=nfs-root \
  NETBOOT_SERVER=192.168.1.125 \
  ROOTFS_COMPRESSION=none \
  ROOTFS_EXPORT_DIR=/srv/netboot/rootfs/shared/rockchip64/helios64/edge-trixie
```

### 4. Drop the TFTP tree into place

> For repeatable multi-board deployments, prefer the `netboot-deploy`
> extension — see [Reference implementation: `netboot-deploy.sh`](#reference-implementation-netboot-deploysh).
> The hook runs after every build with full build-env (`BOARD`, `RELEASE`,
> `BRANCH`, `BOARDFAMILY`, `version`) and rsyncs only the artifacts of
> *this* build, so a single user-config (`NETBOOT_DEPLOY_SSH=...`,
> `NETBOOT_DEPLOY_TFTP_ROOT=...`) covers every board without changes.
> The manual `rsync` below is for one-off builds or troubleshooting.

```sh
# Substitute your build values (board / release / branch) for the
# wildcards below — the directory name follows
# ${FINALDEST}/<version>-netboot-tftp/ where <version> includes them.
rsync -a output/images/Armbian-*_helios64_trixie_edge_*-netboot-tftp/ /srv/netboot/tftp/
# -> /srv/netboot/tftp/pxelinux.cfg/helios64-edge-trixie.example
# -> /srv/netboot/tftp/armbian/rockchip64/helios64/edge-trixie/Image
# -> /srv/netboot/tftp/armbian/rockchip64/helios64/edge-trixie/dtb/rockchip/...

# One-time activation: promote the tagged config into a name U-Boot looks for.
# Pick one of the lookup names depending on scope:
#   default                          — broadest catch-all (any board)
#   default-arm-<arch>-<board>       — board-specific fallback (this example)
#   01-<mac>                         — per-MAC pin (only when NETBOOT_CLIENT_MAC was set)
ln -sfn helios64-edge-trixie.example \
        /srv/netboot/tftp/pxelinux.cfg/default-arm-rk3399-helios64
```

The build writes a tagged file (`<board>-<branch>-<release>.example`)
that is **not** a name U-Boot looks for, so it never auto-activates —
you must explicitly promote it via the `ln -sfn` (or `mv`) above.
Building another release writes its own tagged file next to this one
without touching the active symlink, so you can keep N variants ready
and switch by re-pointing the symlink — no rebuild, no re-deploy.

### 5. Boot

Pull the SD/eMMC out of the Helios64 (or rearrange `boot_targets` so
`pxe` sits before `mmc*`), power it on, and watch the U-Boot console
(`ttyS2 @ 1500000`).

The captured sample below is a real Helios64 boot. It is from a
slightly different run than the walkthrough above — `edge`/`noble`
instead of `edge`/`trixie`, and the build host at `192.168.1.65`
instead of `192.168.1.125`. The walkthrough remains the authoritative
example; this log is included as a real-world reference. Hosts in
the captured sample:

| Address       | Role                                              |
|---------------|---------------------------------------------------|
| 192.168.1.1   | Gateway and DHCP server (router)                  |
| 192.168.1.44  | Helios64 — the netboot client being booted        |
| 192.168.1.65  | Build host — runs TFTP and NFS server             |

```text
Scanning bootdev 'ethernet@fe300000.bootdev':
ethernet@fe300000 Waiting for PHY auto negotiation to complete. done
Speed: 1000, full duplex
BOOTP broadcast 1
DHCP client bound to address 192.168.1.44 (8 ms)

# pxelinux.cfg cascade: U-Boot tries the per-MAC pin first, then
# truncates the 8-hex-char IPv4 progressively, finally falling back
# to the board-specific default symlink. Each miss prints
# "TFTP error: 'File not found' — Not retrying" and is harmless.
Retrieving file: pxelinux.cfg/01-64-62-66-d0-03-cc        (not found)
Retrieving file: pxelinux.cfg/C0A8012C                    (not found)
Retrieving file: pxelinux.cfg/C0A8012                     (not found)
... (cascade continues truncating one hex digit at a time) ...
Retrieving file: pxelinux.cfg/default-arm-rk3399-helios64
Bytes transferred = 482

  1  pxe   ready  ethernet  0  ethernet@fe300000.bootdev extlinux/extlinux.conf
** Booting bootflow 'ethernet@fe300000.bootdev.0' with pxe
1: Armbian helios64 edge noble (netboot)
Retrieving file: armbian/rockchip64/helios64/edge-noble/Image
Retrieving file: armbian/rockchip64/helios64/edge-noble/uInitrd
append: root=/dev/nfs nfsroot=/srv/netboot/rootfs/shared/rockchip64/helios64/edge-noble,tcp,v3 ip=dhcp rw rootwait earlycon loglevel=7 panic=3
Retrieving file: armbian/rockchip64/helios64/edge-noble/dtb/rockchip/rk3399-kobol-helios64.dtb
Starting kernel ...

[    0.000000] Kernel command line: root=/dev/nfs nfsroot=/srv/netboot/rootfs/shared/rockchip64/helios64/edge-noble,tcp,v3 ip=dhcp rw rootwait earlycon loglevel=7 panic=3
[    7.999679] rk_gmac-dwmac fe300000.ethernet eth0: Link is Up - 1Gbps/Full
[    8.022314] Sending DHCP requests ., OK
[    8.039318] IP-Config: Got DHCP answer from 192.168.1.1, my address is 192.168.1.44
[    8.040100] IP-Config: Complete:
[    8.040420]      device=eth0, hwaddr=64:62:66:d0:03:cc, ipaddr=192.168.1.44, mask=255.255.255.0, gw=192.168.1.1
[    8.041914]      bootserver=192.168.1.65, rootserver=192.168.1.65, rootpath=
[    8.060050] Run /init as init process
Loading, please wait...
Starting systemd-udevd version 255.4-1ubuntu8.15
...
Welcome to Armbian-unofficial 26.05.0-trunk noble!
...
[  OK  ] Reached target network.target - Network.
[  OK  ] Reached target getty.target - Login Prompts.

helios64 login:
```

> Linux 6.x and newer no longer print `VFS: Mounted root (nfs filesystem) on device …` for NFS root mounts (that line was specific to disk-backed root). The canonical "PXE done, NFS root mounted, userspace running" markers are `IP-Config: Complete` immediately followed by `Run /init as init process`. If the second line never appears, the NFS mount itself failed — typically `nfsroot` resolution or export ACLs.

For quick lab validation, default credentials are `root` / `1234`
because the wizard was suppressed at build time. **Do not leave that
state on any network you don't fully trust** — the wizard is the only
thing that normally forces a password change, and netboot deliberately
skips it. Pick one before the first boot on an untrusted LAN:

- set `ROOTPWD=<strong password>` at build time;
- or provision a sudo-capable user + `authorized_keys` via
  `userpatches/customize-image.sh` and disable root password login
  (`PasswordAuthentication no` / `PermitRootLogin prohibit-password`);
- or write `PRESET_*` into `/root/.not_logged_in_yet` so
  `preset-firstrun` applies them non-interactively on first boot
  (the extension preserves non-empty trigger files — see the
  `armbian-firstlogin` table above).

The `armbian-firstrun.service` line in the boot log means SSH host keys
have been regenerated on this boot — they'll persist in the NFS rootfs.

## Troubleshooting

**`TFTP from server 192.168.1.1` instead of `.125`** — the router is
providing `siaddr` (its own IP). DHCP option 66/67 are not being sent,
or are being sent without `siaddr`. Check `uci show dhcp | grep boot`
on OpenWRT; on other DHCP servers check the equivalent next-server
setting. Also confirm U-Boot is reading the **first** OFFER: it does
not merge multiple OFFERs, so a proxyDHCP server will not help here.

**`Retrieving file: C0A8012C.img` followed by `ABORT`** — U-Boot
received the OFFER with no bootfile, fell back to requesting a file
named after its own IP in hex (`C0A8012C` = `192.168.1.44`). Fix: set
option 67 (`bootfile`) on the DHCP server to `default`.

**`pxelinux.cfg/pxelinux.cfg/…` in the tftpd-hpa log** — the DHCP
bootfile is `pxelinux.cfg/default` (or anything with a slash). U-Boot
extracts the directory and re-prefixes `pxelinux.cfg/` itself. Set
bootfile to the bare filename `default`.

**`VFS: Unable to mount root fs via NFS`** — several causes, check in
order:

- Kernel was built without `CONFIG_ROOT_NFS`/`CONFIG_IP_PNP_DHCP`.
  The extension's `custom_kernel_config__netboot_enable_nfs_root`
  hook turns these on; make sure you didn't override it. `zcat
  /proc/config.gz | grep -E 'ROOT_NFS|IP_PNP'` on a known-good
  image.
- `/etc/exports` path mismatch vs what's in `nfsroot=`. `showmount
  -e <server>` and compare byte-for-byte.
- Server firewall is blocking TCP/2049 (or the randomized mountd
  port for NFSv3). Pin mountd and open the port.
- `nfsroot=` is using a hostname the client can't resolve yet (DNS
  isn't up during early mount). Use an IP, not a hostname — the
  extension does this by default when `NETBOOT_SERVER` is set.
- `NFS over TCP not available from <gateway-ip>` — the initramfs is
  trying to mount from the default gateway instead of the NFS server.
  The DHCP boot-server (`siaddr`) is not set or points to the wrong
  host. Set `dhcp-boot=default,nfsserver,<nfs-server-ip>` in dnsmasq
  (or `uci set dhcp.@dnsmasq[0].dhcp_boot='default,nfsserver,<ip>'`
  in OpenWRT) so the router announces the NFS server as siaddr. Check
  `/proc/net/pnp` on a booted client — `bootserver` must match your
  NFS server IP. If you can't configure the router, set
  `NETBOOT_SERVER=<ip>` at build time and rebuild.

**`MODULE FAILURE` from initramfs** — the kernel is loading an
initramfs and trying to run `/init` that doesn't understand NFS root.
Either drop the initrd from the PXE config (the extension copies
`uInitrd` only if one exists) or rebuild the initramfs with NFS
support (`update-initramfs -u` with `MODULES=most` in
`/etc/initramfs-tools/initramfs.conf`).

**Board boots from SD/eMMC instead of netboot.** The default
`boot_targets` on most Armbian boards puts local storage first
(`mmc1 mmc0 scsi0 usb0 pxe dhcp`). `pxe`/`dhcp` only trigger when no
local bootflow is found. Either physically remove the local media or
re-order `boot_targets` in U-Boot env:

```text
=> env set boot_targets "pxe dhcp mmc1 mmc0 scsi0 usb0"
=> env save
```

Note that `env save` is per-board and can be wiped by the next U-Boot
flash.

**Wrong baud rate on serial console.** The extension intentionally
does **not** put `console=…` in the kernel APPEND line. Hardcoding a
baud (e.g. 115200) breaks boards like Helios64 that run at
`1500000`. The kernel resolves the console from DT
`/chosen/stdout-path`; `earlycon` is still passed so you see early
boot output. If you see *no* console output at all, check that the
board's U-Boot `bootargs` template isn't overriding APPEND.

**`armbian-firstlogin` whiptail wizard still appears.** Two causes:
(1) stale image — built before you enabled the extension, so
`/root/.not_logged_in_yet` was never removed. Rebuild, or
`ssh root@<ip> rm -f /root/.not_logged_in_yet` on the deployed
rootfs. (2) The trigger file is **non-empty** — the extension
intentionally keeps it so `preset-firstrun` can consume `PRESET_*`
values. Check with `stat -c %s /root/.not_logged_in_yet`: zero
bytes → stale image, non-zero → expected, presets will apply on
first boot and then the wizard stops triggering.
