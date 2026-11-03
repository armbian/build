import os
import glob
import pytest
from helpers import read_sysfs

@pytest.fixture(scope="session")
def nvme_block_device():
    """Detect presence of an NVMe block device in /dev/nvme*n1."""
    devs = glob.glob("/dev/nvme[0-9]n[0-9]")
    if devs:
        return devs[0]
    # Check sysfs fallback
    nvme_sys = glob.glob("/sys/class/block/nvme*n*")
    if nvme_sys:
        return os.path.join("/dev", os.path.basename(nvme_sys[0]))
    return None

@pytest.fixture(scope="session")
def usb_storage_device():
    """Detect presence of a USB mass storage block device (/dev/sd*)."""
    # Exclude root/emmc devices; find block devices linked to usb
    for blk in glob.glob("/sys/block/sd*"):
        target_path = os.path.realpath(blk)
        if "usb" in target_path:
            return os.path.join("/dev", os.path.basename(blk))
    return None

@pytest.fixture(scope="session")
def primary_eth_interface():
    """Detect primary wired ethernet interface name (e.g. end0, eth0)."""
    for iface in ["end0", "eth0"]:
        if os.path.exists(f"/sys/class/net/{iface}"):
            return iface
    for iface_path in glob.glob("/sys/class/net/e*"):
        name = os.path.basename(iface_path)
        if name != "lo" and not name.startswith("wl"):
            return name
    return None

@pytest.fixture(scope="session")
def eth_carrier(primary_eth_interface):
    """Check if primary ethernet interface has an active carrier/cable connected."""
    if not primary_eth_interface:
        return False
    carrier_path = f"/sys/class/net/{primary_eth_interface}/carrier"
    if not os.path.exists(carrier_path):
        return False
    val = read_sysfs(carrier_path, default="0")
    return val == "1"

@pytest.fixture(scope="session")
def eth0_carrier(eth_carrier):
    """Backward-compatibility alias for eth_carrier."""
    return eth_carrier

@pytest.fixture(scope="session")
def spi_nor_device():
    """Detect presence of SPI NOR MTD flash device."""
    for mtd in glob.glob("/sys/class/mtd/mtd[0-9]*"):
        type_str = read_sysfs(os.path.join(mtd, "type"), default="")
        name_str = read_sysfs(os.path.join(mtd, "name"), default="")
        if "nor" in type_str.lower() or "spi" in name_str.lower() or "flash" in name_str.lower():
            dev_name = os.path.basename(mtd)
            return os.path.join("/dev", dev_name)
    if os.path.exists("/dev/mtd0"):
        return "/dev/mtd0"
    return None

@pytest.fixture(scope="session")
def sd_card_device():
    """Detect presence of an SD/MMC block device (/dev/mmcblk0)."""
    if os.path.exists("/dev/mmcblk0"):
        return "/dev/mmcblk0"
    devs = glob.glob("/dev/mmcblk[0-9]")
    if devs:
        return devs[0]
    return None

