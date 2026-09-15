import os
import sys
import glob
import json
import subprocess

def read_sysfs(path, default=None):
    """Helper to read single-line value from sysfs."""
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except (OSError, IOError):
        return default

def run_command(cmd, timeout=10):
    """Helper to run a shell command and return (stdout, returncode)."""
    try:
        res = subprocess.run(
            cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        return res.stdout.strip(), res.returncode
    except subprocess.TimeoutExpired:
        return "", -1
    except Exception as e:
        return str(e), -1

def get_armbian_release():
    """Parse /etc/armbian-release and /etc/armbian-image-release if present."""
    info = {}
    for path in ["/etc/armbian-release", "/etc/armbian-image-release"]:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            info[k.strip()] = v.strip().strip('"').strip("'")
                if info:
                    break
            except Exception:
                pass
    return info

def get_device_tree_info():
    """Read compatible and model from /sys/firmware/devicetree/base or /proc/device-tree."""
    info = {"compatibles": [], "model": ""}
    for base in ["/sys/firmware/devicetree/base", "/proc/device-tree"]:
        compat_path = os.path.join(base, "compatible")
        model_path = os.path.join(base, "model")
        if os.path.exists(compat_path):
            try:
                with open(compat_path, "rb") as f:
                    raw = f.read().decode("utf-8", errors="ignore")
                    info["compatibles"] = [c for c in raw.split("\x00") if c]
            except Exception:
                pass
        if os.path.exists(model_path):
            try:
                with open(model_path, "r", errors="ignore") as f:
                    info["model"] = f.read().strip().strip("\x00")
            except Exception:
                pass
        if info["compatibles"] or info["model"]:
            break
    return info

def _normalize(name):
    """Normalize string for fuzzy comparison (remove _, -, spaces, commas)."""
    return name.lower().replace("_", "").replace("-", "").replace(" ", "").replace(",", "")

# Known Boardfamily alias mappings: alias -> folder name under boardfamily/
BOARDFAMILY_ALIASES = {
    "sun60iw2": "sun60iw2",
    "sun60i": "sun60iw2",
    "a733": "sun60iw2",
    "allwinnera733": "sun60iw2",
    "allwinner_a733": "sun60iw2",
    "t736": "sun60iw2",
}

# Known Board alias mappings: alias -> folder name under board/
BOARD_ALIASES = {
    "orangepi4pro": "orangepi4pro",
    "orangepi4-pro": "orangepi4pro",
    "opi4pro": "orangepi4pro",
}

def detect_boardfamily(test_target_dir=None):
    """
    Detect the Boardfamily / SoC family from Armbian release files and Device Tree.
    Returns matching directory name under test_target/boardfamily/ (e.g. 'sun60iw2') or None.
    """
    if not test_target_dir:
        test_target_dir = os.path.dirname(os.path.abspath(__file__))
    fam_base = os.path.join(test_target_dir, "boardfamily")
    if not os.path.exists(fam_base):
        # Fallback to legacy soc/ if present
        fam_base = os.path.join(test_target_dir, "soc")

    available_families = [
        d for d in os.listdir(fam_base)
        if os.path.isdir(os.path.join(fam_base, d)) and not d.startswith(".") and d != "__pycache__"
    ] if os.path.exists(fam_base) else []

    armbian = get_armbian_release()
    dt = get_device_tree_info()

    candidates = []
    if "BOARDFAMILY" in armbian:
        candidates.append(armbian["BOARDFAMILY"])
    if "BOOT_SOC" in armbian:
        candidates.append(armbian["BOOT_SOC"])
    if "LINUXFAMILY" in armbian:
        candidates.append(armbian["LINUXFAMILY"])
    candidates.extend(dt.get("compatibles", []))

    for c in candidates:
        norm = _normalize(c)
        if norm in BOARDFAMILY_ALIASES and BOARDFAMILY_ALIASES[norm] in available_families:
            return BOARDFAMILY_ALIASES[norm]
        for alias_key, target in BOARDFAMILY_ALIASES.items():
            if alias_key in norm and target in available_families:
                return target
        for fam in available_families:
            if _normalize(fam) in norm or norm in _normalize(fam):
                return fam

    return None

# Alias for detect_boardfamily
detect_soc = detect_boardfamily

def detect_board(test_target_dir=None):
    """
    Detect the Board from Armbian release files and Device Tree.
    Returns matching directory name under test_target/board/ (e.g. 'orangepi4pro') or None.
    """
    if not test_target_dir:
        test_target_dir = os.path.dirname(os.path.abspath(__file__))
    board_base = os.path.join(test_target_dir, "board")
    available_boards = [
        d for d in os.listdir(board_base)
        if os.path.isdir(os.path.join(board_base, d)) and not d.startswith(".") and d != "__pycache__"
    ] if os.path.exists(board_base) else []

    armbian = get_armbian_release()
    dt = get_device_tree_info()

    candidates = []
    if "BOARD" in armbian:
        candidates.append(armbian["BOARD"])
    if "BOARD_NAME" in armbian:
        candidates.append(armbian["BOARD_NAME"])
    if dt.get("model"):
        candidates.append(dt["model"])
    candidates.extend(dt.get("compatibles", []))

    for c in candidates:
        norm = _normalize(c)
        if norm in BOARD_ALIASES and BOARD_ALIASES[norm] in available_boards:
            return BOARD_ALIASES[norm]
        for alias_key, target in BOARD_ALIASES.items():
            if alias_key in norm and target in available_boards:
                return target
        for board in available_boards:
            if _normalize(board) in norm or norm in _normalize(board):
                return board

    return None

if __name__ == "__main__":
    test_dir = os.path.dirname(os.path.abspath(__file__))
    if "--detect-boardfamily" in sys.argv or "--detect-family" in sys.argv or "--detect-soc" in sys.argv:
        fam = detect_boardfamily(test_dir)
        if fam:
            print(fam)
    elif "--detect-board" in sys.argv:
        board = detect_board(test_dir)
        if board:
            print(board)
    elif "--detect" in sys.argv or len(sys.argv) == 1:
        res = {
            "armbian": get_armbian_release(),
            "device_tree": get_device_tree_info(),
            "detected_boardfamily": detect_boardfamily(test_dir),
            "detected_board": detect_board(test_dir),
        }
        print(json.dumps(res, indent=2))
