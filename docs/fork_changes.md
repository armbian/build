# OnePlus 8T (Kebab) WiFi Enable – Summary of Required Changes

This document describes the changes needed to get WiFi working on the OnePlus 8T (kebab) under Armbian. The device uses a **QCA6390** WiFi/Bluetooth chip on PCIe; without these changes, the WiFi device never appears on the bus and no `wlan0`/`wlp1s0` interface is created.

---

## 1. Device tree: Remove PCIe PHY dependency on qca639x

**Where:** `patch/kernel/archive/sm8250-6.18/0011-arm64-dts-qcom-sm8250-oneplus-kebab-Add-device-tree-.patch`  
**What:** Remove `power-domains = <&qca639x>` from the `&pcie0_phy` node (the PCIe PHY that serves the WiFi bus).

**Why:**  
The WiFi PCIe controller is `1c00000.pcie`; its PHY is at `1c06000`. The PHY node had `power-domains = <&qca639x>`, so the kernel would not fully bring up the PHY until the **qca639x** power-sequencing driver had probed.  
The qca639x driver (and/or its pinctrl) depends on `33c0000.pinctrl`, which in turn waits on APR/remoteproc. That chain never completes in this environment, so qca639x never probes. The PHY then stayed in deferred probe until the kernel gave up, and `1c00000.pcie` (bus `0000:00`) never came up.  
Removing the power-domain binding lets the PHY and PCIe controller probe without qca639x, so bus `0000:00` is created and the WiFi device can later appear as `0000:01:00.0` once it is powered.

---

## 2. Device tree: Remove WLAN/BT enable GPIOs and pinctrl from kernel

**Where:** Same patch file.  
**What:**  
- In the **qca639x** node: remove `pinctrl-names`, `pinctrl-0`, `pinctrl-1`, `wlan-enable-gpios`, and `bt-enable-gpios`.  
- In the **bluetooth** node (under `&uart6`): remove `pinctrl-names`, `pinctrl-0`, `pinctrl-1`, and `enable-gpios`.  
- Keep `power-domains = <&qca639x>` in the bluetooth node.  
- Add short comments noting that WLAN/BT enable are driven from userspace.

**Why:**  
The QCA6390 needs **tlmm GPIO 20** (WLAN enable) and **tlmm GPIO 21** (BT enable) driven high to power on. In the original DTS these were assigned to the qca639x and bluetooth drivers.  
Because qca639x does not probe, the kernel still “reserves” those GPIOs when it parses the device tree. Any attempt from userspace to use them (either via sysfs `export` or via `gpioset`) then fails with **“Device or resource busy”**.  
By removing the GPIO and pinctrl properties from the DTS, no kernel driver claims those pins. Userspace can then control them (via the gpiod character-device API) to power the chip. The hardware behaviour is unchanged; only the owner of the GPIOs moves from kernel to userspace.

---

## 3. Patch file format and line counts

**Where:** Same `0011-...-kebab-Add-device-tree-.patch` file.  
**What:**  
- Set the DTS hunk to add exactly **825** lines: `@@ -0,0 +1,825 @@`.  
- Set the diff summary to `825 +++++++++++++++++` and `2 files changed, 826 insertions(+)`.  
- Ensure there is no bare blank line (no `+`, `-`, or space prefix) inside the DTS hunk; the last line before `-- ` must be a valid hunk line (e.g. `+` for a trailing newline in the file).

**Why:**  
Unified diff format requires the line count in each hunk to match the number of added/removed/context lines. After editing the DTS (removing GPIO/pinctrl blocks and adding comments), the DTS hunk had 825 added lines. Leaving the count at 826 (or having a blank line without a prefix) caused the kernel patcher to report **“malformed patch at line 849”** and abort. Correcting the count and ensuring every hunk line has a valid prefix fixes the apply.

---

## 4. Userspace WLAN (and BT) enable script

