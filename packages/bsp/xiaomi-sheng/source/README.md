# libssc source & licensing (GPL compliance)

This directory ships the **corresponding source** for the prebuilt
`libssc_0.4.2-1_arm64.deb` that the `xiaomi-sheng` image installs, so that
redistributing the GPL-licensed `libssc` binary complies with the GNU GPL.

## Upstream metadata
- Project: libssc (Library to expose Qualcomm Sensor Core sensors)
- Upstream: https://codeberg.org/DylanVanAssche/libssc
- Version: 0.4.2
- Commit: 300a2a070e6dca5618334fd31d2516dc50bce8aa
- License: GPL-3.0-or-later (see the LICENSE file inside the tarball and the
  `libssc-0.4.2-copyright` file next to it)

## Contents
- `libssc-0.4.2.tar.gz` – the exact upstream source at the tag `v0.4.2`,
  created with `git archive`. It contains the libssc `meson.build` build
  system, `src/`, `data/`, `utils/`, `mocking/`, `tests/` and `docs/`, plus
  the `LICENSE` and `README.md`.
- `libssc-0.4.2-copyright` – a Debian-style copyright file recording the
  license and provenance.

## Notes
- The tarball is produced with `git archive`, so the git submodules referenced
  by `.gitmodules` (`libqmi`, `mocking/qrtr`) are not expanded; they are
  optional test/mock tooling and are intentionally excluded.
- The `xiaomi-sheng-thp` package itself is Apache-2.0 (see its `LICENSE`), so
  only `libssc` requires source accompanying.
