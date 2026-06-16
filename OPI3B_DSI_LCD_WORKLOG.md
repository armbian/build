# Orange Pi 3B v2.1 Waveshare 5-inch DSI LCD Worklog

Date: 2026-06-15

## Current Result

The Waveshare/Raspberry-compatible 5-inch 800x480 DSI LCD now boots normally on Orange Pi 3B v2.1 with the Armbian vendor 6.1 RK3566 image.

Working image:

```text
output/images/Armbian-unofficial_26.05.0-trunk_Orangepi3b_bookworm_vendor_6.1.115-opi3b21-debug-npu-gpu-dsi-nooops7_minimal.img
```

SHA256:

```text
b6be827a4410bd530915c58de94fcaa3c0b5c7a7c38b9eafdaede022da207119
```

Image checks:

```text
sha256sum -c: OK
MBR signature: 55aa
GPT marker at byte 512: 0000000000000000
```

The image remains MBR/msdos, not GPT.

## 2026-06-16 Brightness And Horizontal Wrap Fix

The desktop build with ATTINY brightness support exposed `/sys/class/backlight/rpi_backlight` correctly, but the LCD showed horizontal wrap: pixels from the right side of the screen appeared at the left edge, with artifacts around dynamic regions such as the cursor, taskbar icons, and drop-downs.

Research and local code inspection pointed at a TC358762 timing mismatch rather than Panfrost, Xorg, or touch input:

- The Raspberry-compatible panel path controls brightness through the ATTINY `REG_PWM` register at I2C address `0x45`.
- The same path also programs the Toshiba TC358762 DSI-to-DPI bridge.
- The old local driver wrote fixed TC358762 timing registers:
  - `HSR = 0x001a0014`
  - `HDISPR = 0x00690320`
  - `VSR = 0x00150002`
  - `VDISPR = 0x000701e0`
- Runtime `xrandr` modeline experiments changed the DSI host timing, but the TC358762 bridge timing stayed fixed. That can make the bridge and host disagree about the scanline length, which matches the observed right-edge-to-left-edge wrap.
- Raspberry Pi's newer TC358762 bridge driver stores the active DRM mode and programs the TC358762 H/V timing registers from that mode in `mode_set`/bridge initialization. We mirrored that idea in the local Raspberry panel driver while keeping ATTINY brightness support.

New patch:

```text
userpatches/kernel/rk35xx-vendor-6.1/0006-drm-panel-raspberrypi-program-tc358762-timing-from-mode.patch
```

What it does:

- keeps the working `rpi_backlight` brightness device from `0005`;
- derives TC358762 `HSR`, `HDISPR`, `VSR`, and `VDISPR` from the preferred DRM mode;
- logs the programmed timing in `dmesg`;
- adds override parameters so porch/sync timing can be tuned from boot args without another rebuild.

Default programmed timing from the preferred mode:

```text
hfp=1 hsync=2 hbp=46
vfp=7 vsync=2 vbp=21
```

Optional boot override example in `/boot/armbianEnv.txt`:

```text
extraargs=... panel_raspberrypi_touchscreen.opi3b_timing_override=1 panel_raspberrypi_touchscreen.opi3b_hfp=1 panel_raspberrypi_touchscreen.opi3b_hsync=2 panel_raspberrypi_touchscreen.opi3b_hbp=46 panel_raspberrypi_touchscreen.opi3b_vfp=7 panel_raspberrypi_touchscreen.opi3b_vsync=2 panel_raspberrypi_touchscreen.opi3b_vbp=21
```

Build validation:

```text
Patch-stack clean check: PASS
Kernel-only build: PASS
```

Build command used:

```bash
./compile.sh opi3b-vendor-bookworm-xfce-touch kernel PREFER_DOCKER=yes DOCKER_NICE=5 ARTIFACT_IGNORE_CACHE=yes
```

Produced kernel package version:

```text
6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a
```

Install these two packages on the board first:

```text
output/debs/linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
output/debs/linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

Optional matching packages:

```text
output/debs/linux-headers-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
output/debs/linux-libc-dev-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

SHA256:

```text
8835e4e6b0b6c627af497b448cb00bb248db33396a22a1805f1ff86d20d950a7  linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
4d9c5a1c90d088b9d9eb5b7a10071b6704acdaf60438c4009b3821b6edc37c8d  linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
a1a04cb76d453ed4b061afb0a6cbe1eb67c89b54fc949b1dbdbe8a06328059e7  linux-headers-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
fa9a533672f7cd1f69f21aa77f6664845eccfdbda87d366740366ebe4b86e0ba  linux-libc-dev-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pcfb6-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

Board test command after installing and rebooting:

```bash
dmesg | grep -iE 'TC358762 timing|rpi_touchscreen|dsi|drm|backlight' | tail -120
cat /sys/class/backlight/rpi_backlight/max_brightness
cat /sys/class/backlight/rpi_backlight/brightness
brightnessctl -d rpi_backlight set 30%
sleep 1
brightnessctl -d rpi_backlight set 100%
xrandr --query 2>/dev/null || true
```

Expected new log line:

```text
TC358762 timing: hfp=1 hsync=2 hbp=46 vfp=7 vsync=2 vbp=21 override=0
```

If wrap remains, test boot overrides instead of rebuilding. Add one candidate set to `extraargs`, reboot, and check the `TC358762 timing:` log line:

```text
panel_raspberrypi_touchscreen.opi3b_timing_override=1 panel_raspberrypi_touchscreen.opi3b_hfp=1 panel_raspberrypi_touchscreen.opi3b_hsync=5 panel_raspberrypi_touchscreen.opi3b_hbp=48 panel_raspberrypi_touchscreen.opi3b_vfp=7 panel_raspberrypi_touchscreen.opi3b_vsync=1 panel_raspberrypi_touchscreen.opi3b_vbp=21
```

The first boot should be tested with no override so the driver uses the preferred mode-derived timing.

## 2026-06-16 Correction: Generic Waveshare 800x480 Path

Board test result for the `0006` TC358762 timing patch:

```text
FAIL
Color wrong: blue appears green.
Right edge still wraps onto the left edge.
Brightness still works.
Artifacts remain.
```

Conclusion: `0006` was the wrong direction and has been removed from the active patch stack.

Further research showed the better match is Raspberry Pi's open `vc4-kms-dsi-waveshare-800x480` overlay, not the `raspberrypi,7inch-touchscreen-panel` video driver. The Waveshare 800x480 overlay uses:

- a generic DSI video panel;
- the MCU at I2C `0x45` only as `raspberrypi,7inch-touchscreen-panel-regulator`;
- the existing regulator driver for panel power, GPIO, and backlight;
- a separate touch node.

New test overlay:

```text
userpatches/overlay/orangepi3b-waveshare-800x480-generic.dts
output/overlay-test/orangepi3b-waveshare-800x480-generic.dtbo
```

Timing copied from Raspberry Pi's `vc4-kms-dsi-waveshare-800x480-overlay.dts`:

```text
clock-frequency = 27777000
hactive = 800
vactive = 480
hfront-porch = 59
hsync-len = 2
hback-porch = 45
vfront-porch = 7
vsync-len = 2
vback-porch = 22
```

Expected driver change with the generic overlay:

```text
Old bad path:
  rpi_touchscreen 1-0045
  panel-raspberrypi-touchscreen
  manual TC358762 register writes

