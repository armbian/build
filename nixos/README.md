Install nix CLI: [See nix docs](https://nixos.org/download/)
Enable cross compilation from x86 machine and enable flakes:
Add to `/etc/nix/nix.conf`:
```
experimental-features = nix-command flakes
extra-platforms = aarch64-linux arm-linux i686-linux
```

BUILD (Regular SD):  `nix build .#sdImages.rpi4 --print-build-logs`
BUILD (Uncompressed): `nix build .#sdImages.rpi4-uncompressed --print-build-logs`
BUILD (Immutable): `nix build .#sdImages.rpi4-immutable --print-build-logs`
BUILD (Immutable-Uncompressed): `nix build .#sdImages.rpi4-immutable-uncompressed --print-build-logs`

FLASH (Compressed): `zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync`
FLASH (Uncompressed): `sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync`
DECOMPRESS: `zstd -d result/sd-image/nixos* -o rpi4-nixos.img`
FLASH WITH CALIGULA: `sudo caligula burn result/sd-image/nixos*`

UPDATE:
`nixos-rebuild switch --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false`
UPDATE with sshpass:
`sshpass -p "cisco" nixos-rebuild switch --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false`

UPDATE (boot):
`sshpass -p "cisco" nixos-rebuild boot --flake .#rpi4 --target-host root@<IP_OR_HOSTNAME> --option filter-syscalls false`

GENERATE Password for hashedPassword:
`mkpasswd -m sha-512`
