# Lenovo Elden sensor integration

Services, udev rules, scripts and configuration for starting `lenovo-elden-sensors` on Armbian.
Programs and private libraries reside in `/usr/share/lenovo-elden-sensors`.

## Services

- `lenovo-elden-sensors-init.service`: runs the initialization script once, then remains active without a background process.
  It prepares runtime mappings and writable registry state under `/var/lib/hexagonrpc`.
  It prefers device calibration and warns when using the bundled fallback. Existing DSP state survives reboots.
  When the calibration directory is absent or empty, it waits up to 10 seconds
  for the persist block device before attempting extraction. If the device does
  not appear, initialization continues with the existing state selection and fallback logic.
  Input template changes create a new registry generation; DSP writes to the working
  state do not trigger replacement. A valid working copy without a recorded template
  digest is retained and the current template is recorded as its comparison baseline.
  Persist extraction uses temporary storage that is removed on exit; the latest
  failed extraction log is retained as `/var/lib/hexagonrpc/persist-extract.log`.
- `lenovo-elden-sensors-rpc.service`: runs `hexagonrpcd`, providing DSP file access through FastRPC.
  It requires successful initialization and `/dev/fastrpc-adsp-secure`. Removing the device stops this service.
- `lenovo-elden-sensors-motion.service`: runs `ssc-input motion`, exposing acceleration and gyroscope readings through a virtual input device.
- `lenovo-elden-sensors-hall.service`: runs `ssc-input hall`, exposing `SW_LID` while inhibiting logind lid actions.
- `iio-sensor-proxy.service`: exposes sensor readings to desktop clients over D-Bus.
  It reads acceleration from the motion device and light, proximity and compass data through SSC.

## Startup order

1. The RPC service pulls in the initialization service and waits for the FastRPC device.
   Initialization and device discovery have no ordering dependency on each other.
2. After initialization succeeds and the device exists, systemd starts `hexagonrpcd`.
3. Motion, Hall and proxy services can then start independently; they have no ordering dependency on each other.
   The Hall service also starts after `systemd-logind.service` when logind has a startup job.

Armbian enables RPC, motion and Hall services for `multi-user.target`.
Udev or D-Bus activation starts the proxy. The RPC dependency starts initialization without enabling it separately.
The RPC unit uses `Type=exec`; its startup does not guarantee that SSC discovery has completed.
Motion and Hall retry after process exits. The proxy can discover input devices that appear after its startup.

Motion, Hall and proxy services start after `hexagonrpcd` and follow its stop/restart operations.
The proxy drop-in selects the private binary and libraries without overwriting the distribution binary.
Udev rules trigger services, identify input devices and supply the acceleration mount matrix.

`lenovo-elden-sensors.conf` configures the proxy service.
`81-lenovo-elden-sensors.rules` supplies the udev rules.
