import os
import platform
import glob
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_cpu_architecture():
    """Verify system architecture is aarch64."""
    arch = platform.machine()
    assert arch in ("aarch64", "arm64"), f"Expected aarch64 CPU architecture, got {arch}"

def test_cpu_core_count():
    """Verify that all 8 CPU cores (6x Cortex-A55 + 2x Cortex-A76) exist in sysfs."""
    cpu_dirs = glob.glob("/sys/devices/system/cpu/cpu[0-9]*")
    # Filter only cpu0..cpu7
    core_dirs = [d for d in cpu_dirs if os.path.basename(d)[3:].isdigit()]
    assert len(core_dirs) >= 8, f"Expected at least 8 CPU cores, found {len(core_dirs)}"

def test_cpu_cluster_topology():
    """Verify DynamIQ big.LITTLE cluster topology: 6x Cortex-A55 (0xd05) and 2x Cortex-A76 (0xd0b)."""
    # Check Cores 0-5 (LITTLE cluster: Cortex-A55)
    for i in range(6):
        midr_path = f"/sys/devices/system/cpu/cpu{i}/regs/identification/midr_el1"
        midr = read_sysfs(midr_path)
        if midr:
            val = int(midr, 16)
            part = (val >> 4) & 0xfff
            assert part == 0xd05, f"Core {i} expected Cortex-A55 (0xd05), got 0x{part:x}"

    # Check Cores 6-7 (BIG cluster: Cortex-A76)
    for i in (6, 7):
        midr_path = f"/sys/devices/system/cpu/cpu{i}/regs/identification/midr_el1"
        midr = read_sysfs(midr_path)
        if midr:
            val = int(midr, 16)
            part = (val >> 4) & 0xfff
            assert part == 0xd0b, f"Core {i} expected Cortex-A76 (0xd0b), got 0x{part:x}"

def test_cpu_online_status():
    """Verify that all available cores are online."""
    online_str = read_sysfs("/sys/devices/system/cpu/online")
    assert online_str is not None, "Could not read /sys/devices/system/cpu/online"
    # For an 8-core CPU, online should be '0-7'
    assert "0-7" in online_str or online_str == "0-7", f"Not all cores online: {online_str}"

    for i in range(8):
        online_file = f"/sys/devices/system/cpu/cpu{i}/online"
        if os.path.exists(online_file):
            assert read_sysfs(online_file) == "1", f"CPU core {i} is offline"

def test_cpu_frequencies():
    """Verify that cpufreq policy is initialized and reporting valid clock frequencies."""
    policies = glob.glob("/sys/devices/system/cpu/cpufreq/policy*")
    if not policies:
        pytest.skip("No cpufreq policies active in sysfs")

    for policy in policies:
        cur_freq = read_sysfs(os.path.join(policy, "scaling_cur_freq"))
        assert cur_freq is not None and cur_freq.isdigit(), f"Invalid scaling_cur_freq in {policy}"
        freq_khz = int(cur_freq)
        assert freq_khz > 200000, f"CPU frequency abnormally low: {freq_khz} kHz in {policy}"
