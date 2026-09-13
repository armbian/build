import os
import glob
import pytest
from helpers import read_sysfs, run_command

pytestmark = [pytest.mark.board]

def test_wifi_interface_present():
    """Verify presence of AIC8800D80 WiFi network interface (wlan0)."""
    wlan_devices = glob.glob("/sys/class/net/wlan*")
    if not wlan_devices:
        pytest.skip("No wireless network interface (wlan0) found in /sys/class/net/")

    wlan_dev = wlan_devices[0]
    operstate = read_sysfs(os.path.join(wlan_dev, "operstate"), default="")
    assert os.path.exists(wlan_dev), f"{wlan_dev} missing"

def test_wifi_not_rfkilled():
    """Verify WiFi is not hard-blocked by rfkill."""
    rfkill_dirs = glob.glob("/sys/class/rfkill/rfkill*")
    for rfd in rfkill_dirs:
        rf_type = read_sysfs(os.path.join(rfd, "type"), default="")
        if rf_type == "wlan":
            hard = read_sysfs(os.path.join(rfd, "hard"), default="0")
            assert hard == "0", f"WiFi is hard-blocked by hardware switch: {rfd}"

def test_bluetooth_hci_present():
    """Verify presence of Bluetooth HCI controller (/sys/class/bluetooth/hci0)."""
    hci_devices = glob.glob("/sys/class/bluetooth/hci*")
    if not hci_devices:
        pytest.skip("No Bluetooth HCI controller found in /sys/class/bluetooth/")

    hci_dev = hci_devices[0]
    dev_type = read_sysfs(os.path.join(hci_dev, "type"), default="")
    assert os.path.exists(hci_dev), f"Bluetooth controller {hci_dev} missing"