New test path:
  rpi_touchscreen_attiny / raspberrypi,7inch-touchscreen-panel-regulator at 1-0045
  simple-panel-dsi under dsi1
  no panel-raspberrypi-touchscreen video driver
```

Board test result:

```text
FAIL
UART reaches U-Boot "Starting kernel" and then no further kernel output.
Treat this overlay as unsafe/non-booting.
```

The repo default was reverted to the known-booting overlay:

```text
DSI_OVERLAY_NAME=orangepi3b-waveshare-5inch-dsi-panel
```

Do not use `orangepi3b-waveshare-800x480-generic` for a default image until it is reworked and tested from a recovery-safe boot path.

## Confirmed Hardware State

- Board: Orange Pi 3B v2.1, RK3566.
- Kernel: Armbian vendor 6.1.115 RK35xx.
- GPU: Panfrost/Mali G52 path preserved.
- NPU: RKNPU driver path preserved.
- DSI LCD: boot confirmed working after the probe-cycle patch.
- Touch: confirmed working with `fts_ts` on `/dev/input/event0`; `evtest` reports `BTN_TOUCH`, `ABS_MT_POSITION_X`, and `ABS_MT_POSITION_Y` events over the 800x480 panel range.

## Root Cause

The DSI panel hardware and I2C controller were working, but the vendor 6.1 display stack hit a probe-order deadlock:

```text
dw-mipi-dsi-rockchip fe070000.dsi: failed to find panel or bridge: -517
rpi_touchscreen 1-0045: DSI host not ready, deferring panel probe
```

The cycle was:

1. Rockchip DSI host probed and registered the MIPI DSI host.
2. Rockchip display component bind immediately searched for a DRM panel.
3. The Raspberry-compatible I2C panel had not registered its DRM panel yet, so DSI bind returned `-EPROBE_DEFER`.
4. The Rockchip DSI probe unwound and unregistered the MIPI DSI host.
5. The I2C panel retried, could not find the DSI host, and deferred again.
6. The display aggregate repeatedly rebound VOP/HDMI/DSI and userspace did not become stable.

UART confirmed the panel controller answered on I2C:

```text
rpi_touchscreen 1-0045: OPi3B DSI panel probe start, i2c addr=0x45
rpi_touchscreen 1-0045: Atmel firmware revision 0xc3 detected
rpi_touchscreen 1-0045: remote DSI host node is /dsi@fe070000
```

## Important Patches

Kernel patches are in:

```text
userpatches/kernel/rk35xx-vendor-6.1/
```

Key patches:

```text
0001-drm-mipi-dsi-guard-detach-during-host-unwind.patch
0002-phy-guard-destroy-during-probe-cleanup.patch
0003-drm-panel-raspberrypi-add-opi3b-debug-and-hbp-mode.patch
0004-drm-rockchip-dsi-break-rpi-panel-probe-cycle.patch
```

`0001` prevents a crash in `mipi_dsi_detach()` during failed DSI unwind.

`0002` prevents a PHY cleanup crash when a failed DSI probe tries to destroy a PHY device whose sysfs node is already absent.

`0003` adds OPi3B-specific diagnostic logs to `panel-raspberrypi-touchscreen.c` and removes `MIPI_DSI_MODE_VIDEO_NO_HBP` so the vendor 6.1 mode flags preserve horizontal back porch timing closer to the older working vendor stack.

`0004` is the main functional fix. It:

- delays Rockchip DSI component registration for Raspberry-compatible DSI panels;
- keeps the MIPI DSI host alive long enough for the I2C panel driver to find it;
- registers the DRM panel before creating the DSI child device, because this vendor Synopsys host checks `drm_of_find_panel_or_bridge()` during DSI attach.

Expected successful log lines:

```text
Raspberry-compatible DSI panel detected; delaying component registration
OPi3B DSI panel probe start
Atmel firmware revision 0xc3 detected
DRM panel registered before DSI child registration
registered DSI child device for host attach
delayed component registration succeeded
```

## Overlay Profiles

Overlay sources are in:

```text
userpatches/overlay/
```

Important overlays:

```text
orangepi3b-waveshare-5inch-dsi-panel-no-touch.dts
orangepi3b-waveshare-5inch-dsi-panel.dts
```

`panel-no-touch` enables the display path but intentionally disables:

```text
raspits_touch_ft5426
```

`panel` uses the same display path and enables:

```text
raspits_touch_ft5426
```

Touch was later confirmed with the full `panel` overlay. `evtest` showed the touchscreen as:

```text
/dev/input/event0: fts_ts
ABS_MT_POSITION_X: 0..800
ABS_MT_POSITION_Y: 0..480
BTN_TOUCH events present
```

Confirmed touch sample:

```text
Input device name: "fts_ts"
Event code 53 (ABS_MT_POSITION_X), Min 0, Max 800
Event code 54 (ABS_MT_POSITION_Y), Min 0, Max 480
Event code 330 (BTN_TOUCH)
```

## Test Commands

Display-only test:

```bash
sudo op3b-dsi-try panel-no-touch
sync
sudo reboot
```

Full panel plus touch test:

```bash
sudo op3b-dsi-try panel
sync
sudo reboot
```

After boot, check touch input:

```bash
op3b-dsi-status
dmesg | grep -iE 'ft54|touch|edt|goodix|input|rasp|panel|dsi' | tail -200
ls -l /dev/input/by-path /dev/input/by-id 2>/dev/null
cat /proc/bus/input/devices | grep -iA8 -B2 'touch\|ft54\|rasp'
```

If `evtest` is installed:

```bash
sudo evtest
```

Select the touchscreen event device, touch the LCD, and confirm events are printed.

If `evtest` is missing:

```bash
sudo apt update
sudo apt install -y evtest
sudo evtest
```

## Full Hardware Validation

After the DSI LCD and touch are confirmed, run this read-only report on the board to validate the rest of the image before publishing:

```bash
cat > /tmp/op3b-final-validate.sh <<'EOF'
#!/usr/bin/env bash
set +e

