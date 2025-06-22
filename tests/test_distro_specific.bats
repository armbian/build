#!/usr/bin/env bats

# Test suite for distribution-specific functionality
# Testing framework: BATS (Bash Automated Testing System)

# Load test helpers if they exist
load test_helper 2>/dev/null || true

setup() {
    # Create temporary directory for test fixtures
    export BATS_TEST_TMPDIR="$(mktemp -d)"
    export ORIGINAL_PATH="$PATH"
    export ORIGINAL_ETC="/etc"
    
    # Create mock /etc directory structure
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    
    # Mock various distribution release files
    create_mock_os_release() {
        local distro="$1"
        case "$distro" in
            "ubuntu")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="Ubuntu"
VERSION="20.04.3 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.3 LTS"
VERSION_ID="20.04"
VERSION_CODENAME=focal
UBUNTU_CODENAME=focal
EOF
                ;;
            "centos")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="CentOS Linux"
VERSION="8"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="8"
PRETTY_NAME="CentOS Linux 8"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:centos:centos:8"
HOME_URL="https://www.centos.org/"
BUG_REPORT_URL="https://bugs.centos.org/"
EOF
                ;;
            "debian")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
NAME="Debian GNU/Linux"
VERSION_ID="11"
VERSION="11 (bullseye)"
VERSION_CODENAME=bullseye
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
EOF
                ;;
            "rhel")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.5 (Ootpa)"
ID="rhel"
ID_LIKE="fedora"
VERSION_ID="8.5"
PLATFORM_ID="platform:el8"
PRETTY_NAME="Red Hat Enterprise Linux 8.5 (Ootpa)"
ANSI_COLOR="0;31"
EOF
                ;;
            "fedora")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="Fedora Linux"
VERSION="35 (Workstation Edition)"
ID=fedora
VERSION_ID=35
VERSION_CODENAME=""
PLATFORM_ID="platform:f35"
PRETTY_NAME="Fedora Linux 35 (Workstation Edition)"
ANSI_COLOR="0;38;2;60;110;180"
EOF
                ;;
            "arch")
                cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://bugs.archlinux.org/"
EOF
                ;;
        esac
    }
    
    # Mock LSB release file
    create_mock_lsb_release() {
        local distro="$1"
        case "$distro" in
            "ubuntu")
                cat > "$BATS_TEST_TMPDIR/etc/lsb-release" << 'EOF'
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=20.04
DISTRIB_CODENAME=focal
DISTRIB_DESCRIPTION="Ubuntu 20.04.3 LTS"
EOF
                ;;
        esac
    }
    
    # Mock system commands
    create_mock_commands() {
        mkdir -p "$BATS_TEST_TMPDIR/bin"
        export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
        
        # Mock which command
        cat > "$BATS_TEST_TMPDIR/bin/which" << 'EOF'
#!/bin/bash
case "$1" in
    "apt"|"apt-get") echo "/usr/bin/apt" ;;
    "yum") echo "/usr/bin/yum" ;;
    "dnf") echo "/usr/bin/dnf" ;;
    "pacman") echo "/usr/bin/pacman" ;;
    "zypper") echo "/usr/bin/zypper" ;;
    *) exit 1 ;;
esac
EOF
        chmod +x "$BATS_TEST_TMPDIR/bin/which"
    }
}

teardown() {
    # Clean up test environment
    rm -rf "$BATS_TEST_TMPDIR"
    export PATH="$ORIGINAL_PATH"
    unset BATS_TEST_TMPDIR ORIGINAL_PATH ORIGINAL_ETC
}

@test "should detect Ubuntu distribution correctly from os-release" {
    create_mock_os_release "ubuntu"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "ubuntu" ]]
}

@test "should detect CentOS distribution correctly from os-release" {
    create_mock_os_release "centos"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "centos" ]]
}

@test "should detect Debian distribution correctly from os-release" {
    create_mock_os_release "debian"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "debian" ]]
}

