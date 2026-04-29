# Appliance Image Extension

This extension provisions an appliance-style image directly at build time.

Features:
- installs appliance packages into the image
- copies an application binary from a local path or download URL
- can extract a `.tar.gz` release asset before installing the binary
- creates a managed systemd service
- creates login and service users
- optionally enables SSH
- configures UFW and avahi-daemon
- disables Armbian first-run prompts so the image boots in its final state

Enable it in your build config with `ENABLE_EXTENSIONS="appliance-image"` and set at least one of:
- `APPLIANCE_IMAGE_BINARY_SOURCE_PATH`
- `APPLIANCE_IMAGE_BINARY_URL`

Useful settings:
- `APPLIANCE_IMAGE_SERVICE_NAME`
- `APPLIANCE_IMAGE_LOGIN_USER`
- `APPLIANCE_IMAGE_LOGIN_PASSWORD`
- `APPLIANCE_IMAGE_HOSTNAME`
- `APPLIANCE_IMAGE_OVERLAY_DIR`
- `APPLIANCE_IMAGE_BINARY_URL_EXTRACT_MODE=targz`
- `APPLIANCE_IMAGE_BINARY_ARCHIVE_MEMBER`
- `APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT`
- `APPLIANCE_IMAGE_AVAHI_SERVICE_PORT`
- `APPLIANCE_IMAGE_SUDOERS_CONTENT`
- `APPLIANCE_IMAGE_OPEN_PORTS`
- `APPLIANCE_IMAGE_ENABLE_SSH=yes`

`APPLIANCE_IMAGE_OVERLAY_DIR` can point at a directory whose contents should be copied into the image rootfs, for example files under `etc/`, `opt/`, or `var/lib/your-app/`.

`APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT` is a space-separated list of `KEY=value` entries suitable for simple service environments.

When `APPLIANCE_IMAGE_BINARY_URL_EXTRACT_MODE=targz`, the extension downloads the URL as a gzip-compressed tar archive and extracts `APPLIANCE_IMAGE_BINARY_ARCHIVE_MEMBER` into the final install path.