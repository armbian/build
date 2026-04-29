# AutoButler Image Extension

This extension provisions an AutoButler appliance image from the latest GitHub release.

It builds on `appliance-image` and preconfigures:

- latest `autobutler_Linux_arm64.tar.gz` from GitHub Releases
- install path `/usr/local/bin/autobutler`
- systemd service `autobutler.service`
- service account and login account `autobutler`
- data directory `/var/lib/autobutler/data`
- mounts directory `/var/lib/autobutler/mounts`
- HTTP on port 80
- avahi service for `autobutler.local`
- sudoers rule needed for managed mount operations

Enable it with:

```sh
ENABLE_EXTENSIONS="autobutler-image"
```

Optional settings:

- `AUTOBUTLER_IMAGE_LOGIN_PASSWORD`
- `AUTOBUTLER_IMAGE_LOGIN_USER`
- `AUTOBUTLER_IMAGE_HOSTNAME`
- `AUTOBUTLER_IMAGE_PORT`
- `AUTOBUTLER_IMAGE_ENABLE_SSH=yes`
