import os
import stat
import time
import subprocess
import pytest
from helpers import run_command

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_npu_device_node():
    """Verify /dev/vipcore or /dev/galcore device node exists and is a character device."""
    dev_paths = ["/dev/vipcore", "/dev/galcore"]
    found = [p for p in dev_paths if os.path.exists(p)]
    if not found:
        pytest.skip("NPU device node (/dev/vipcore or /dev/galcore) not present (vipcore kernel module not loaded)")
    mode = os.stat(found[0]).st_mode
    assert stat.S_ISCHR(mode), f"{found[0]} is not a character device"

def test_npu_interrupt_registered():
    """Verify vipcore / galcore / NPU interrupt is registered in /proc/interrupts."""
    dev_paths = ["/dev/vipcore", "/dev/galcore"]
    if not any(os.path.exists(p) for p in dev_paths):
        pytest.skip("NPU driver not active, NPU interrupt not expected")
    with open("/proc/interrupts", "r") as f:
        content = f.read()
    assert "vipcore" in content.lower() or "galcore" in content.lower() or "npu" in content.lower(), (
        "NPU interrupt (vipcore/galcore) not found in /proc/interrupts"
    )

def test_npu_lenet_inference():
    """Execute lenet digit recognition benchmark on the NPU."""
    lenet_bin = None
    for candidate in ["/usr/bin/lenet", "./lenet"]:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            lenet_bin = candidate
            break

    if not lenet_bin:
        pytest.skip("lenet NPU benchmark binary not found on target")

    model_path = "/etc/npu/lenet/model/lenet.nb"
    input_path = "/etc/npu/lenet/input_data/lenet.dat"
    if not os.path.exists(model_path) or not os.path.exists(input_path):
        pytest.skip(f"lenet model files missing ({model_path} or {input_path})")

    out, code = run_command(f"{lenet_bin} {model_path} {input_path}", timeout=15)
    assert code == 0, f"lenet execution failed (exit code {code}): {out}"
    assert "awnn_run" in out or "1.000000" in out or "viplite" in out.lower(), (
        f"lenet output did not report classification results: {out}"
    )

def test_npu_vpm_run_inference():
    """Execute vpm_run NBG inference benchmark on the NPU."""
    vpm_bin = None
    for candidate in ["/usr/bin/vpm_run", "./vpm_run"]:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            vpm_bin = candidate
            break

    if not vpm_bin:
        pytest.skip("vpm_run NPU benchmark binary not found on target")

    # Look for sample.txt resource file which specifies NBG and input data
    sample_txt = None
    for candidate in [
        "/etc/npu/vpm_run/sample.txt",
        "/etc/npu/sample.txt",
        "./sample.txt",
    ]:
        if os.path.exists(candidate):
            sample_txt = os.path.abspath(candidate)
            break

    if not sample_txt:
        pytest.skip("No sample.txt found for vpm_run benchmark")

    sample_dir = os.path.dirname(sample_txt)
    sample_name = os.path.basename(sample_txt)
    out, code = run_command(f"cd {sample_dir} && {vpm_bin} -s {sample_name}", timeout=15)
    assert code == 0, f"vpm_run failed (exit code {code}): {out}"
    assert "ret=0" in out or "done" in out.lower(), f"vpm_run did not complete successfully: {out}"
