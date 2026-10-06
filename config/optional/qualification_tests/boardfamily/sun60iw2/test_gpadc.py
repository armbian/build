import os
import glob
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def find_gpadc_device():
    for dev in glob.glob("/sys/bus/iio/devices/iio:device*"):
        name = read_sysfs(os.path.join(dev, "name"), default="")
        if "gpadc" in name.lower() or "adc" in name.lower():
            return dev
    return None

def test_gpadc_device_present():
    """Verify that the Allwinner GPADC IIO device is registered."""
    gpadc_dev = find_gpadc_device()
    if not gpadc_dev:
        # If no explicit name match, check if any IIO device exists
        devices = glob.glob("/sys/bus/iio/devices/iio:device*")
        if not devices:
            pytest.skip("No IIO devices found in /sys/bus/iio/devices/")
        gpadc_dev = devices[0]

    assert os.path.exists(gpadc_dev), "GPADC IIO device not found"

def test_gpadc_raw_readings():
    """Verify reading raw voltage channels produces valid 12-bit ADC values (0..4095)."""
    gpadc_dev = find_gpadc_device()
    if not gpadc_dev:
        devices = glob.glob("/sys/bus/iio/devices/iio:device*")
        if not devices:
            pytest.skip("No IIO devices available to read")
        gpadc_dev = devices[0]

    raw_files = glob.glob(os.path.join(gpadc_dev, "in_voltage*_raw"))
    if not raw_files:
        pytest.skip(f"No in_voltage*_raw channels found in {gpadc_dev}")

    for raw_path in raw_files:
        val_str = read_sysfs(raw_path)
        assert val_str is not None and val_str.isdigit(), (
            f"Invalid ADC reading from {raw_path}: '{val_str}'"
        )
        val = int(val_str)
        # Allwinner GPADC is 12-bit (0..4095)
        assert 0 <= val <= 4095, f"ADC value {val} out of 12-bit range in {raw_path}"