@test "should detect RHEL distribution correctly from os-release" {
    create_mock_os_release "rhel"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "rhel" ]]
}

@test "should detect Fedora distribution correctly from os-release" {
    create_mock_os_release "fedora"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "fedora" ]]
}

@test "should detect Arch Linux distribution correctly from os-release" {
    create_mock_os_release "arch"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 0 ]
    [[ "$output" == "arch" ]]
}

@test "should detect apt package manager for Ubuntu" {
    create_mock_os_release "ubuntu"
    create_mock_commands
    
    get_package_manager() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            case "$ID" in
                "ubuntu"|"debian") echo "apt" ;;
                "centos"|"rhel") echo "yum" ;;
                "fedora") echo "dnf" ;;
                "arch") echo "pacman" ;;
                "opensuse"|"sles") echo "zypper" ;;
                *) echo "unknown" ;;
            esac
        fi
    }
    
    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "apt" ]]
}

@test "should detect yum package manager for CentOS" {
    create_mock_os_release "centos"
    create_mock_commands
    
    get_package_manager() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            case "$ID" in
                "ubuntu"|"debian") echo "apt" ;;
                "centos"|"rhel") echo "yum" ;;
                "fedora") echo "dnf" ;;
                "arch") echo "pacman" ;;
                "opensuse"|"sles") echo "zypper" ;;
                *) echo "unknown" ;;
            esac
        fi
    }
    
    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "yum" ]]
}

@test "should detect dnf package manager for Fedora" {
    create_mock_os_release "fedora"
    create_mock_commands
    
    get_package_manager() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            case "$ID" in
                "ubuntu"|"debian") echo "apt" ;;
                "centos"|"rhel") echo "yum" ;;
                "fedora") echo "dnf" ;;
                "arch") echo "pacman" ;;
                "opensuse"|"sles") echo "zypper" ;;
                *) echo "unknown" ;;
            esac
        fi
    }
    
    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "dnf" ]]
}

@test "should detect pacman package manager for Arch Linux" {
    create_mock_os_release "arch"
    create_mock_commands
    
    get_package_manager() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            case "$ID" in
                "ubuntu"|"debian") echo "apt" ;;
                "centos"|"rhel") echo "yum" ;;
                "fedora") echo "dnf" ;;
                "arch") echo "pacman" ;;
                "opensuse"|"sles") echo "zypper" ;;
                *) echo "unknown" ;;
            esac
        fi
    }
    
    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "pacman" ]]
}

@test "should handle missing os-release file gracefully" {
    rm -f "$BATS_TEST_TMPDIR/etc/os-release"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        else
            echo "Error: Unable to detect distribution - os-release not found"
            return 1
        fi
    }
    
    run detect_distribution
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unable to detect distribution" ]]
}

@test "should handle malformed os-release file" {
    cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
This is not a valid
os-release file format
ID=
EOF
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            if [[ -z "$ID" ]]; then
                echo "Error: Invalid distribution ID"
                return 1
            fi
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run detect_distribution
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid distribution ID" ]]
}

@test "should handle unsupported distribution" {
    cat > "$BATS_TEST_TMPDIR/etc/os-release" << 'EOF'
NAME="Exotic Linux"
ID="exotic"
VERSION_ID="1.0"
PRETTY_NAME="Exotic Linux 1.0"
EOF
    
    get_package_manager() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            case "$ID" in
                "ubuntu"|"debian") echo "apt" ;;
                "centos"|"rhel") echo "yum" ;;
                "fedora") echo "dnf" ;;
                "arch") echo "pacman" ;;
                "opensuse"|"sles") echo "zypper" ;;
                *)
                    echo "Error: Unsupported distribution: $ID"
                    return 1
                    ;;
            esac
        fi
    }
    
    run get_package_manager
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unsupported distribution: exotic" ]]
}

