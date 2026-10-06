import os
import time
import glob
import pytest
from helpers import read_sysfs, run_command

pytestmark = [pytest.mark.board]

def test_pcie_controller_present():
    """Verify PCIe Root Complex controller appears on the PCI bus."""
    pci_devs = glob.glob("/sys/bus/pci/devices/*")
    assert len(pci_devs) >= 1, "No PCI/PCIe devices found in /sys/bus/pci/devices/"

def test_pcie_link_speed():
    """Verify PCIe link speed (Gen2 5.0 GT/s or Gen3 8.0 GT/s)."""
    pci_devs = glob.glob("/sys/bus/pci/devices/*")
    speeds = []
    for dev in pci_devs:
        speed_file = os.path.join(dev, "current_link_speed")
        if os.path.exists(speed_file):
            val = read_sysfs(speed_file)
            if val:
                speeds.append((dev, val))

    if not speeds:
        pytest.skip("PCIe device link speed not reported by sysfs")

    # Ensure at least one PCIe device reports a valid link speed
    valid_speeds = [s for d, s in speeds if "GT/s" in s or "Gb/s" in s]
    assert len(valid_speeds) >= 1, f"No active PCIe link speed found: {speeds}"

@pytest.mark.hardware
def test_nvme_drive_detected(nvme_block_device):
    """Verify that an NVMe M.2 SSD is detected."""
    if not nvme_block_device:
        pytest.skip("No NVMe SSD detected in M.2 slot (optional hardware requirement not met)")
    assert os.path.exists(nvme_block_device), f"NVMe block device {nvme_block_device} missing"

@pytest.mark.hardware
def test_nvme_read_throughput(nvme_block_device, is_root):
    """Benchmark sequential read throughput from NVMe drive."""
    if not nvme_block_device:
        pytest.skip("No NVMe SSD connected")

    # Read 50 MB in 1MB chunks
    chunk_size = 1024 * 1024
    num_chunks = 50
    total_bytes = chunk_size * num_chunks

    try:
        with open(nvme_block_device, "rb") as f:
            t0 = time.time()
            bytes_read = 0
            for _ in range(num_chunks):
                data = f.read(chunk_size)
                if not data:
                    break
                bytes_read += len(data)
            elapsed = time.time() - t0
    except PermissionError:
        pytest.skip("Reading from block device requires root permissions")

    assert bytes_read > 0, "Failed to read any bytes from NVMe drive"
    throughput_mb_s = (bytes_read / (1024 * 1024)) / elapsed
    print(f"\n[NVMe Benchmark] Read {bytes_read / (1024*1024):.1f} MB in {elapsed:.2f}s: {throughput_mb_s:.1f} MB/s")
    assert throughput_mb_s >= 30.0, f"NVMe read throughput abnormally low: {throughput_mb_s:.1f} MB/s"
