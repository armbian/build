---
type: slide
slideOptions:
transition: slide
theme: league
  
---

# `armbian-next`, 2/X

> “Let me add `set -e` to `armbian/build`...”
#### ...two years later...

---

## `armbian-next`

- What? _whirlwind tour_
- How to try out
- Plans for merge

---

#### `armbian-next` - Bash stuff

- `set -e` bash mode (no more `$?`, stops when things go wrong)
- `stdout`/`stderr` separation
- 100% new logging to `stderr`; levels; :deciduous_tree:
- trap/cleanup manager; managed `TMPDIR`
- runner utility functions (for `chroot` & host)
- 90% cleaner `shellcheck` in `lib/*.sh`
- _many more_

---

#### `armbian-next` - Git stuff

- no more shallow (`--depth=1`) fetches anywhere
- using single, bare, Git repository for all kernels / u-boots
    - via `git worktree`
- kernel tree seeding (~4gb):
    - *fast* via GitHub actions / `ghcr.io`
    - *slow* via `kernel.org` Git Bundles
- be patient on first build

---

#### `armbian-next` - New Docker support

- completely rewritten Docker support
- prebuilt Docker images for arm64/amd64 for each of 4 "host" releases
- Dockerfile is auto-generated & re-used
- Using multiple Docker Volumes for `/cache` sub-folders

---

#### `armbian-next` - Docker (+Rancher), Apple M1

- Supports

- Linux: `docker.io`, `docker-ce` (Docker Inc)
- Docker Desktop on Mac Intel **and M1**
- **Rancher** on Mac M1
    - using `docker` mode, not `containerd`
- _might just work on Windows with WSL2_

---

#### `armbian-next` - Packages Aggregation in Python

- Standalone Python util for aggregation

- `in`: configuration structure (`config` directories, `packages` files, `packages.additional` etc)
- `in`: `RELEASE` and board info / extra packages etc
- `in`: desktop configs, appgroups `DESKTOP_xxx`

---

#### `armbian-next` - Packages Aggregation in Python

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
- ancient stuff might need small Makefile fixes


---

#### `armbian-next` - Kernel Builds

- `KERNEL_MAJOR_MINOR` (`"5.10"`, `"6.1"`)
- _fast_ rebuilds when working patches
- no more `mkdebian` / `builddeb`
- instead uses `make install` from Kbuild
- packaging and headers handled in `lib/` code now
- (mostly) working header packages when cross compiling
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

#### `armbian-next` - Other

- New `CLI` infrastructure
- `initrd` caching :smiley_cat:
- ORAS-based storage foundation
- ...

---

#### `armbian-next` - Stuff that's not ready :satisfied:

- `extras` `buildpkg`
- `repo` management
- `EXTRAWIFI=yes`

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

* If using Docker Desktop, turn up Resources (CPU/RAM/Disk), use `VirtIOFS` sharing and Virtualization framework
* Turn up logging
    * `SHOW_LOG=yes` shows output of runner commands
    * `SHOW_DEBUG=yes` a lot of debugging info
    * `SHOW_COMMAND=yes` shows the runners commands cmdline
    * ...
* Grab logs at `output/logs`

---

#### `armbian-next` - Plans for merge

- `200+` commits, `+75k -8k`
- get developers trying it out
- get Igor to try it out on CI
- fix, fix, fix
- documentation (you're looking at it)
- single PR, ~20 commits, squashed by directory
- use for next release (23.02?)

---

## Go try `armbian-next`
# Thank you!

---

#### Update Dec 21-28 - Fixes

- `sunxi`/`sunxi64` patching (`series.conf`)
- `git worktree` references with absolute paths
    - switching between Docker and non-docker on Linux
- small fixes for early stoppages (`origin` branch, etc)


---

#### Update Dec 21-28 - New

- ORAS (via `ghcr.io`) kernel tree seeding (4gb -> 2gb)
- Patch+hash generator for `EXTRAWIFI` kernel drivers
    - Still WiP: `.config` auto `=m`; use `sha1` instead of `branch`
- patched files modification time consistency (fast rebuilds)
- `grub` fixes and sanity checks (sbc-media/jetson-nano, riscv64)
    - workarounds for `grub-mkconfig` under Docker


---

#### Update Dec 21-28 `armbian-next` - Stuff that's not ready

- `extras` `buildpkg`
- ~~`repo` management~~ (moved away by Igor)
- ~~`EXTRAWIFI=yes`~~ (experimental support, WiP)
- `BUILD_ONLY=` (replaced with new CLI, needs impl)

- rootfs hashes don't match
- permissions problems when using sudo/Docker

