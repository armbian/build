import os
import glob
import time
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.board]

def test_usb3_xhci_controller():
    """Verify presence of SuperSpeed USB 3.0 xHCI host controller in sysfs."""
    usb_devices = glob.glob("/sys/bus/usb/devices/usb*")
    assert len(usb_devices) >= 1, "No USB root hubs found in /sys/bus/usb/devices/"

    speeds = [read_sysfs(os.path.join(d, "speed"), default="") for d in usb_devices]
    has_superspeed = any("5000" in s or "10000" in s for s in speeds)
    assert has_superspeed, (
        f"No SuperSpeed (5000M/10000M) USB 3.x root hub found among speeds: {speeds}"
    )

def test_usb2_companion_controllers():
    """Verify USB 2.0 HighSpeed (480M) host controller root hubs."""
    usb_devices = glob.glob("/sys/bus/usb/devices/usb*")
    speeds = [read_sysfs(os.path.join(d, "speed"), default="") for d in usb_devices]
    has_highspeed = any("480" in s for s in speeds)
    assert has_highspeed, (
        f"No HighSpeed (480M) USB 2.0 root hub found among speeds: {speeds}"
    )

@pytest.mark.hardware
def test_usb_storage_detected(usb_storage_device, usb_mount_path):
    """Verify that an attached USB mass storage drive is detected."""
    target_dev = usb_mount_path or usb_storage_device
    if not target_dev:
        pytest.skip("No USB storage drive detected in USB ports (optional hardware requirement not met)")
    assert os.path.exists(target_dev), f"USB storage device {target_dev} not found"

@pytest.mark.hardware
def test_usb_storage_read_throughput(usb_storage_device, usb_mount_path, is_root):
    """Benchmark sequential read throughput from connected USB drive."""
    target_dev = usb_storage_device
    if not target_dev and usb_mount_path and os.path.exists(usb_mount_path) and not os.path.isdir(usb_mount_path):
        target_dev = usb_mount_path
    elif not target_dev and usb_mount_path and os.path.isdir(usb_mount_path):
        # Find underlying block device of the mountpoint
        out, code = run_command(f"findmnt -n -o SOURCE {usb_mount_path}")
        if code == 0 and os.path.exists(out):
            target_dev = out

    if not target_dev:
        pytest.skip("No USB block device connected")

    chunk_size = 512 * 1024
    num_chunks = 40  # 20 MB read test
    total_bytes = chunk_size * num_chunks

    try:
        with open(target_dev, "rb") as f:
            t0 = time.time()
            bytes_read = 0
            for _ in range(num_chunks):
                data = f.read(chunk_size)
                if not data:
                    break
                bytes_read += len(data)
            elapsed = time.time() - t0
    except PermissionError:
        pytest.skip("Reading from block device requires root privileges")
    except IsADirectoryError:
        pytest.skip(f"{target_dev} is a directory; please provide block device")

    assert bytes_read > 0, "Failed to read any bytes from USB storage device"
    throughput_mb_s = (bytes_read / (1024 * 1024)) / elapsed
    print(f"\n[USB Benchmark] Read {bytes_read / (1024*1024):.1f} MB in {elapsed:.2f}s: {throughput_mb_s:.1f} MB/s")
    assert throughput_mb_s >= 5.0, f"USB read throughput abnormally low: {throughput_mb_s:.1f} MB/s"
