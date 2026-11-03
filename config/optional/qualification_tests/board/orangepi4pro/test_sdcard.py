import os
import time
import shutil
import pytest
from helpers import read_sysfs, run_command

pytestmark = [pytest.mark.board]

@pytest.fixture
def sd_test_dir():
    """
    Provide a scratch directory strictly located on the SD card filesystem (/dev/mmcblk*).
    /tmp is mounted on tmpfs (RAM), so /var/tmp or /root must be used to test actual MMC hardware.
    """
    test_dir = "/var/tmp/sd_test"
    os.makedirs(test_dir, exist_ok=True)

    # Verify that test_dir is actually mounted on an mmcblk partition
    out, code = run_command(f"findmnt -n -o SOURCE -T {test_dir}", timeout=5)
    assert code == 0 and "mmcblk" in out, (
        f"Test directory {test_dir} is not on an SD/MMC device: {out}"
    )

    yield test_dir
    shutil.rmtree(test_dir, ignore_errors=True)

def test_sdcard_device_detected(sd_card_device):
    """Verify that an SD/MMC block device is detected in /dev."""
    if not sd_card_device:
        pytest.skip("No SD card detected (/dev/mmcblk0 missing)")
    assert os.path.exists(sd_card_device), f"Block device {sd_card_device} missing"

def test_sdcard_capacity(sd_card_device):
    """Verify SD card capacity reported by sysfs is valid (> 2 GB)."""
    if not sd_card_device:
        pytest.skip("No SD card device available")
    dev_name = os.path.basename(sd_card_device)
    size_file = f"/sys/class/block/{dev_name}/size"
    if not os.path.exists(size_file):
        pytest.skip(f"{size_file} not found")

    size_sectors = read_sysfs(size_file)
    assert size_sectors and size_sectors.isdigit(), f"Invalid size in {size_file}: {size_sectors}"
    # Size in 512-byte sectors -> convert to GiB
    size_gib = (int(size_sectors) * 512) / (1024 ** 3)
    print(f"\n[SD Card] Detected capacity: {size_gib:.2f} GiB ({size_sectors} sectors)")
    assert size_gib >= 2.0, f"SD card capacity abnormally low: {size_gib:.2f} GiB"

def test_sdcard_controller_driver():
    """Verify sunxi-mmc platform driver is bound to the SDXC controller (4020000.mmc)."""
    driver_path = "/sys/bus/platform/drivers/sunxi-mmc/4020000.mmc"
    assert os.path.exists(driver_path), (
        "sunxi-mmc driver is not bound to 4020000.mmc controller"
    )

def test_sdcard_single_block_direct_write(sd_test_dir, is_root):
    """
    Verify single-block (512 bytes) direct I/O write on SD card filesystem.
    Single-block writes never triggered the IDMAC burst threshold bug.
    """
    if not is_root:
        pytest.skip("Direct I/O block testing requires root permissions")

    test_file = os.path.join(sd_test_dir, "test_single_block.bin")
    cmd = f"dd if=/dev/zero of={test_file} bs=512 count=1 oflag=direct"
    out, code = run_command(cmd, timeout=10)
    assert code == 0, f"Single-block direct write failed ({code}): {out}"
    assert os.path.exists(test_file) and os.path.getsize(test_file) == 512

def test_sdcard_multiblock_write_boundary(sd_test_dir, is_root):
    """
    Boundary test specifically targeting the Allwinner A733 IDMAC REG_THLDC stall bug.
    Without the fix, any multi-block write (count >= 2 blocks) hangs in D-state waiting
    for a DMA completion interrupt that never arrives.
    """
    if not is_root:
        pytest.skip("Direct I/O block testing requires root permissions")

    # Test 1: 2 blocks (1024 bytes) - the exact boundary where IDMAC enters multi-block mode
    test_1k = os.path.join(sd_test_dir, "test_1k.bin")
    cmd_1k = f"dd if=/dev/zero of={test_1k} bs=512 count=2 oflag=direct"
    out, code = run_command(cmd_1k, timeout=10)
    assert code == 0, f"2-block direct write failed or timed out (IDMAC stall): {out}"
    assert os.path.getsize(test_1k) == 1024

    # Test 2: 4 KB (8 blocks)
    test_4k = os.path.join(sd_test_dir, "test_4k.bin")
    cmd_4k = f"dd if=/dev/zero of={test_4k} bs=4k count=1 oflag=direct"
    out, code = run_command(cmd_4k, timeout=10)
    assert code == 0, f"4KB direct write failed or timed out: {out}"
    assert os.path.getsize(test_4k) == 4096

    # Test 3: 64 KB (128 blocks)
    test_64k = os.path.join(sd_test_dir, "test_64k.bin")
    cmd_64k = f"dd if=/dev/zero of={test_64k} bs=64k count=1 oflag=direct"
    out, code = run_command(cmd_64k, timeout=10)
    assert code == 0, f"64KB direct write failed or timed out: {out}"
    assert os.path.getsize(test_64k) == 65536

def test_sdcard_direct_write_throughput(sd_test_dir, is_root):
    """
    Benchmark multi-megabyte direct I/O write throughput (10 MB, 20480 blocks) on SD card.
    Verifies sustained IDMAC DMA throughput and ensures no bus stalls occur.
    """
    if not is_root:
        pytest.skip("Direct I/O throughput testing requires root permissions")

    test_10m = os.path.join(sd_test_dir, "test_10m.bin")
    cmd = f"dd if=/dev/zero of={test_10m} bs=1M count=10 oflag=direct"
    t0 = time.time()
    out, code = run_command(cmd, timeout=30)
    elapsed = time.time() - t0

    assert code == 0, f"10 MB direct write failed or timed out ({code}): {out}"
    assert os.path.getsize(test_10m) == 10 * 1024 * 1024

    mb_s = 10.0 / elapsed
    print(f"\n[SD Card Write Benchmark] 10 MB direct write in {elapsed:.2f}s: {mb_s:.2f} MB/s")
    assert mb_s >= 1.5, f"SD direct write throughput abnormally low: {mb_s:.2f} MB/s"

def test_sdcard_sequential_read_throughput(sd_test_dir, is_root):
    """Benchmark sequential read throughput from SD card using direct I/O."""
    if not is_root:
        pytest.skip("Direct I/O throughput testing requires root permissions")

    test_10m = os.path.join(sd_test_dir, "test_10m.bin")
    if not os.path.exists(test_10m):
        # Create test file if previous test did not run
        run_command(f"dd if=/dev/zero of={test_10m} bs=1M count=10", timeout=15)
        run_command("sync", timeout=10)

    cmd = f"dd if={test_10m} of=/dev/null bs=1M iflag=direct"
    t0 = time.time()
    out, code = run_command(cmd, timeout=25)
    elapsed = time.time() - t0

    assert code == 0, f"10 MB direct read failed ({code}): {out}"
    mb_s = 10.0 / elapsed
    print(f"\n[SD Card Read Benchmark] 10 MB direct read in {elapsed:.2f}s: {mb_s:.2f} MB/s")
    assert mb_s >= 2.5, f"SD direct read throughput abnormally low: {mb_s:.2f} MB/s"

def test_sdcard_dmesg_no_idmac_errors():
    """Verify kernel log contains zero MMC hardware timeouts, IDMAC stalls, or CRC errors."""
    out, code = run_command("dmesg | grep -iE 'mmcblk0.*(error|timed out|corrupt)|sunxi-mmc.*(error|timeout|fatal)'", timeout=5)
    assert code != 0 or not out.strip(), f"Found MMC error messages in dmesg:\n{out}"
