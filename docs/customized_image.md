# Customized Armbian Image (Oneplus 8t)

This describes how to build a **customized** rootfs image for the Oneplus 8t (ABL) with users, passwords, SSH keys, extra packages, and custom commands applied **inside the image** before flashing. The device will not run the normal first-boot wizard; everything is preconfigured.

## Prerequisites

- A built Armbian image for oneplus-kebab (see [README](../README.md) and [flashing_instructions.md](flashing_instructions.md)), or you will use `--build` to build first.
- **Linux:** Root or sudo (for mounting the rootfs image and chroot).
- **macOS:** Docker (the customizer runs inside a Linux container; same as for the main build).

## Quick start

1. Copy the example config and edit it:

   ```bash
   cp userpatches/customized-image.yaml.example userpatches/customized-image.yaml
   # Edit userpatches/customized-image.yaml (passwords, users, SSH keys, packages, etc.)
   ```

2. Run the wrapper (build + customize, or customize only):

   ```bash
   # Build a clean image, then customize it:
   ./scripts/build-customized-image.sh --build userpatches/customized-image.yaml

   # Or customize an existing rootfs image:
   ./scripts/build-customized-image.sh userpatches/customized-image.yaml
   ./scripts/build-customized-image.sh userpatches/customized-image.yaml output/images/Armbian_*.rootfs.img
   ```

3. Flash the **customized** rootfs image to the phone’s “linux” partition (see flashing instructions). Use the same `*.boot_*.img` as before; only the rootfs is replaced.

## Config file (YAML)

Path: `userpatches/customized-image.yaml` (or any path you pass to the script).

| Key | Description |
|-----|-------------|
| `root_password` | Root password (plain text) set in the image. |
| `user_name` | Optional new user (created with `useradd`). Leave empty to skip. |
| `user_password` | Password for the new user. |
| `user_shell` | Login shell for the new user (default: `/bin/bash`). |
| `user_sudo` | Sudoers spec for the new user (e.g. `ALL=(ALL) NOPASSWD:ALL`). Empty = no sudo. |
| `ssh_keys_root` | List of SSH public keys for `root`: file paths or inline key strings. |
| `ssh_keys_user` | List of SSH public keys for the new user (if `user_name` is set). |
| `locale` | System locale (e.g. `en_US.UTF-8`). If set, enables the locale in locale.gen, runs locale-gen, and sets LANG. |
| `timezone` | Timezone name (e.g. `America/Chicago` for US Central). If set, writes /etc/timezone and /etc/localtime. |
| `wifi_ssid` | WiFi network name (SSID). If set, a NetworkManager connection is created so the system connects on first boot. Requires NetworkManager in the image (default for non-minimal Armbian). |
| `wifi_password` | WiFi password (WPA-PSK). Use together with `wifi_ssid`. |
| `extra_packages` | List of package names to install with `apt-get install` (customizer has network). |
| `run_commands` | List of shell commands to run inside the chroot (e.g. enable services, edit configs). |

**Disk space:** A full `apt-get upgrade` can run out of space because unpacked packages are written to the rootfs (the image has fixed size). If upgrade fails with "No space left on device", hold large packages during upgrade (e.g. `apt-mark hold armbian-firmware-full` before `apt-get upgrade -y`, then `apt-mark unhold armbian-firmware-full`).

Example:

```yaml
root_password: "secure-root-password"
user_name: "armbian"
user_password: "user-password"
user_shell: "/bin/bash"
user_sudo: "ALL=(ALL) NOPASSWD:ALL"
ssh_keys_root:
  - "~/.ssh/id_ed25519.pub"
ssh_keys_user:
  - "~/.ssh/id_ed25519.pub"
extra_packages:
  - "vim"
  - "htop"
run_commands:
  - "systemctl enable some-service"
```

Paths in `ssh_keys_root` / `ssh_keys_user` can be relative to the directory containing the config file or absolute. On Linux, `~` is expanded to your home directory. On macOS (Docker), use paths relative to the config file or put key files under `userpatches/` so they are available inside the container.

## Scripts

- **`scripts/build-customized-image.sh`** – Wrapper: optional build, then runs the customizer. On macOS it runs the customizer inside Docker.
- **`scripts/customize-image.sh`** – Core customizer (Linux only): mounts the rootfs image, chroots, applies the YAML config, writes `*-customized.rootfs.img`. Called by the wrapper or directly (as root) on Linux.

## macOS (Darwin)

On macOS there is no `losetup` or native way to mount a raw ext4 image. The wrapper detects Darwin and runs the customizer **inside a Debian Docker container** with the image and config bind-mounted. Docker is required (same as for `./compile.sh build` on Mac). The first run may install `python3-yaml` inside the container.

## Output

The customizer does **not** modify your original rootfs image. It copies it to a new file and modifies the copy:

- Input:  `Armbian_*_Oneplus-kebab_noble_current_*.rootfs.img`
- Output: `Armbian_*_Oneplus-kebab_noble_current_*-customized.rootfs.img`

Flash the `*-customized.rootfs.img` to the “linux” partition and use the same `*.boot_*.img` for `boot_b` as in the normal flashing flow.

## Dependencies

- **Host (Linux or inside Docker):** `python3`, `python3-yaml` (PyYAML), `losetup`, `mount`, `chroot`. On Debian/Ubuntu: `apt-get install python3-yaml`.
- The customizer runs with network access so `extra_packages` are installed with `apt-get install` inside the chroot.