section() { printf '\n\n===== %s =====\n' "$*"; }
run() {
	printf '\n$ %s\n' "$*"
	timeout 25s bash -lc "$*" 2>&1 || printf '[exit %s]\n' "$?"
}
have() { command -v "$1" >/dev/null 2>&1; }

section "Board / Boot"
run 'date -Is'
run 'tr -d "\0" </proc/device-tree/model 2>/dev/null || true'
run 'uname -a'
run 'cat /boot/armbianEnv.txt'
run 'uptime'
run 'free -h'

section "Display / DSI / Touch"
run 'op3b-dsi-status 2>/dev/null || true'
run 'ls -la /sys/class/drm/ /dev/dri/ 2>/dev/null || true'
run 'for s in /sys/class/drm/card*-*/status; do [ -e "$s" ] && printf "%s: " "$s" && cat "$s"; done'
run 'cat /proc/bus/input/devices | grep -iA10 -B3 "fts\|touch\|ft54\|rasp" || true'
run 'ls -la /dev/input/by-path /dev/input/by-id 2>/dev/null || true'

section "GPU / Panfrost / Mesa"
run 'for x in /sys/class/drm/card* /sys/class/drm/renderD*; do [ -e "$x/device/uevent" ] || continue; echo "=== $x ==="; readlink -f "$x/device"; grep -E "DRIVER|OF_NAME|OF_FULLNAME|MODALIAS" "$x/device/uevent"; done'
run 'dmesg | grep -iE "panfrost|mali|gpu" | tail -80 || true'
if have glxinfo; then run 'DISPLAY=${DISPLAY:-:0} glxinfo -B'; else echo 'MISSING: glxinfo'; fi
if have es2_info; then run 'DISPLAY=${DISPLAY:-:0} es2_info'; else echo 'MISSING: es2_info'; fi
if have eglinfo; then run 'eglinfo --display surfaceless | head -120'; else echo 'MISSING: eglinfo'; fi
if have vulkaninfo; then run 'vulkaninfo --summary'; else echo 'MISSING: vulkaninfo'; fi

section "NPU / RKNPU"
run 'ls -la /dev/rknpu* /dev/dri/renderD* 2>/dev/null || true'
run 'for x in /sys/class/drm/card* /sys/class/drm/renderD*; do [ -e "$x/device/uevent" ] || continue; grep -q "DRIVER=RKNPU" "$x/device/uevent" && { echo "=== RKNPU node: $x ==="; readlink -f "$x/device"; cat "$x/device/uevent"; }; done'
run 'dmesg | grep -iE "rknpu|npu" | tail -120 || true'
if [ -x "$HOME/rknn-venv/bin/python" ]; then
	run '"$HOME/rknn-venv/bin/python" - <<PY
from rknnlite.api import RKNNLite
print("RKNNLite import OK from venv")
PY'
elif python3 -c 'import rknnlite' >/dev/null 2>&1; then
	run 'python3 - <<PY
from rknnlite.api import RKNNLite
print("RKNNLite import OK from system python")
PY'
else
	echo 'MISSING: RKNNLite python package not installed in system python or ~/rknn-venv'
fi

section "Wi-Fi / Network"
run 'nmcli dev 2>/dev/null || true'
run 'ip -br addr'
run 'ip route'
run 'iw dev 2>/dev/null || true'
run 'iw dev wlan0 link 2>/dev/null || true'
run 'rfkill list 2>/dev/null || true'
run 'ping -c 3 -W 2 1.1.1.1'
run 'getent hosts github.com'

section "Bluetooth"
run 'systemctl is-enabled bluetooth 2>/dev/null; systemctl is-active bluetooth 2>/dev/null; systemctl status bluetooth --no-pager -l 2>/dev/null | sed -n "1,40p"'
run 'rfkill list bluetooth 2>/dev/null || true'
run 'bluetoothctl list 2>/dev/null || true'
run 'bluetoothctl show 2>/dev/null || true'
run 'hciconfig -a 2>/dev/null || true'
run 'dmesg | grep -iE "bluetooth|btusb|hci|brcm|uart" | tail -120 || true'

section "Ethernet / PCIe / USB"
run 'ip -br link | grep -E "end|eth|enp|wlan|lo" || true'
run 'ethtool end1 2>/dev/null || ethtool end0 2>/dev/null || ethtool eth0 2>/dev/null || true'
run 'lspci -nn 2>/dev/null || true'
run 'lsusb 2>/dev/null || true'

section "Storage / Filesystem"
run 'lsblk -o NAME,MAJ:MIN,SIZE,RO,TYPE,FSTYPE,MOUNTPOINTS'
run 'df -hT'
run 'mount | grep -E " / |/boot|zram|overlay"'

section "CPU / Thermal / Governors"
run 'for z in /sys/class/thermal/thermal_zone*; do [ -e "$z/temp" ] || continue; printf "%s " "$z"; cat "$z/type" 2>/dev/null; awk "{printf \"temp=%.1fC\\n\", \\$1/1000}" "$z/temp"; done'
run 'for c in /sys/devices/system/cpu/cpu[0-9]*; do [ -e "$c/cpufreq/scaling_cur_freq" ] || continue; printf "%s " "${c##*/}"; cat "$c/cpufreq/scaling_governor" "$c/cpufreq/scaling_cur_freq" "$c/cpufreq/cpuinfo_max_freq" 2>/dev/null | paste -sd " " -; done'
run 'cat /proc/cpuinfo | grep -E "processor|Hardware|Revision|Serial|model name"'

