# Configuration Directory

This directory contains the build-time configuration files, templates, and data consumed by the Armbian build framework.

- `ARMBIAN_CACHE_DIR` (default `/armbian/cache`): Host path that, when present, is bind-mounted into the chroot at `/armbian/cache` to share downloaded artifacts (keyrings, packages, etc.) between builds. Override this if your cache lives elsewhere or needs to be relocated for containerized builds.