**Where:** `packages/bsp/oneplus-kebab/qca6390-wlan-enable.sh`  
**What:** A shell script that:  
- Uses `gpiodetect` to find the TLMM gpiochip (label `f100000.pinctrl`).  
- Uses **gpioset** to drive **line 20** (WLAN enable) and **line 21** (BT enable) high on that chip, and keeps the process running so the lines stay high.  
- After a short delay, writes `1` to `/sys/bus/pci/rescan` so the kernel rescans PCI and discovers the QCA6390 as `0000:01:00.0`.  
- The script runs until killed (it `wait`s on the background `gpioset`), so the service that runs it stays up and the enable lines remain asserted.

**Why:**  
With the GPIOs no longer claimed by the DTS, userspace must assert them. The QCA6390 does not power up until WLAN enable (tlmm 20) is high; BT enable (tlmm 21) is set high in the same way for Bluetooth.  
We use the **gpiod** character-device API (`gpioset`) instead of the legacy sysfs GPIO interface because: (1) sysfs `export` was failing when the GPIOs were still in the DTS; (2) even after removing them from the DTS, the character-device API is the preferred and robust way to control GPIOs.  
`gpioset` must keep running (no `-t 0`) so the lines stay high; exiting would release the lines and the chip could power down.  
PCI rescan is needed because the device is powered only after boot; the kernel does not see it at initial enumeration, so we trigger a rescan after driving the enable GPIOs.

---

## 5. Systemd service for WLAN/BT enable at boot

**Where:** `packages/bsp/oneplus-kebab/qca6390-wlan-enable.service`  
**What:**  
- Unit that runs `qca6390-wlan-enable.sh`.  
- `After=local-fs.target`, `Before=network-pre.target` so it runs early but after `/sys` is available.  
- `Type=simple` because the script does not exit (it holds the GPIOs via `gpioset`).  
- `WantedBy=multi-user.target` so it starts at normal boot.

**Why:**  
WiFi (and PCIe discovery) must be enabled before the network stack tries to use the interface. Running as a service ensures the enable sequence and PCI rescan happen automatically on every boot.

---

## 6. Board configuration: install script, service, and gpiod

**Where:** `config/boards/oneplus-kebab.conf`  
**What:**  
- In **post_family_tweaks_bsp__oneplus-kebab_firmware**: install `qca6390-wlan-enable.sh` to `/usr/local/bin/` and `qca6390-wlan-enable.service` to `/usr/lib/systemd/system/`.  
- In **post_family_tweaks__oneplus-kebab_enable_services**: run `systemctl enable qca6390-wlan-enable.service`.  
- In the same function, add **gpiod** to the `chroot_sdcard_apt_get_install` list so the image has `gpioset` and `gpiodetect`.

**Why:**  
The script and service must be on the rootfs and enabled so that every built image runs the enable sequence at boot. The script depends on `gpioset` and `gpiodetect` from the **gpiod** package, so gpiod must be installed in the image.

---

## Resulting flow

1. Boot uses a DTB where: (a) the PCIe PHY no longer depends on qca639x, so `1c00000.pcie` and bus `0000:00` come up; (b) tlmm GPIOs 20 and 21 are not claimed by any driver.  
2. Early userspace runs `qca6390-wlan-enable.service`, which runs `qca6390-wlan-enable.sh`.  
3. The script finds the TLMM gpiochip, drives WLAN and BT enable high via `gpioset`, then triggers PCI rescan.  
4. The kernel discovers the QCA6390 at `0000:01:00.0`; the ath11k driver binds and creates the WiFi interface (e.g. `wlp1s0`).  
5. The user can then connect to WiFi (e.g. via NetworkManager or wpa_supplicant + DHCP) as on any Linux system.

---

## Files touched (quick reference)

| Path | Change |
|------|--------|
| `patch/kernel/archive/sm8250-6.18/0011-...-kebab-Add-device-tree-.patch` | Remove pcie0_phy power-domains; remove WLAN/BT GPIO/pinctrl from qca639x and bluetooth; fix hunk line count and patch format. |
| `packages/bsp/oneplus-kebab/qca6390-wlan-enable.sh` | New: gpioset WLAN/BT enable, then PCI rescan. |
| `packages/bsp/oneplus-kebab/qca6390-wlan-enable.service` | New: systemd unit for the script. |
| `config/boards/oneplus-kebab.conf` | Install script and service; enable service; add gpiod to packages. |