section "Video / Media"
run 'ls -la /dev/video* /dev/media* /dev/mpp_service 2>/dev/null || true'
if have v4l2-ctl; then run 'v4l2-ctl --list-devices'; else echo 'MISSING: v4l2-ctl'; fi
if have vainfo; then run 'DISPLAY=${DISPLAY:-:0} vainfo'; else echo 'MISSING: vainfo'; fi
run 'dmesg | grep -iE "rkvdec|rkvenc|hantro|mpp|vpu|vdec|venc" | tail -120 || true'

section "Serious Kernel/System Errors"
run 'journalctl -p 0..3 -b --no-pager | tail -250'
run 'dmesg | grep -iE "panic|oops|BUG:|call trace|segfault|hung task|rcu stall|watchdog|failed|error" | tail -250 || true'

section "Summary Hints"
echo "PASS signs: fts_ts input, panfrost DRM node, RKNPU DRM node, Wi-Fi connected, Bluetooth controller listed, no panic/oops/call trace."
echo "Optional failures: glxinfo/vainfo may fail without a running display session; vulkaninfo may fail if this Mesa build has no Panfrost Vulkan."
EOF
chmod +x /tmp/op3b-final-validate.sh
/tmp/op3b-final-validate.sh 2>&1 | tee ~/op3b-final-validation-$(date +%Y%m%d-%H%M%S).log
```

## Validation Result, 2026-06-15

Board booted successfully with the DSI panel path active.

Confirmed:

- DSI connector: `/sys/class/drm/card1-DSI-1` is `connected`.
- HDMI connector: `/sys/class/drm/card1-HDMI-A-1` is `disconnected`.
- Display mode: VOP enabled `800x480p60` on MIPI DSI.
- Touch: `fts_ts` registered on I2C address `0x38` and exported `/dev/input/event0`.
- DSI panel controller: `rpi_touchscreen 1-0045` answered with Atmel firmware revision `0xc3`.
- DSI probe-cycle fix active: log shows `Raspberry-compatible DSI panel detected; delaying component registration`, `DRM panel registered before DSI child registration`, and `delayed component registration succeeded`.
- GPU kernel path: Panfrost bound to `fde60000.gpu`, exposed `/dev/dri/renderD130`, and initialized as `mali-g52`.
- GPU userspace path: surfaceless EGL reports Mesa Panfrost. `glxinfo -B` failed only because there was no open X display as root.
- Vulkan: not available in this Mesa stack; `vulkaninfo` reports no Vulkan driver. This is expected for this Panfrost/Mesa package set and is not required for OpenGL ES acceleration.
- NPU kernel path: RKNPU bound to `fde40000.npu`, exposed `/dev/dri/renderD128`, and initialized as `rknpu 0.9.8`.
- Bluetooth: `hci0` is up over UART, Broadcom BCM4345C5 firmware loaded, `bluetooth.service` active, and `bluetoothctl show` reports a controller.
- Storage: root filesystem mounted from `mmcblk1p1`, 29G ext4, about 7% used.
- Thermal: SoC and GPU around 31 C at idle.
- CPU governor: all four cores set to `performance`, current and max frequency `1800000`.
- Media service: `/dev/mpp_service` present for Rockchip MPP.

Remaining validation gaps:

- Wi-Fi was present but disconnected/down in the captured boot. This needs a connection test with a configured SSID.
- RKNNLite Python package was not installed in the tested root environment, so only the kernel RKNPU node was validated. Install `rknn-toolkit-lite2` or use a venv, then run an RKNN model test.
- V4L2 `/dev/video0` was not present. This is not a DSI/GPU/NPU blocker; Rockchip MPP exposes `/dev/mpp_service` instead.

Known vendor-kernel log noise still present:

- Proprietary `mali` probe fails first, then open-source `panfrost` binds successfully.
- `RKNPU ... IRQ npu_irq not found` appears, but the DRM RKNPU device still initializes.
- Missing regulator/leakage/SCMI messages are inherited from the vendor DT/kernel combination.
- PCIe reports link failure when no PCIe endpoint is attached.
- Bluetooth VCP/MCP/BAP plugin warnings are BlueZ optional-profile noise with experimental features disabled.

## XFCE Touch Desktop Build, 2026-06-15

Recommended desktop for this board/panel is XFCE minimal with touch-specific tuning. GNOME and KDE/Plasma are more touch-oriented in general, but they are heavier and a poor fit for RK3566 plus an 800x480 5-inch panel. XFCE gives the best balance of speed, visual polish, and low-risk X11/Panfrost behavior.

Build profile:

```text
userpatches/config-opi3b-vendor-bookworm-xfce-touch.conf.sh
build-opi3b-vendor-bookworm-xfce-touch.sh
```

Built image:

```text
output/images/Armbian-unofficial_26.05.0-trunk_Orangepi3b_bookworm_vendor_6.1.115_xfce-opi3b21-fast-xfce-touch-dsi_desktop.img
```

SHA256:

```text
4c802e87c4d4b9590bad0c15b0d09e5fa1c74dc53a754139658ffa378d9e5382
```

Image checks:

```text
sha256sum -c: OK
MBR signature: 55aa
GPT marker at byte 512: 0000000000000000
Disklabel type: dos
Root partition: start sector 32768, size 4.3G, type 83 Linux
```

Desktop tuning added by `OPI3B_TOUCH_DESKTOP_TWEAKS=yes`:

- XFCE minimal desktop tier.
- Performance CPU governor.
- DSI panel overlay enabled by default with `orangepi3b-waveshare-5inch-dsi-panel`.
- XFCE compositor disabled to reduce GPU/display latency.
- Larger 40px XFCE panel and 110 DPI defaults for the 800x480 panel.
- Arc-Dark theme, Papirus-Dark icons, and Noto fonts.
- Onboard virtual keyboard installed and autostarted for new users.
- NetworkManager GUI, Blueman, audio control, Mesa/EGL tools, V4L2 tools, sensor tools, Python venv/pip/numpy, and hardware debug utilities included.

Build result:

```text
Build completed successfully.
Runtime: 15:37 min
Log: output/logs/log-build-no-uuidgen-yet-22855-7435.log.ans
```

## If It Fails Again

Use UART if possible and capture these filtered logs:

```bash
dmesg | grep -iE 'OPi3B DSI|Atmel|delayed component|DSI device registration|failed to attach|panel|bridge|dsi|drm|vop|touch|ft54|input' | tail -300
sudo cat /sys/kernel/debug/devices_deferred 2>/dev/null || true
ls -la /sys/class/drm/
cat /boot/armbianEnv.txt
```

Important failure patterns:

```text
DSI host not ready, deferring panel probe
failed to find panel or bridge: -517
DSI device registration failed
failed to attach dsi to host
delayed component registration failed
```

## Build Command

From this directory:

```bash
./build-opi3b-vendor-bookworm-cli-debug.sh
```

## XFCE Touch Regression, 2026-06-15

The first XFCE touch desktop image booted the DSI panel, but the touch input device was missing. Runtime evidence:

```text
/sys/class/drm/card1-DSI-1/status: connected
rpi_touchscreen 1-0045: OPi3B DSI panel probe start
rpi_touchscreen 1-0045: Atmel firmware revision 0xc3 detected
rpi_touchscreen 1-0045: registered DSI child device for host attach
```

Missing runtime evidence:

```text
i2c 1-0038
raspits-ft5426
input: fts_ts
/dev/input/by-path/...1-0038...
```

This means the panel controller was working, but the kernel touch driver was not present. The board DTS already has `raspits_touch_ft5426` at I2C address `0x38`, and the DSI panel overlay enables it, so this was not an X11 calibration or desktop mapping issue.

Fix applied to `userpatches/config-opi3b-vendor-bookworm-xfce-touch.conf.sh`: add a `custom_kernel_config__opi3b_dsi_panel_touch_builtin` hook that forces these options built in:

```text
CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y
CONFIG_TOUCHSCREEN_RASPITS_FT5426=y
```

After rebuilding/flashing the desktop image, expected touch validation:

```bash
dmesg | grep -iE 'raspits|fts|ft54|1-0038|touch' | tail -120
cat /proc/bus/input/devices | grep -iA12 -B3 'fts_ts'
ls -la /dev/input/by-path | grep -i '0038\|i2c'
sudo evtest
```

Rebuilt XFCE desktop image with the touch driver enabled:

```text
output/images/Armbian-unofficial_26.05.0-trunk_Orangepi3b_bookworm_vendor_6.1.115_xfce-opi3b21-fast-xfce-touch-dsi_desktop.img
```

SHA256:

```text
0e59f744b2ed197de6a95e8613e36dbd1a86b11f0d82fc717fb3b4d8da2e2e2c
```

Build checks:

```text
sha256sum -c: OK
CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y
CONFIG_TOUCHSCREEN_RASPITS_FT5426=y
MBR signature: 55aa
GPT marker at byte 512: 0000000000000000
MBR partition 1: type 83, start sector 32768, size 9043968 sectors
Build log: output/logs/log-build-no-uuidgen-yet-32008-810910.log.ans
Runtime: 14:15 min
```

## XFCE Touch Mapping, 2026-06-16

After enabling `CONFIG_TOUCHSCREEN_RASPITS_FT5426=y`, the `fts_ts` input device appears and emits events, but X11 may still map the touch coordinates incorrectly. Symptom: tapping the panel makes the cursor appear or jump, but not under the finger.

This is an X/libinput mapping or calibration problem, not the DSI panel driver failing. The image customization now installs:

```text
/etc/X11/xorg.conf.d/40-opi3b-ft5426-touch.conf
/usr/local/bin/op3b-touch-map
/etc/skel/.config/autostart/op3b-touch-map.desktop
```

`op3b-touch-map` maps `fts_ts` to the connected DSI output and can test these coordinate modes:

```text
normal
invert-x
invert-y
rotate-180
swap
rotate-cw
rotate-ccw
```

Runtime test order on the board:

```bash
op3b-touch-map normal
op3b-touch-map invert-x
op3b-touch-map invert-y
op3b-touch-map rotate-180
op3b-touch-map swap
op3b-touch-map rotate-cw
op3b-touch-map rotate-ccw
```

Whichever mode puts touches under the finger should become the autostart mode.

## DSI Horizontal Artifact Investigation, 2026-06-16

Observed artifact: horizontal corruption appears on the same scanline as changed high-contrast UI content. Initially it followed the cursor, but hiding the cursor removed only the cursor-related trigger; taskbar icon updates can still trigger a similar line.

Runtime tests performed on the board:

```text
Full ShadowFB/software Xorg path
No GLAMOR
No pageflip
No hardware cursor plane
Panfrost unbound from fde60000.gpu
Only Smart0 primary plane active
```

Results:

```text
Cursor flicker improved with software/hidden cursor.
The horizontal artifact itself remained.
Unbinding Panfrost did not change the artifact.
Pixel-clock/timing changes affected artifact severity:
  30.000 MHz was least bad.
  33.333 MHz black-screened.
  36.000 MHz was worst.
