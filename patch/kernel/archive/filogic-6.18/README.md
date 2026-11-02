# Filogic Linux 6.18 patches

The series uses the kernel.org `linux-6.18.y` branch as its base. It serves
the BPI-R4 (MT7988) and the BPI-R3 Mini (MT7986).

## BPI patches

`patches.bpi/` holds commits from Frank-W's `6.18-main` branch. The reviewed
range is the 138 non-merge commits on top of `v6.18.53` (the merge base with
stable). Each patch keeps its `cherry picked from commit` line.

Taken: runtime changes for the BPI-R4: RSS and LRO, phylink PCS handling,
the MT7988 LynxI and USXGMII PCS drivers and their link-flap fixes, MT7988
SerDes paths, BPI-R4 device tree updates, SFP and 10GBASE-R fixes, the
pca954x reset select and the mt7996 default EEPROM tx power fix.

Not taken:
- Build scripts, CI, defconfigs, firmware blobs and documentation.
- Other boards: BPI-R4 Pro, BPI-R4 Lite, MT7987, MT7622 and MT7623.
- MaxLinear switch and AS21xxx PHY drivers.
- `net: pcs: mediatek: usxgmii: TEST INBAND DISABLED UXGMII`: test change.
- `net: sfp: enhance quirk for HUAWEI MA5671A`: stable has the fix.
- `wifi: mt76: allow loading eeprom from file`, `mt76: Fix file loading`: mt76
  waits 60 s for a missing file before it uses the DT calibration.
- `hwrng: add driver for MediaTek TRNG SMC`: no MT7988 or MT7986 DT node uses it.

These patches conflicted with stable and were resolved by hand:
- `Add RSS support`, `Add LRO support`: stable registers the netdevs after the
  dummy netdev. The NAPI setup and the probe error path follow that order.
- `add paths and SerDes modes for MT7988`: `phylink_create()` uses the
  per-SoC `mac_ops`, and the stable EEE LPI setup stays.
- `introduce internal phylink PCS handling`: keeps the stable
  `IS_ERR_OR_NULL()` check of `mac_select_pcs()`.
- `Use tx_power from default fw if EEPROM contains 0s`: keeps the stable
  default EEPROM size check.

## Armbian patches

`patches.armbian/` holds the BPI-R3 Mini device tree patches, the xHCI
shutdown fix and the BPI-R4 part of the upstream commit that builds full SD
and eMMC dtbs.

Patches 0035 to 0041 fix review findings in the BPI patches and in the
xHCI shutdown fix. They keep the BPI patches unchanged.
