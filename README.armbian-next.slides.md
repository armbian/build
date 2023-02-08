---
type: slide
slideOptions:
transition: slide
theme: league
  
---

# `armbian-next`, 7/X

> “Let me add `set -e` to `armbian/build`...”

#### ...two years later...

#### semi-consolidated version

---

## `armbian-next`

- What? _whirlwind tour_
- How to try out

---

#### `armbian-next` - Bash stuff

- `set -e` bash mode (no more `$?`, stops when things go wrong)
- `stdout`/`stderr` separation
- 100% new logging to `stderr`; levels; emoji :deciduous_tree:
- trap/cleanup manager; managed `TMPDIR`
- runner utility functions (for `chroot` & host)
- 95% cleaner `shellcheck` in `lib/*.sh`
- _many more_

---

#### `armbian-next` - Git stuff

- no more shallow (`--depth=1`) **fetches** anywhere
- using single, bare, Git repository for all kernels / u-boots
    - via `git worktree`
- kernel tree seeding:
    - *fast* + *full* via GitHub actions / `ghcr.io` (~3gb)
    - *fast* + *pre-shallowed* via GitHub actions / `ghcr.io` (~300mb)
- be patient on first build; use `KERNEL_GIT=shallow` to force shallow bundle
- uses `git archive` for firmware, reduces disk usage 50%

---

#### `armbian-next` - New Docker support

- completely rewritten Docker support
- prebuilt Docker images for arm64/amd64 for each of 4 "host" releases
- Dockerfile is auto-generated & re-used
- Using multiple Docker Volumes for `/cache` sub-folders (on Darwin)

---

#### `armbian-next` - Docker (+Rancher), Apple M1

- Supports
    - Linux: `docker.io`, `docker-ce` (Docker Inc)
    - Docker Desktop on Mac Intel **and M1**
    - **Rancher** on Mac M1
        - using `docker` mode, not `containerd`

---

#### `armbian-next` - WSL2

- WSL2 (sans-Docker) is supported
- use Windows Terminal app for emoji glory

---

#### `armbian-next` - Packages Aggregation in Python

- Standalone Python util for aggregation

- `in`: configuration structure (`config` directories, `packages` files, `packages.additional` etc)
- `in`: `RELEASE` and board info / extra packages etc
- `in`: desktop configs, appgroups `DESKTOP_xxx`
- `out`: *arrays* and *dictionaries* of aggregated packages
    - `debootstrap`, `cli`/`desktop`, `image`
- `out`: Markdown docs: _"why is this package included, or not included?", "potential paths"_

---

#### `armbian-next` - Patch handling in Python

- `apply-patches`
- `patches-to-git`
- `git-to-patches`

- Markdown patching summaries
- Rebasing patches
- Git Archeology

---

#### `armbian-next` - General Building

- should build most stuff on **arm64** as well as amd64
- uses **system toolchains by default** for everything
- sets `CFLAGS` to turn some errors into warnings
- allowing old u-boots to build with newer gcc
- manages `python` symlinks for u-boot/kernel usage
- ancient stuff might need small Makefile fixes

---

#### `armbian-next` - Kernel Builds

- `KERNEL_MAJOR_MINOR` (`"5.10"`, `"6.1"`)
- _fast_ rebuilds when working patches
- no more `mkdebian` / `builddeb`
- instead uses `make install` from Kbuild
- packaging and headers handled in `lib/` code now
- (mostly) working header packages when cross compiling (@TODO needs testing and fixes)
- _finally_ no more `headers-byteshift.patch` :wink:

---

#### `armbian-next` - u-boot Builds

- Split targets, but not yet `UBOOT_TARGET_MAP`
- Handling Python2/Python3 requirements
- Handling of x86-only tooling under qemu when building on arm64

---

#### `armbian-next` - Image building

- *no more* `apt-cacher-ng` by default (still works)
- local `.deb` caching, works in Docker too
- Aggregation opens path for `mmdebstrap` migration later

---

#### `armbian-next` - Other 1

- New `CLI` infrastructure; `./compile.sh <command> [NAME=VALUE]... <config_file>`
- `initrd` caching
- ORAS-based artifact caching
- auto-GHA Markdown logs
- pesters user to not run as `root` or under `sudo` (still can...)

---

#### `armbian-next` - Other 2

- pesters user to not run as `root` or under `sudo` (still can...)
- ANSI-pastebin beta 2 + `SHARE_LOG=yes`
- `armbian-kernel` default .config changes, always applied
- tooling (ORAS/shellcheck/etc) + pip packages pre-installed in Docker images
- shellcheck is run on `DEBIAN/postinst` and such in all packages

---

#### `armbian-next` - Stuff that's dropped :satisfied:

- `extras` `buildpkg`
- `repo` management
- `FEL` boot support

---

#### TODO stuff

- @TODO: kernel wifi drivers: `.config` auto `=m`; use `sha1` instead of `branch`
- @TODO: patching: needs summary "table" on-screen
- @TODO: patching: needs proper "rejects" log
- @TODO: logging: summarize "make" output, `998 CCs, 500 LDs, 312 INSTALLs`
- @TODO: `compile.sh` -> `armbian.sh`
- @TODO: "minimal" images vs aggregation, probably wrong

---

#### Update 8th February `armbian-next` - "artifacts"

- big WiP; producing isolated artifacts
- artifacts have consistent versions
- artifacts can be cached both locally and remotely (OCI/ORAS)
- _not yet_ used for building images; will soon
- `REPOSITORY_INSTALL` is no more
- will need testing, a lot of it

---

#### Trying out `armbian-next`

##### **do not share dir with `master`!!**

``` bash
cd ~ # clone to a new directory!
git clone --branch=armbian-next \
  https://github.com/armbian/build armbian-build-next

cd ~/armbian-build-next
./compile.sh # and off you go

# Later, to update:
cd ~/armbian-build-next
git pull --rebase # !!!we rebase!!! use --rebase
```

---

#### Trying out `armbian-next`, pt 2

* If using Docker or WSL2, turn up Resources (CPU/RAM/Disk)
    * Mac: use `VirtIOFS` sharing and Virtualization framework
* Turn up logging
    * `DEBUG=yes` a lot of debugging info
    * `SHOW_COMMAND=yes` shows the runners commands cmdline
    * ...
* Grab logs at `output/logs`, use new paste / `SHARE_LOG=yes`

---