```

Conclusion: this is not normal Panfrost rendering corruption and not only the hardware cursor plane. It is more likely in the RK3566 VOP2 -> DSI bridge/panel link path, especially DSI video mode/timing.

Research notes:

```text
Waveshare 5-inch 800x480 panel behaves like the Raspberry Pi 7-inch compatible ATTINY/TC358762 path.
Waveshare's newer "5inch DSI LCD C/D" path is 720x1280 and is not this panel.
Waveshare's closed module repo hides much of the panel init in WS_xinchDSI_Screen.ko, so it is not directly reusable.
Upstream Linux panel-raspberrypi-touchscreen.c uses MIPI_DSI_MODE_VIDEO_SYNC_PULSE for this panel family.
Our vendor-6.1 patched panel driver was still using MIPI_DSI_MODE_VIDEO_BURST.
```

Patch update: `0003-drm-panel-raspberrypi-add-opi3b-debug-and-hbp-mode.patch` now switches the DSI child from burst video to sync-pulse video:

```text
- MIPI_DSI_MODE_VIDEO_BURST
+ MIPI_DSI_MODE_VIDEO_SYNC_PULSE
```

The same patch now also adds a local OPi3B/Waveshare preferred mode:

```text
800x480, 30.000 MHz
H: 800 859 861 906
V: 480 487 489 511
```

The original 26.000 MHz Raspberry firmware timing remains as a fallback mode. This requires a kernel/image rebuild; the DSI video mode flag cannot be changed with `xrandr` at runtime.

## Remaining Boot Log Cleanup Plan, 2026-06-16

The remaining notes were reviewed after final validation. The image should fix the entries that are real runtime/config issues and leave harmless vendor DT/kernel noise alone.

Changes now baked into the build profile:

```text
CONFIG_TOUCHSCREEN_RASPITS_FT5426=y
CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y
CONFIG_DRM_PANFROST=m
CONFIG_MALI_MIDGARD=n
CONFIG_MALI_BIFROST=n
```

Reasoning:

```text
Panfrost is the working GPU path.
The vendor Mali driver probes first, logs IRQ/register failures, then Panfrost binds.
Disabling the vendor Mali Midgard/Bifrost path should remove that noisy failed probe while preserving Panfrost.
```

Changes now baked into the XFCE touch image rootfs:

```text
/etc/X11/xorg.conf.d/20-op3b-modesetting.conf
  modesetting driver
  SWCursor=true
  PageFlip=false