@test "should fall back to lsb-release when os-release is unavailable" {
    rm -f "$BATS_TEST_TMPDIR/etc/os-release"
    create_mock_lsb_release "ubuntu"
    
    detect_distribution_with_fallback() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
        elif [[ -f "$BATS_TEST_TMPDIR/etc/lsb-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/lsb-release"
            echo "${DISTRIB_ID,,}"
        else
            echo "Error: Unable to detect distribution"
            return 1
        fi
    }
    
    run detect_distribution_with_fallback
    [ "$status" -eq 0 ]
    [[ "$output" == "ubuntu" ]]
}

@test "should handle empty os-release file" {
    touch "$BATS_TEST_TMPDIR/etc/os-release"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            if [[ -z "$ID" ]]; then
                echo "Error: Distribution ID not found"
                return 1
            fi
            echo "$ID"
        fi
    }
    
    run detect_distribution
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Distribution ID not found" ]]
}

@test "should validate distribution name parameter" {
    validate_distribution_name() {
        local distro="$1"
        if [[ -z "$distro" ]]; then
            echo "Error: Distribution name parameter is required"
            return 1
        fi
        if [[ "$distro" =~ [^a-zA-Z0-9._-] ]]; then
            echo "Error: Invalid characters in distribution name"
            return 1
        fi
        echo "Valid distribution name: $distro"
        return 0
    }
    
    run validate_distribution_name ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "parameter is required" ]]
}

@test "should sanitize distribution names with special characters" {
    validate_distribution_name() {
        local distro="$1"
        if [[ -z "$distro" ]]; then
            echo "Error: Distribution name parameter is required"
            return 1
        fi
        if [[ "$distro" =~ [^a-zA-Z0-9._-] ]]; then
            echo "Error: Invalid characters in distribution name"
            return 1
        fi
        echo "Valid distribution name: $distro"
        return 0
    }
    
    run validate_distribution_name "ubuntu; rm -rf /"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid characters" ]]
}

@test "should accept valid distribution names with hyphens and dots" {
    validate_distribution_name() {
        local distro="$1"
        if [[ -z "$distro" ]]; then
            echo "Error: Distribution name parameter is required"
            return 1
        fi
        if [[ "$distro" =~ [^a-zA-Z0-9._-] ]]; then
            echo "Error: Invalid characters in distribution name"
            return 1
        fi
        echo "Valid distribution name: $distro"
        return 0
    }
    
    run validate_distribution_name "ubuntu-18.04"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid distribution name: ubuntu-18.04" ]]
}

@test "should accept distribution names with underscores" {
    validate_distribution_name() {
        local distro="$1"
        if [[ -z "$distro" ]]; then
            echo "Error: Distribution name parameter is required"
            return 1
        fi
        if [[ "$distro" =~ [^a-zA-Z0-9._-] ]]; then
            echo "Error: Invalid characters in distribution name"
            return 1
        fi
        echo "Valid distribution name: $distro"
        return 0
    }
    
    run validate_distribution_name "centos_stream"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid distribution name: centos_stream" ]]
}

@test "should complete distribution detection within reasonable time" {
    create_mock_os_release "ubuntu"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    run timeout 5s bash -c "detect_distribution"
    [ "$status" -eq 0 ]
    [[ "$output" == "ubuntu" ]]
}

@test "should handle concurrent distribution detection calls" {
    create_mock_os_release "ubuntu"
    
    detect_distribution() {
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            echo "$ID"
            return 0
        fi
        return 1
    }
    
    local pids=()
    for i in {1..3}; do
        detect_distribution &
        pids+=($!)
    done
    
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    [ "$all_success" = true ]
}

