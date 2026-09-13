import os
import pytest

@pytest.fixture(scope="session")
def dt_compatible():
    compat_path = "/sys/firmware/devicetree/base/compatible"
    if os.path.exists(compat_path):
        try:
            with open(compat_path, "rb") as f:
                return f.read().decode("utf-8", errors="ignore").split("\x00")
        except Exception:
            return []
    return []

@pytest.fixture(scope="session")
def is_sun60iw2(dt_compatible):
    return any("sun60i" in c or "a733" in c or "sun60iw2" in c or "t736" in c for c in dt_compatible)

@pytest.fixture(scope="session")
def is_a733(is_sun60iw2):
    return is_sun60iw2
