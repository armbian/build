#!/usr/bin/env bash
#
# Peripheral test runner for target SBCs with automatic hardware detection.
# Usage:
#   ./run_tests.sh                               # Auto-detects Boardfamily & Board and runs tests
#   ./run_tests.sh --boardfamily                 # Run tests for detected board family (or all)
#   ./run_tests.sh --boardfamily sun60iw2        # Run specific board family tests
#   ./run_tests.sh --board                       # Run tests for detected Board (or all boards)
#   ./run_tests.sh --board orangepi4pro          # Run specific board tests
#   ./run_tests.sh --interactive                 # Include interactive tests (HDMI pattern, buttons)
#   ./run_tests.sh --iperf <IP>                  # Test network bandwidth against iperf3 server
#   ./run_tests.sh --usb-mount </mnt/usb>        # Run throughput test on mounted USB storage
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

show_help() {
    cat << 'EOF'
Target Peripheral Validation Suite Runner

Usage:
  ./run_tests.sh [OPTIONS] [PYTEST_OPTIONS]

Target Selection:
  (default)                     Auto-detects board family and board, running applicable tests
  --boardfamily, --soc [FAMILY] Run tests for detected board family (or specify FAMILY, e.g. sun60iw2)
  --board [BOARD]               Run tests for detected board (or specify BOARD, e.g. orangepi4pro)
  <path/to/test.py>             Run a specific test file or directory directly


Hardware & Setup Options:
  --skip-setup, --no-setup      Skip running board/boardfamily setup.sh scripts prior to testing

Test Configuration:
  --interactive                 Include interactive tests requiring visual inspection or physical input
  --iperf <IP|HOST>             Specify iperf3 server for network bandwidth testing (default: router.lan)
  --usb-mount <PATH>            Path to mounted USB storage device for throughput testing

Help:
  -h, --help                    Show this help message and exit

Pytest Options:
  Any additional arguments (e.g. -v, -s, -k "pattern", -x, --tb=short) are forwarded directly to pytest.

Examples:
  ./run_tests.sh                                # Auto-detect and run non-interactive tests
  ./run_tests.sh --board orangepi4pro -v        # Run tests for Orange Pi 4 Pro with verbose output
  ./run_tests.sh --boardfamily sun60iw2         # Run Allwinner A733 / sun60iw2 family tests
  ./run_tests.sh board/orangepi4pro/test_sdcard.py -s  # Run only the SD card test suite
  ./run_tests.sh --interactive                  # Run all detected tests including interactive checks
EOF
}

# Early check for help flag before dependency verification
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        show_help
        exit 0
    fi
done

# Ensure pytest is installed
if ! command -v pytest >/dev/null 2>&1 && ! python3 -m pytest --version >/dev/null 2>&1; then
    echo "pytest is not installed. Installing..."
    pip3 install -r requirements.txt || (apt-get update && apt-get install -y python3-pytest)
fi

# Auto-detect Board and Boardfamily from Armbian release files and Device Tree
AUTO_BOARDFAMILY=$(python3 helpers.py --detect-boardfamily 2>/dev/null || true)
AUTO_BOARD=$(python3 helpers.py --detect-board 2>/dev/null || true)