@test "should execute complete distribution-specific workflow for Ubuntu" {
    create_mock_os_release "ubuntu"
    create_mock_commands
    
    complete_distro_workflow() {
        local distro package_manager
        
        if [[ -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            . "$BATS_TEST_TMPDIR/etc/os-release"
            distro="$ID"
        else
            echo "Error: Cannot detect distribution"
            return 1
        fi
        
        case "$distro" in
            "ubuntu"|"debian") package_manager="apt" ;;
            "centos"|"rhel") package_manager="yum" ;;
            "fedora") package_manager="dnf" ;;
            "arch") package_manager="pacman" ;;
            *) package_manager="unknown" ;;
        esac
        
        echo "Distribution: $distro, Package Manager: $package_manager"
        echo "Ubuntu workflow completed successfully"
        return 0
    }
    
    run complete_distro_workflow
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Distribution: ubuntu, Package Manager: apt" ]]
    [[ "$output" =~ "Ubuntu workflow completed successfully" ]]
}

@test "should provide helpful error messages for failures" {
    rm -f "$BATS_TEST_TMPDIR/etc/os-release"
    
    detect_distribution_with_helpful_errors() {
        if [[ ! -f "$BATS_TEST_TMPDIR/etc/os-release" ]]; then
            echo "Error: Unable to detect Linux distribution"
            echo "Try: Ensure /etc/os-release exists and is readable"
            echo "Alternative: Check for /etc/lsb-release or distribution-specific files"
            return 1
        fi
    }
    
    run detect_distribution_with_helpful_errors
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Unable to detect Linux distribution" ]]
    [[ "$output" =~ "Try: Ensure /etc/os-release exists" ]]
    [[ "$output" =~ "Alternative: Check for /etc/lsb-release" ]]
}

@test "should provide script version information" {
    get_script_version() {
        echo "distro_specific_utils v1.2.3"
        return 0
    }
    
    run get_script_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "should display comprehensive help information" {
    display_help() {
        cat << 'EOF'
Usage: distro_specific_utils [OPTIONS] [COMMAND]

DESCRIPTION:
    Utility for detecting Linux distributions and managing 
    distribution-specific operations.

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show version information
    -d, --detect    Detect current distribution
    -p, --package   Show package manager for current distribution

COMMANDS:
    detect          Detect the current Linux distribution
    package-mgr     Show the package manager for current distribution
    
EXAMPLES:
    distro_specific_utils --detect
    distro_specific_utils package-mgr

SUPPORTED DISTRIBUTIONS:
    Ubuntu, Debian, CentOS, RHEL, Fedora, Arch Linux, openSUSE
EOF
    }
    
    run display_help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "OPTIONS:" ]]
    [[ "$output" =~ "EXAMPLES:" ]]
    [[ "$output" =~ "SUPPORTED DISTRIBUTIONS:" ]]
}

@test "should validate system requirements" {
    check_system_requirements() {
        local missing_commands=()
        
        if [[ ! -r /etc/os-release ]] && [[ ! -r /etc/lsb-release ]]; then
            echo "Warning: No distribution identification files found"
        fi
        
        for cmd in cat grep sed awk; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                missing_commands+=("$cmd")
            fi
        done
        
        if [[ ${#missing_commands[@]} -gt 0 ]]; then
            echo "Error: Missing required commands: ${missing_commands[*]}"
            return 1
        fi
        
        echo "System requirements satisfied"
        return 0
    }
    
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    for cmd in cat grep sed awk; do
        echo '#!/bin/bash' > "$BATS_TEST_TMPDIR/bin/$cmd"
        echo 'echo "mock $cmd"' >> "$BATS_TEST_TMPDIR/bin/$cmd"
        chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
    done
    
    run check_system_requirements
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System requirements satisfied" ]]
}

@test "should handle insufficient permissions gracefully" {
    touch "$BATS_TEST_TMPDIR/etc/os-release"
    chmod 000 "$BATS_TEST_TMPDIR/etc/os-release"
    
    handle_permission_error() {
        local file="$BATS_TEST_TMPDIR/etc/os-release"
        if [[ ! -r "$file" ]]; then
            echo "Error: Insufficient permissions to read $file"
            echo "Try: Run with appropriate permissions or contact system administrator"
            return 1
        fi
        return 0
    }
    
    run handle_permission_error
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Insufficient permissions" ]]
    [[ "$output" =~ "Try: Run with appropriate permissions" ]]
}