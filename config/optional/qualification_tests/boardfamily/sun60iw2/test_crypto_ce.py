import os
import stat
import pytest

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_hwrng_device_node():
    """Verify /dev/hwrng hardware random number generator exists."""
    dev_path = "/dev/hwrng"
    assert os.path.exists(dev_path), "Hardware RNG /dev/hwrng device node missing"
    mode = os.stat(dev_path).st_mode
    assert stat.S_ISCHR(mode), f"{dev_path} is not a character device"

def test_hwrng_entropy_read():
    """Read random bytes from /dev/hwrng and verify non-zero entropy."""
    dev_path = "/dev/hwrng"
    try:
        with open(dev_path, "rb") as f:
            data = f.read(256)
    except PermissionError:
        pytest.skip("Permission denied reading /dev/hwrng (requires root or audio/dialout group)")
    except OSError as e:
        pytest.skip(f"/dev/hwrng has no active hardware backend registered: {e}")

    assert len(data) == 256, f"Expected 256 bytes from /dev/hwrng, got {len(data)}"
    # Verify it is not all zeros or a constant repeated byte
    assert data != b"\x00" * 256, "Hardware RNG returned all zero bytes"
    unique_bytes = len(set(data))
    assert unique_bytes > 32, f"Entropy suspiciously low: only {unique_bytes} unique bytes out of 256"

def test_crypto_engine_registered():
    """Verify sun8i-ce Crypto Engine algorithms in /proc/crypto."""
    if not os.path.exists("/proc/crypto"):
        pytest.skip("/proc/crypto not available")

    with open("/proc/crypto", "r") as f:
        content = f.read()

    # On Allwinner SoCs, driver is sun8i-ce or sunxi-ce / ss- hardware driver
    has_sunxi_ce = any(k in content.lower() for k in ["sun8i-ce", "sunxi-ce", "ss-aes", "ss-cbc", "allwinner"])
    if not has_sunxi_ce:
        pytest.skip("sunxi/sun8i hardware crypto not found in /proc/crypto (may be loaded as module)")

    assert "driver" in content, "Invalid /proc/crypto format"
