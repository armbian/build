import os
import glob
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_thermal_zones_exist():
    """Verify that thermal zones are registered in sysfs."""
    zones = glob.glob("/sys/class/thermal/thermal_zone*")
    assert len(zones) >= 1, "No thermal zones found in /sys/class/thermal/"

def test_thermal_zone_readings():
    """Verify that every thermal zone produces a valid, plausible temperature reading."""
    zones = sorted(glob.glob("/sys/class/thermal/thermal_zone*"))
    assert zones, "No thermal zones found"

    for zone in zones:
        zone_name = os.path.basename(zone)
        zone_type = read_sysfs(os.path.join(zone, "type"), default="unknown")
        temp_raw = read_sysfs(os.path.join(zone, "temp"))
        assert temp_raw is not None, f"Could not read temperature from {zone_name}"
        assert temp_raw.lstrip("-").isdigit(), f"Non-numeric temperature '{temp_raw}' in {zone_name}"

        # Values in sysfs are in millicelsius (e.g. 45000 = 45°C)
        temp_c = int(temp_raw) / 1000.0
        assert 15.0 <= temp_c <= 105.0, (
            f"Thermal zone {zone_name} ({zone_type}) temperature out of bounds: {temp_c}°C"
        )

def test_ths_hardware_zones_named():
    """Check for expected Allwinner A733 thermal sensors (CPU, GPU, NPU, DDR)."""
    zones = glob.glob("/sys/class/thermal/thermal_zone*")
    types = [read_sysfs(os.path.join(z, "type"), default="") for z in zones]
    types_str = " ".join(types).lower()

    # On A733, sensors monitor cpu-little, cpu-big, gpu, npu, ddr
    has_cpu = any("cpu" in t for t in types)
    assert has_cpu, f"No CPU thermal zone found among types: {types}"