/etc/X11/xorg.conf.d/40-opi3b-ft5426-touch.conf
  libinput match for fts_ts
  identity calibration matrix

/usr/local/bin/op3b-touch-fix
/usr/local/bin/op3b-touch-map -> op3b-touch-fix
/usr/local/sbin/op3b-touch-display-setup
/etc/lightdm/lightdm.conf.d/99-op3b-touch.conf
```

The final DSI overlay now disables the unused eDP/PWM-backlight path when the Waveshare/Raspberry-compatible DSI panel is enabled:

```text
orangepi3b-waveshare-5inch-dsi-panel.dts
  pwm2 = disabled
  /backlight = disabled
  /edp-panel = disabled
```

Expected improvements:

```text
No vendor Mali probe failure before Panfrost.
Vendor Mali modules are also blacklisted in /etc/modprobe.d as a fallback.
Touch helper present for LightDM and user session.
Narrow Xorg display workaround present from first boot.
Less deferred-probe noise from unused eDP/backlight nodes.
DSI transport switched from burst video to sync-pulse video for artifact testing.
DSI preferred mode uses the least-bad tested 30 MHz clock instead of 26 MHz.
The RK35xx boot script no longer calls missing kaslrseed, avoiding that U-Boot error.
```

Post-build patch hygiene:

```text
The generated image was built successfully after the functional changes above.
Afterward, patch hunk headers were refreshed so a future rebuild applies the
same code without Armbian reporting offset-based needs_rebase warnings.
```

Not fixed intentionally:

```text
PCIe link fail if no endpoint/NVMe is attached: keeping PCIe enabled preserves board functionality.
SCMI protocol warnings: firmware does not expose those protocols.
Dummy regulator messages: vendor DT omits some supply descriptions but hardware works.
RK817 battery/charger warnings: PMIC subdrivers probe despite no battery path.
MMC tuning warning: only actionable if SD I/O errors occur.
Audio UCM/routing warnings: only worth tuning if audio routing is a product requirement.
FIQ debugger warnings: vendor debug feature noise.
Reserved DRM logo/LUT loader-memory warnings: vendor boot-logo path noise.
RKNPU early resource/IRQ warnings: leave unless RKNN runtime actually fails.
```

## Performance-Only Mitigation Policy, 2026-06-16

The XFCE touch image profile is now intentionally performance-first. The build
adds these kernel command-line arguments to `/boot/armbianEnv.txt`:

```text
mitigations=off kpti=0 nospectre_v2 nospectre_bhb ssbd=force-off arm64.nobti audit=0 nokaslr apparmor=0 selinux=0 init_on_alloc=0 init_on_free=0 page_alloc.shuffle=0
```

Intent:

```text
Disable broad Linux CPU vulnerability mitigations.
Explicitly disable ARM64 KPTI, Spectre v2, Spectre-BHB, SSBD, and BTI paths.
Disable kernel audit logging.
Disable kernel address layout randomization.
Disable AppArmor and SELinux at boot.
Disable default page/object zeroing hardening and page allocator randomization.
Keep cma=256M from the rk35xx default boot environment.
```

The profile also requests these performance/security-tradeoff kernel config
settings where supported by the vendor tree:

```text
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
CONFIG_CC_OPTIMIZE_FOR_SIZE=n
CONFIG_RANDOMIZE_BASE=n
CONFIG_SECURITY_SELINUX=n
CONFIG_SECURITY_APPARMOR=n
CONFIG_HARDENED_USERCOPY=n
CONFIG_INIT_ON_ALLOC_DEFAULT_ON=n
CONFIG_INIT_ON_FREE_DEFAULT_ON=n
CONFIG_SHUFFLE_PAGE_ALLOCATOR=n
```

This is only appropriate for a trusted, single-purpose, performance-focused
image. It knowingly weakens security isolation against CPU side-channel classes
and reduces security/event auditing.

Rollback:

```bash
sudo sed -i 's/ mitigations=off//; s/ kpti=0//; s/ nospectre_v2//; s/ nospectre_bhb//; s/ ssbd=force-off//; s/ arm64.nobti//; s/ audit=0//; s/ nokaslr//; s/ apparmor=0//; s/ selinux=0//; s/ init_on_alloc=0//; s/ init_on_free=0//; s/ page_alloc.shuffle=0//' /boot/armbianEnv.txt
sudo reboot
```

Validation after boot:

```bash
cat /proc/cmdline
grep . /sys/devices/system/cpu/vulnerabilities/* 2>/dev/null || true
```

Expected result:

```text
/proc/cmdline contains the performance-only mitigation-disabling args.
CPU vulnerability files may report Vulnerable, Mitigation disabled, or Not affected.
For this image, Vulnerable/Mitigation disabled is expected, not a bug.
```

## LCD Brightness Control, 2026-06-16

The Waveshare/Raspberry-compatible DSI LCD brightness is not controlled by the
Orange Pi board PWM backlight node. That node is disabled in the final DSI
overlay because it is unused by this panel path and previously caused deferred
probe noise.

The active brightness control is the ATTINY/MCU PWM register inside the
`panel-raspberrypi-touchscreen` driver:

```text
I2C panel MCU: 0x45
PWM register: REG_PWM
Range: 0..255
```

Patch added:

```text
0005-drm-panel-raspberrypi-expose-attiny-backlight.patch
```

Expected sysfs after booting an image built with this patch:

```text
/sys/class/backlight/rpi_backlight/brightness
/sys/class/backlight/rpi_backlight/max_brightness
```

Validation:

```bash
ls -la /sys/class/backlight/
cat /sys/class/backlight/rpi_backlight/max_brightness
cat /sys/class/backlight/rpi_backlight/brightness
echo 80 | sudo tee /sys/class/backlight/rpi_backlight/brightness
echo 255 | sudo tee /sys/class/backlight/rpi_backlight/brightness
brightnessctl -l
brightnessctl -d rpi_backlight set 50%
```

Do not use the old `/sys/class/backlight/backlight` PWM path for this panel.
If direct I2C writes are used for emergency testing, they should be treated as
a workaround only because the kernel owns the I2C client.

## Generic Waveshare 800x480 Overlay Rejected, 2026-06-16

The attempted generic port of Raspberry Pi's
`vc4-kms-dsi-waveshare-800x480` style overlay was tested as:

```text
orangepi3b-waveshare-800x480-generic
```

Result:

```text
U-Boot reaches "Starting kernel ..."
No further normal Linux boot output
No SSH/display recovery
```

This is a hard DT/early-kernel failure, not a normal panel timing failure.
The overlay was removed from `userpatches/overlay` and must not be shipped as a
default or selectable recovery profile until it is redesigned and tested from a
non-default SD-card recovery flow.

Recovery for a card that was left on this overlay:

```text
/boot/armbianEnv.txt
```

Replace:

```text
user_overlays=orangepi3b-waveshare-800x480-generic
```

with the known-booting panel overlay:

```text
user_overlays=orangepi3b-waveshare-5inch-dsi-panel
```

or with the no-display recovery overlay:

```text
user_overlays=orangepi3b-debug-noop
```

The clean replacement kernel/DTB build after removing the bad TC358762 timing
patch completed successfully:

```text
linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-P0289-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-P0289-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

This build keeps:

```text
0005-drm-panel-raspberrypi-expose-attiny-backlight.patch
orangepi3b-waveshare-5inch-dsi-panel
```

and does not include the rejected `0006` timing-register patch.

## Brightness Sequencing Test Build, 2026-06-16

After the board recovered to the known-booting overlay, `0005` was adjusted to
keep the runtime `/sys/class/backlight/rpi_backlight` device but restore the old
panel prepare behavior:

```text
prepare(): write ATTINY REG_PWM=255 directly
runtime brightness: use rpi_backlight sysfs device
```

Reason: the display was normal before brightness support, and the first
brightness patch changed panel prepare from a direct `REG_PWM=255` write to
`backlight_update_status()`. This test isolates boot-time brightness sequencing
without reintroducing the rejected TC358762 timing patch.

Test kernel/DTB build:

```text
linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-P4d8a-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-P4d8a-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

Expected test:

```text
1. Boot with user_overlays=orangepi3b-waveshare-5inch-dsi-panel.
2. Confirm LCD geometry/color/artifact state immediately after boot.
3. Confirm /sys/class/backlight/rpi_backlight exists.
4. Change brightness from sysfs or desktop slider.
5. Check whether wrap/artifacts appear only after runtime brightness changes.
```

## Bad-State Log And DSI Mode Revert Test, 2026-06-16

Bad-state log from `P4d8a` showed:

```text
user_overlays=orangepi3b-waveshare-5inch-dsi-panel
DSI-1 connected
current mode: 800x480 25.979 MHz
H: 800 801 803 849
V: 480 487 489 510
backlight actual_brightness=255
backlight brightness=0
```

The LCD still showed wrong color and right-edge-to-left-edge horizontal wrap.
That ruled out boot-time `backlight_update_status()` as the direct cause.

Next test changed `0003` to diagnostics-only:

```text
userpatches/kernel/rk35xx-vendor-6.1/0003-drm-panel-raspberrypi-add-opi3b-diagnostics.patch
```

Removed from `0003`:

```text
25.979 MHz preferred mode
MIPI_DSI_MODE_VIDEO_SYNC_PULSE
removal of MIPI_DSI_MODE_VIDEO_NO_HBP
```

Kept:

```text
probe diagnostics
0004 delayed DSI component/probe-cycle fix
0005 rpi_backlight support
```

Test kernel/DTB build:

```text
linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pa59c-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pa59c-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

Expected comparison:

```text
If Pa59c restores correct color/position, the culprit was the DSI mode/flag
experiment in the earlier 0003, not brightness support.

If Pa59c is still wrong, compare it against the older P9c90 package because
the remaining difference is likely 0005 brightness registration or a userspace
desktop/display-manager interaction.
```

Pa59c board result:

```text
Color: correct
Horizontal right-to-left offset/wrap: gone
Brightness: still works
Remaining issue: artifacts around dynamic content such as cursor, dropdowns,
taskbar icons, and other frequently repainted UI regions
```

Conclusion:

```text
Keep Pa59c display mode/flags as the current good baseline.
Do not reintroduce the 25.979 MHz + sync-pulse timing experiment.
Investigate remaining artifacts separately as a composition/scanout/update-path
issue rather than a backlight or basic panel-timing issue.
```

## Dynamic-Content Artifact Follow-Up, 2026-06-16

Observed on the good Pa59c baseline:

```text
Color: correct
Horizontal offset/wrap: gone
Brightness: works through rpi_backlight
Remaining artifact: dynamic UI regions such as cursor, dropdowns, taskbar icons,
and dragged windows
Important clue: artifact disappears when the moving/changing object touches the
far-left screen border (x=0)
```

This points away from Waveshare panel timing and away from Panfrost itself:

```text
Unbinding/disabling Panfrost did not remove the artifact.
ShadowFB/software Xorg path reduced cursor-specific flicker but did not remove
the underlying line/artifact.
The x=0 behavior suggests a scanout memory/update/stride/plane issue, especially
CPU-updated dumb framebuffer or VOP2 primary plane handling.
```

Search/research note:

```text
Rockchip VOP2 has RK3566-specific mirror-window limitations and vendor driver
logic around mirror windows and plane assignment. That is relevant to VOP2
artifacts, but the current runtime log shows only Smart0 as the primary plane,
so the first narrow test is memory backing for dumb buffers rather than changing
plane assignment.
```

References:

```text
https://lists.infradead.org/pipermail/linux-rockchip/2025-January/054364.html
https://lists.freedesktop.org/archives/dri-devel/2022-April/349047.html
https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c
```

Kernel-only test build:

```text
Patch: userpatches/kernel/rk35xx-vendor-6.1/0006-drm-rockchip-force-dumb-buffers-contiguous.patch
Purpose: force rockchip_gem_dumb_create() buffers through ROCKCHIP_BO_CONTIG
without changing DSI mode, panel init, or backlight behavior.

linux-image-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pfded-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
linux-dtb-vendor-rk35xx_26.05.0-trunk_arm64__6.1.115-S95e8-Dd76a-Pfded-C7298-Hbd43-HK01ba-Vc222-B4497-R448a.deb
```

Interpretation:

```text
If Pfded removes or changes the artifact, continue investigating Rockchip
GEM/cache/IOMMU/shmem scanout.

If Pfded is unchanged, remove 0006 and continue with VOP2 primary plane /
linebuffer / damage-update behavior.
```

Pfded board result:

```text
Artifact: unchanged
Conclusion: contiguous dumb buffers are not enough to fix the dynamic-content
artifact.
Action: removed 0006-drm-rockchip-force-dumb-buffers-contiguous.patch from the
active patch stack. Continue with VOP2 primary plane / linebuffer / scanout
state debugging.
```

## Deep DRM Snapshot Result, 2026-06-16

Snapshot archives copied to:

```text
debug-snapshots/op3b-drm-deep-artifact-20260616-090940.tar.gz
debug-snapshots/op3b-drm-deep-left-edge-clean-20260616-090952.tar.gz
```

Visible-artifact and left-edge-clean snapshots showed no meaningful DRM state
change. The visual difference is from the framebuffer contents/update pattern,
not from a live connector/mode/plane switch.

Relevant state:

```text
DRM display device: /dev/dri/card1, debugfs dri/1 and dri/129
Connector: DSI-1 connected/enabled
HDMI: disconnected
Mode: 800x480p60
dclk: 26000 kHz
Timing: H 800 801 806 854, V 480 487 488 509
Active plane: Smart0-win0 only
Framebuffer: Xorg, XR24, 800x480, pitch 3200, offset 0
Plane source/destination: full screen 800x480+0+0
Cursor/overlay planes: inactive
```

Xorg state:

```text
Driver: modesetting
Options active: AccelMethod none, ShadowFB true, PageFlip false, SWcursor true
glamor: disabled
hardware cursor: disabled
Damage tracking: initialized
```

Conclusion:

```text
This is not Panfrost, glamor, pageflip, hardware cursor, or overlay plane
composition in the current test state. The next no-rebuild isolation test is to
switch Xorg from modesetting to fbdev on /dev/fb0. If fbdev fixes it, bake fbdev
or a full-frame update workaround into the desktop image. If fbdev still shows
it, continue in the kernel VOP2/DSI scanout path.
```

Fbdev runtime test result:

```text
Changing Xorg to Driver "fbdev" with /dev/fb0 produced a black screen with a
blinking cursor. Xorg loaded fbdev and used /dev/fb0, but also loaded modesetting
as GPU screen and terminated with Fatal server error.

Conclusion: simple fbdev config is not a usable workaround as tested. Restore
the modesetting config before continuing. If testing fbdev again, capture the
full Xorg.0.log and try an AutoAddGPU=false server layout to prevent the
modesetting GPU screen from being attached.
```

fbdev board result:

```text
After switching Xorg to fbdev on /dev/fb0, the LCD showed only a blinking cursor
on a black screen.
Conclusion: fbdev is not a usable workaround on this image. Revert to the
known-good modesetting configuration and continue with the modesetting/KMS
update path or kernel VOP2 scanout path.
```

Further Xorg runtime tests:

```text
ShadowFB=false:
  Result: artifact worse.
  Interpretation: direct CPU writes into the KMS framebuffer are worse than
  shadow-buffer copies.

ShadowFB=true + DoubleShadow=true:
  Xorg confirmed "Double-buffered shadow updates: on".
  Result: artifact unchanged.
  Interpretation: double shadow does not fix the damaged/dynamic-region
  corruption.

Current best Xorg baseline:
  Driver modesetting
  AccelMethod none
  ShadowFB true
  PageFlip false
  SWcursor true
  DoubleShadow unset/false
```

## VP0 Primary Plane Overlay Correction, 2026-06-16

The first Esmart0 overlay test used:

```text
rockchip,plane-mask = <0x04>
rockchip,primary-plane = <2>
```

The live DT showed those properties, but DRM still reported:

```text
Smart0-win0: ACTIVE
```

Reason found in `rockchip_drm_vop2.c`:

```text
vop2_plane_mask_check() rejects incomplete plane masks on RK356x/RK3588-class
VOP2. The driver then runs vop2_plane_mask_assign() and restores the default
assignment, which selects Smart0.
```

Correct diagnostic overlay:

```text
rockchip,plane-mask = <0x3f>   # keep all RK3566 windows assigned
rockchip,primary-plane = <2>   # Esmart0
```

Fallback Cluster0 diagnostic:

```text
rockchip,plane-mask = <0x3f>
rockchip,primary-plane = <0>
```

Esmart0 full-mask board result:

```text
user_overlays=orangepi3b-waveshare-5inch-dsi-panel orangepi3b-vp0-primary-esmart0-fullmask
Live DT: plane-mask = 0x3f, primary-plane = 2
dmesg: vp0 primary plane phy id: Esmart0[2]
DRM summary: Esmart0-win0: ACTIVE
Artifact: still present
Conclusion: artifact is not specific to Smart0. Continue with Cluster0 as the
last useful window-selection isolation test. If Cluster0 also shows the
artifact, continue below VOP2 window fetch: VP0/post-processing/DSI bridge/link
or userspace full-frame redraw workaround.
```

## Artifact Isolation Updates, 2026-06-16

Panfrost boot-level disable test:

```text
panfrost blacklisted at boot
lsmod: panfrost not loaded
DRM nodes: rknpu + display-subsystem only, no GPU card
Artifact: unchanged
Conclusion: artifact is not caused by Panfrost.
```

fbdev-only Xorg test:

```text
Config: Driver "fbdev", /dev/fb0, AutoAddGPU=false, explicit Screen/Layout
Result: black screen with blinking white cursor
Conclusion: fbdev Xorg is not a practical workaround on this image. Restore
modesetting + ShadowFB baseline.
```

Current display conclusion:

```text
The artifact is not tied to Panfrost, not Smart0-specific, and not fixed by
Xorg shadow-buffer options. It appears in the userspace desktop scanout/update
path through Rockchip DRM/KMS on DSI, while boot animation remains clean.
Next serious fix path is kernel/display-driver research around RK3566 VOP2/DSI
scanout/update behavior, or a userspace compositor/full-frame redraw workaround.
```
