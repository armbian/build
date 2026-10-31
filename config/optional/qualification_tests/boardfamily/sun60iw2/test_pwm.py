import os
import glob
import time
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_pwm_chip_registered():
    """Verify that at least one PWM chip is registered in sysfs."""
    chips = glob.glob("/sys/class/pwm/pwmchip*")
    assert len(chips) >= 1, "No PWM chips found in /sys/class/pwm/"

def test_pwm_channel_count():
    """Verify that PWM chips report valid channel counts via npwm."""
    chips = glob.glob("/sys/class/pwm/pwmchip*")
    for chip in chips:
        npwm = read_sysfs(os.path.join(chip, "npwm"))
        assert npwm is not None and npwm.isdigit(), f"Invalid npwm in {chip}"
        assert int(npwm) > 0, f"PWM chip {chip} has 0 channels"

def test_pwm_channel_export_and_config(is_root):
    """Test exporting, configuring period and duty cycle, and unexporting a PWM channel."""
    if not is_root:
        pytest.skip("Root privileges required to write to /sys/class/pwm/pwmchip*/export")

    chips = glob.glob("/sys/class/pwm/pwmchip*")
    if not chips:
        pytest.skip("No PWM chips found")

    chip = chips[0]
    export_path = os.path.join(chip, "export")
    unexport_path = os.path.join(chip, "unexport")
    pwm0_dir = os.path.join(chip, "pwm0")

    # If already exported, unexport first
    if os.path.exists(pwm0_dir):
        try:
            with open(unexport_path, "w") as f:
                f.write("0\n")
            time.sleep(0.1)
        except OSError:
            pass

    try:
        # Export channel 0
        with open(export_path, "w") as f:
            f.write("0\n")
        time.sleep(0.1)

        assert os.path.exists(pwm0_dir), f"Failed to export pwm0 in {chip}"

        # Configure 1 kHz period (1,000,000 ns) and 50% duty cycle (500,000 ns)
        period_path = os.path.join(pwm0_dir, "period")
        duty_path = os.path.join(pwm0_dir, "duty_cycle")

        with open(period_path, "w") as f:
            f.write("1000000\n")
        with open(duty_path, "w") as f:
            f.write("500000\n")

        assert read_sysfs(period_path) == "1000000"
        assert read_sysfs(duty_path) == "500000"

    finally:
        # Clean up by unexporting
        if os.path.exists(pwm0_dir):
            try:
                with open(unexport_path, "w") as f:
                    f.write("0\n")
            except OSError:
                pass
