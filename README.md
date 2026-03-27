# IP Terminals

This repository contains the configuration and build system for custom IP Terminal images, designed for use in Thomas More network classrooms. Based on **NixOS**, these images provide a robust, immutable environment for network debugging and configuration.

## 🚀 Key Features
- **Immutable Environment**: Root filesystem is read-only by default (stateless).
- **Network Tools**: Pre-installed `nmap`, `dnsutils`, `traceroute`, `netcat`, and more.
- **Custom Configuration**: A built-in `config` tool to manage network settings via TUI.
- **Hardware Integration**: Support for LCD displays and custom service for IP monitoring.
- **Remote Management**: SSH enabled by default (User: `cisco`, Password: `cisco`).

---

## 🛠️ Getting Started

### 1. Install Nix
To build these images, you need the Nix package manager:
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### 2. Configure Nix
Enable Flakes and Cross-Compilation by adding the following to `/etc/nix/nix.conf`:
```text
experimental-features = nix-command flakes
extra-platforms = aarch64-linux arm-linux i686-linux
```

---

## 🏗️ Building the Image

You can build different variants of the SD card image using the Nix flake.
NOTE: Building can take a while. Some packages are downloaded from cachix and others are built from source.

| Variant | Command |
| :--- | :--- |
| **Standard SD** | `nix build .#sdImages.rpi4 --print-build-logs` |
| **Uncompressed** | `nix build .#sdImages.rpi4-uncompressed --print-build-logs` |
| **Immutable** | `nix build .#sdImages.rpi4-immutable --print-build-logs` |
| **Immutable (Uncompressed)** | `nix build .#sdImages.rpi4-immutable-uncompressed --print-build-logs` |

---

## 💾 Flashing to SD Card

Once built, the image will be in `result/sd-image/`. Replace `/dev/sdX` with your SD card device path.

### Using `dd` (Standard)
```bash
# For compressed images (.img.zst)
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# For uncompressed images (.img)
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### Other Methods
- **Manual Decompression**: `zstd -d result/sd-image/nixos* -o rpi4-nixos.img`
- **Using Caligula**: `sudo caligula burn result/sd-image/nixos*`

---

## 🔄 Updating

For testing purposes, you can update the terminals over the network without reflashing the SD card.
NOTE: This is only possible for mutable images.

### Update (via ssh)
```bash
nixos-rebuild switch --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false
```

### Update (via sshpass)
```bash
sshpass -p "cisco" nixos-rebuild switch --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false
```

### Update for next boot (via sshpass)
```bash
sshpass -p "cisco" nixos-rebuild boot --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false
```

---

## 🔐 Configuration

### Password Generation
If you need to update the `hashedPassword` in `flake.nix`, generate a new hash using:
```bash
mkpasswd -m sha-512
```

### Default Credentials
- **Username**: `cisco` (or `root`)
- **Password**: `cisco`
