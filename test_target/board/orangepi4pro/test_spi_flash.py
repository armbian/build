import os
import glob
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.board]

def test_spi_flash_mtd_present(spi_nor_device):
    """Verify presence of onboard SPI-NOR flash MTD device."""
    if not spi_nor_device or not os.path.exists(spi_nor_device):
        # Check sysfs mtd devices
        mtd_dirs = glob.glob("/sys/class/mtd/mtd*")
        if not mtd_dirs:
            pytest.skip("No SPI-NOR MTD flash devices found")
        spi_nor_device = "/dev/mtd0"

    assert os.path.exists("/sys/class/mtd/mtd0"), "MTD device mtd0 missing in /sys/class/mtd/"

def test_spi_flash_capacity():
    """Verify onboard SPI-NOR flash size (16 MB / 16777216 bytes)."""
    size_file = "/sys/class/mtd/mtd0/size"
    if not os.path.exists(size_file):
        pytest.skip("/sys/class/mtd/mtd0/size not found")

    size_str = read_sysfs(size_file)
    assert size_str is not None and size_str.isdigit(), f"Invalid mtd0 size: {size_str}"
    size_bytes = int(size_str)
    # Orange Pi 4 Pro features a 16MB SPI-NOR flash chip
    expected_bytes = 16 * 1024 * 1024
    assert size_bytes == expected_bytes, (
        f"Expected 16MB ({expected_bytes} bytes), got {size_bytes} bytes"
    )

def test_spi_flash_safe_read(is_root):
    """Read first 4KB of SPI NOR flash and verify bootloader / TOC data presence."""
    mtd_path = "/dev/mtd0ro" if os.path.exists("/dev/mtd0ro") else "/dev/mtd0"
    if not os.path.exists(mtd_path):
        pytest.skip(f"Device node {mtd_path} not available")

    try:
        with open(mtd_path, "rb") as f:
            header = f.read(4096)
    except PermissionError:
        pytest.skip(f"Reading from {mtd_path} requires root privileges")

    assert len(header) == 4096, f"Expected 4096 bytes read from SPI-NOR, got {len(header)}"
    # Verify the chip is not unprogrammed (all 0xFF) or wiped (all 0x00)
    assert header != b"\xFF" * 4096, "SPI NOR flash block is completely unprogrammed (0xFF)"
    assert header != b"\x00" * 4096, "SPI NOR flash block is completely zeroed (0x00)"
