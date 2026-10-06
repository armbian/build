import os
import glob
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.board]

def test_regulators_registered():
    """Verify that power regulators are registered in sysfs."""
    regulators = glob.glob("/sys/class/regulator/regulator.*")
    assert len(regulators) >= 1, "No voltage regulators found in /sys/class/regulator/"

def test_axp_power_rails():
    """Verify presence and valid microvolt levels of essential SoC/board power rails."""
    regulators = glob.glob("/sys/class/regulator/regulator.*")
    rails = {}
    for reg in regulators:
        name = read_sysfs(os.path.join(reg, "name"), default="")
        microvolts = read_sysfs(os.path.join(reg, "microvolts"), default="0")
        if name:
            rails[name.lower()] = int(microvolts) if microvolts.isdigit() else 0

    assert rails, "No named regulator rails found"

    # Check that at least some core rails report valid voltages > 0.5V (500000 uV)
    valid_rails = [name for name, uV in rails.items() if uV >= 500000]
    assert len(valid_rails) >= 1, f"No regulators reporting operational voltage: {rails}"

def test_i2c_pmic_bus():
    """Verify presence of I2C bus controllers in /dev/i2c-*."""
    i2c_nodes = glob.glob("/dev/i2c-*")
    if not i2c_nodes:
        pytest.skip("No /dev/i2c-* character devices found (i2c-dev module may need loading)")
    assert len(i2c_nodes) >= 1, f"Found I2C buses: {i2c_nodes}"
