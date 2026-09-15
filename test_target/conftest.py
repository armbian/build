import os
import sys
import subprocess
import pytest

# Ensure root of test_target is always on sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import read_sysfs, run_command, detect_boardfamily, detect_soc, detect_board, get_armbian_release

def pytest_addoption(parser):
    parser.addoption(
        "--interactive",
        action="store_true",
        default=False,
        help="Run interactive tests that require human intervention or visual inspection",
    )
    parser.addoption(
        "--iperf-server",
        action="store",
        default="router.lan",
        help="IP or hostname of an iperf3 server for network bandwidth testing (default: router.lan)",
    )
    parser.addoption(
        "--usb-mount",
        action="store",
        default=None,
        help="Path to mounted USB storage device for throughput tests",
    )

def pytest_collection_modifyitems(config, items):
    if not config.getoption("--interactive"):
        skip_interactive = pytest.mark.skip(
            reason="Interactive test skipped (pass --interactive to run)"
        )
        for item in items:
            if "interactive" in item.keywords:
                item.add_marker(skip_interactive)

@pytest.fixture(scope="session")
def interactive_mode(request):
    return request.config.getoption("--interactive")

@pytest.fixture(scope="session")
def iperf_server(request):
    return request.config.getoption("--iperf-server")

@pytest.fixture(scope="session")
def usb_mount_path(request):
    return request.config.getoption("--usb-mount")

@pytest.fixture(scope="session")
def is_root():
    return os.geteuid() == 0

@pytest.fixture(scope="session")
def detected_boardfamily():
    return detect_boardfamily()

@pytest.fixture(scope="session")
def detected_soc(detected_boardfamily):
    return detected_boardfamily

@pytest.fixture(scope="session")
def detected_board():
    return detect_board()

@pytest.fixture(scope="session")
def armbian_info():
    return get_armbian_release()