SKIP_SETUP=0
EXPLICIT_TARGET=0
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-setup|--no-setup)
            SKIP_SETUP=1
            shift
            ;;

        --boardfamily|--soc)
            EXPLICIT_TARGET=1
            if [[ -n "$2" && "$2" != --* ]]; then
                ARGS+=("boardfamily/$2")
                shift 2
            elif [[ -n "${AUTO_BOARDFAMILY}" ]]; then
                ARGS+=("boardfamily/${AUTO_BOARDFAMILY}")
                shift
            else
                ARGS+=("-m" "boardfamily")
                shift
            fi
            ;;
        --board)
            EXPLICIT_TARGET=1
            if [[ -n "$2" && "$2" != --* ]]; then
                ARGS+=("board/$2")
                shift 2
            elif [[ -n "${AUTO_BOARD}" ]]; then
                ARGS+=("board/${AUTO_BOARD}")
                shift
            else
                ARGS+=("-m" "board")
                shift
            fi
            ;;
        --interactive)

            ARGS+=("--interactive")
            shift
            ;;
        --iperf)
            ARGS+=("--iperf-server" "$2")
            shift 2
            ;;
        --usb-mount)
            ARGS+=("--usb-mount" "$2")
            shift 2
            ;;
        *)
            # If user provided a specific path or pytest option
            if [[ "$1" == boardfamily/* || "$1" == soc/* || "$1" == board/* ]]; then
                EXPLICIT_TARGET=1
            fi
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Run setup scripts for detected hardware unless explicitly skipped
if [[ ${SKIP_SETUP} -eq 0 ]]; then
    if [[ -n "${AUTO_BOARDFAMILY}" && -x "boardfamily/${AUTO_BOARDFAMILY}/setup.sh" ]]; then
        echo "--> Running Boardfamily setup: boardfamily/${AUTO_BOARDFAMILY}/setup.sh"
        bash "boardfamily/${AUTO_BOARDFAMILY}/setup.sh" || echo "WARNING: Boardfamily setup returned code $?"
    fi
    if [[ -n "${AUTO_BOARD}" && -x "board/${AUTO_BOARD}/setup.sh" ]]; then
        echo "--> Running Board setup: board/${AUTO_BOARD}/setup.sh"
        bash "board/${AUTO_BOARD}/setup.sh" || echo "WARNING: Board setup returned code $?"
    fi
fi

# If no target was explicitly specified, use auto-detected targets for the current board
if [[ ${EXPLICIT_TARGET} -eq 0 ]]; then
    TARGET_PATHS=()
    if [[ -n "${AUTO_BOARDFAMILY}" && -d "boardfamily/${AUTO_BOARDFAMILY}" ]]; then
        TARGET_PATHS+=("boardfamily/${AUTO_BOARDFAMILY}")
    fi
    if [[ -n "${AUTO_BOARD}" && -d "board/${AUTO_BOARD}" ]]; then
        TARGET_PATHS+=("board/${AUTO_BOARD}")
    fi
    if [[ ${#TARGET_PATHS[@]} -eq 0 ]]; then
        echo "Error: Could not auto-detect a matching board or boardfamily test suite." >&2
        echo "Detected Boardfamily: ${AUTO_BOARDFAMILY:-none}" >&2
        echo "Detected Board:       ${AUTO_BOARD:-none}" >&2
        echo "Please specify a target (e.g. --board orangepi4pro or path/to/test.py)." >&2
        exit 1
    fi
    ARGS=("${TARGET_PATHS[@]}" "${ARGS[@]}")
fi

# Default --usb-mount if /mnt/usb is mounted and not specified
if [[ ! " ${ARGS[*]} " =~ " --usb-mount " ]] && mountpoint -q /mnt/usb 2>/dev/null; then
    ARGS+=("--usb-mount" "/mnt/usb")
fi

# In interactive mode, disable pytest stdout/stdin capture (-s) so prompts are visible and can receive input
if [[ " ${ARGS[*]} " =~ " --interactive " ]] && [[ ! " ${ARGS[*]} " =~ " -s " && ! " ${ARGS[*]} " =~ " --capture=no " ]]; then
    ARGS+=("-s")
fi


echo "================================================="
echo "Target Peripheral Validation Suite"
echo "Root directory:       ${SCRIPT_DIR}"
echo "Detected Boardfamily: ${AUTO_BOARDFAMILY:-'(none detected)'}"
echo "Detected Board:       ${AUTO_BOARD:-'(none detected)'}"
echo "Test Targets:         ${ARGS[*]:-(all non-interactive)}"
echo "================================================="

python3 -m pytest "${ARGS[@]}"
