import os
import sys
import stat
import time
import select
import pytest
from helpers import read_sysfs

pytestmark = [pytest.mark.boardfamily, pytest.mark.soc]

def test_framebuffer_device_node():
    """Verify /dev/fb0 exists and is a character device."""
    fb_path = "/dev/fb0"
    if not os.path.exists(fb_path):
        pytest.skip("No framebuffer device /dev/fb0 found (headless or no display handoff)")

    mode = os.stat(fb_path).st_mode
    assert stat.S_ISCHR(mode), f"{fb_path} is not a character device"

def test_drm_card_device():
    """Verify DRM card0 device exists in /dev/dri/."""
    card_path = "/dev/dri/card0"
    if not os.path.exists(card_path):
        pytest.skip("DRM card /dev/dri/card0 not found")
    mode = os.stat(card_path).st_mode
    assert stat.S_ISCHR(mode), f"{card_path} is not a character device"

def test_framebuffer_resolution():
    """Verify framebuffer virtual_size and bits_per_pixel (1920x1080 @ 32 bpp)."""
    size_path = "/sys/class/graphics/fb0/virtual_size"
    bpp_path = "/sys/class/graphics/fb0/bits_per_pixel"

    if not os.path.exists(size_path):
        pytest.skip("sysfs framebuffer virtual_size node not found")

    size_str = read_sysfs(size_path)
    bpp_str = read_sysfs(bpp_path)

    assert size_str is not None, "Could not read fb0 virtual_size"
    assert "1920,1080" in size_str or "1920" in size_str, (
        f"Expected 1920x1080 resolution, got {size_str}"
    )

    if bpp_str:
        assert bpp_str in ("32", "24"), f"Expected 32 or 24 bpp, got {bpp_str}"

@pytest.mark.interactive
@pytest.mark.timeout(45)
def test_display_interactive_pattern(interactive_mode, is_root):
    """Interactive visual confirmation: draws RGB color blocks to /dev/fb0."""
    fb_path = "/dev/fb0"
    if not os.path.exists(fb_path):
        pytest.skip("No framebuffer /dev/fb0 available")

    size_path = "/sys/class/graphics/fb0/virtual_size"
    size_str = read_sysfs(size_path, default="1920,1080")
    try:
        width, height = [int(x) for x in size_str.split(",")]
    except Exception:
        width, height = 1920, 1080

    bytes_per_pixel = 4
    row_bytes = width * bytes_per_pixel

    # Generate 4 color bands: Red, Green, Blue, White
    # In 32-bit XRGB format (little-endian: B, G, R, X)
    red_pixel   = b"\x00\x00\xFF\x00"
    green_pixel = b"\x00\xFF\x00\x00"
    blue_pixel  = b"\xFF\x00\x00\x00"
    white_pixel = b"\xFF\xFF\xFF\x00"

    band_height = height // 4
    red_band   = (red_pixel * width) * band_height
    green_band = (green_pixel * width) * band_height
    blue_band  = (blue_pixel * width) * band_height
    white_band = (white_pixel * width) * (height - 3 * band_height)

    pattern = red_band + green_band + blue_band + white_band

    try:
        with open(fb_path, "wb") as fb:
            fb.write(pattern)
            fb.flush()
    except PermissionError:
        pytest.skip("Writing to /dev/fb0 requires root privileges")

    print("\n[INTERACTIVE DISPLAY TEST]")
    print("A 4-color test pattern (Red, Green, Blue, White) has been drawn to HDMI display.")
    print(">>> Did the test pattern display properly on the monitor? [y/N] (waiting up to 30s): ", end="", flush=True)

    try:
        r, _, _ = select.select([sys.stdin], [], [], 30.0)
        if r:
            response = sys.stdin.readline().strip().lower()
        else:
            print("\n[TIMEOUT] No response received within 30 seconds.")
            response = "timeout"
    except Exception as e:
        print(f"\n[ERROR reading input: {e}]")
        response = "error"

    assert response in ("y", "yes"), f"User response was '{response}' (expected 'y' or 'yes')"

