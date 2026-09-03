# Filogic Linux 7.2 patches

The active series uses the official kernel.org `linux-7.2.y` branch as its
base. BPI hardware patches are taken from Frank-W's `7.2-main` branch so that
they match the Linux 7.2 APIs. GL-MT2500 patches follow the BPI compatibility
series.

The following upstream range contains the 86 commits reviewed for this port:

```
0a484c3734f978e5d041c8e40e845f73b82cbfd2..6.16-rsslro
```

The original format-patch files are not stored in this archive. They can be
reproduced from the range above when needed. The active Linux 7.2 equivalents
are kept in `patches.bpi/`; build, packaging, defconfig, test, cover-letter, and
documentation-only changes are intentionally omitted.

## 6.16-rsslro audit

Mechanical patch applicability is not used as the selection criterion. The
original range also contains local build helpers, temporary validation changes,
and intermediate revisions that must not become Armbian kernel patches.

The original commits are classified as follows:

| Original patch IDs | Disposition for Linux 7.2 |
| --- | --- |
| `0009`, `0033`, `0035`, `0046`, `0048-0051`, `0053-0063`, `0065-0066`, `0074-0078`, `0080-0086` | Ported, rebased, or folded into the active `patches.bpi/` series |
| `0001-0004`, `0011-0015`, `0017-0029`, `0031-0032`, `0042-0044`, `0052`, `0064`, `0069-0071` | Already upstream or superseded by Linux 7.2 implementations |
| `0005-0008`, `0010`, `0016`, `0036-0041`, `0045`, `0067-0068`, `0072-0073`, `0079` | Build, packaging, defconfig, test, cover-letter, or documentation-only changes; excluded |
| `0030`, `0034`, `0047` | Intentionally excluded runtime changes; see below |

The last group is excluded because `0030` removes the read-only protection from
the BL2 partition, `0034` adds an unused CPU-frequency calibration cell, and
`0047` adds an out-of-tree module that can make every MTD partition writable.

Only entries listed in the top-level `series.conf` are stored and applied during
a build.
