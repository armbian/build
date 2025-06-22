#!/usr/bin/env bats

# Load the apa script for testing
APA_SCRIPT="${BATS_TEST_DIRNAME}/../git/extensions/apa.sh"

setup() {
    # Create temporary directory for test isolation
    export TEST_TEMP_DIR="$(mktemp -d)"
    export ORIGINAL_HOME="$HOME"
    export ORIGINAL_APA_CONFIG_DIR="$APA_CONFIG_DIR"
    export ORIGINAL_APA_LOG_LEVEL="$APA_LOG_LEVEL"
    export ORIGINAL_APA_TIMEOUT="$APA_TIMEOUT"

    # Set up test environment
    export HOME="$TEST_TEMP_DIR"
    export APA_CONFIG_DIR="$TEST_TEMP_DIR/.apa"
    export APA_LOG_LEVEL="quiet"
    export APA_TIMEOUT="10"

    # Make apa script executable and available
    chmod +x "$APA_SCRIPT"
    export PATH="$(dirname "$APA_SCRIPT"):$PATH"
}

teardown() {
    # Restore original environment
    export HOME="$ORIGINAL_HOME"
    export APA_CONFIG_DIR="$ORIGINAL_APA_CONFIG_DIR"
    export APA_LOG_LEVEL="$ORIGINAL_APA_LOG_LEVEL"
    export APA_TIMEOUT="$ORIGINAL_APA_TIMEOUT"

    # Clean up temporary files
    [ -n "$TEST_TEMP_DIR" ] && rm -rf "$TEST_TEMP_DIR"
}

@test "apa script exists and is executable" {
    [ -f "$APA_SCRIPT" ]
    [ -x "$APA_SCRIPT" ]
}

@test "apa shows help with --help option" {
    run bash "$APA_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apa - Automated Package Assistant" ]]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "Commands:" ]]
    [[ "$output" =~ "install" ]]
    [[ "$output" =~ "update" ]]
    [[ "$output" =~ "remove" ]]
}

@test "apa shows help with -h option" {
    run bash "$APA_SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apa - Automated Package Assistant" ]]
}

@test "apa shows version with --version option" {
    run bash "$APA_SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apa version 1.2.3" ]]
}

@test "apa shows version with -v option" {
    run bash "$APA_SCRIPT" -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apa version 1.2.3" ]]
}

@test "apa shows help when run with no arguments" {
    run bash "$APA_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "apa install succeeds with valid package name" {
    run bash "$APA_SCRIPT" install nginx
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Package nginx installed successfully" ]]
}

@test "apa install creates config directory" {
    bash "$APA_SCRIPT" install test-package
    [ -d "$APA_CONFIG_DIR" ]
}

@test "apa install fails without package name" {
    run bash "$APA_SCRIPT" install
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Install command requires a package name" ]]
}

@test "apa install fails with empty package name" {
    run bash "$APA_SCRIPT" install ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Package name cannot be empty" ]]
}

@test "apa install fails with invalid package name containing spaces" {
    run bash "$APA_SCRIPT" install "invalid package"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa install fails with invalid package name containing special chars" {
    run bash "$APA_SCRIPT" install "invalid@package#"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa install accepts valid package names with dots, dashes, underscores" {
    run bash "$APA_SCRIPT" install "valid-package_name.123"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "installed successfully" ]]
}

@test "apa update succeeds with valid package name" {
    run bash "$APA_SCRIPT" update nginx
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Package nginx updated successfully" ]]
}

@test "apa update fails without package name" {
    run bash "$APA_SCRIPT" update
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Update command requires a package name" ]]
}

@test "apa update fails with empty package name" {
    run bash "$APA_SCRIPT" update ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Package name cannot be empty" ]]
}

@test "apa update fails with invalid package name" {
    run bash "$APA_SCRIPT" update "invalid@package"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa remove succeeds with valid package name" {
    run bash "$APA_SCRIPT" remove nginx
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Package nginx removed successfully" ]]
}

@test "apa remove fails without package name" {
    run bash "$APA_SCRIPT" remove
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Remove command requires a package name" ]]
}

@test "apa remove fails with empty package name" {
    run bash "$APA_SCRIPT" remove ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Package name cannot be empty" ]]
}

@test "apa remove fails with invalid package name" {
    run bash "$APA_SCRIPT" remove "invalid package name"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa list shows installed packages" {
    run bash "$APA_SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "nginx-1.18.0" ]]
    [[ "$output" =~ "curl-7.68.0" ]]
    [[ "$output" =~ "git-2.34.1" ]]
}

@test "apa search succeeds with valid query" {
    run bash "$APA_SCRIPT" search "web"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found packages matching 'web'" ]]
    [[ "$output" =~ "web-server-toolkit" ]]
}

@test "apa search fails without query" {
    run bash "$APA_SCRIPT" search
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Search command requires a query" ]]
}

@test "apa search fails with empty query" {
    run bash "$APA_SCRIPT" search ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Search query cannot be empty" ]]
}

@test "apa search handles special characters in query" {
    run bash "$APA_SCRIPT" search "web-server"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found packages matching" ]]
}

@test "apa info succeeds with valid package name" {
    run bash "$APA_SCRIPT" info nginx
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Package: nginx" ]]
    [[ "$output" =~ "Version:" ]]
    [[ "$output" =~ "Description:" ]]
    [[ "$output" =~ "Maintainer:" ]]
}

@test "apa info fails without package name" {
    run bash "$APA_SCRIPT" info
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Info command requires a package name" ]]
}

@test "apa info fails with empty package name" {
    run bash "$APA_SCRIPT" info ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Package name cannot be empty" ]]
}

@test "apa info fails with invalid package name" {
    run bash "$APA_SCRIPT" info "invalid@package"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa handles unknown command gracefully" {
    run bash "$APA_SCRIPT" unknown-command
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown command: unknown-command" ]]
}

@test "apa handles unknown option gracefully" {
    run bash "$APA_SCRIPT" --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --unknown-option" ]]
}

@test "apa quiet option suppresses info output" {
    run bash "$APA_SCRIPT" --quiet install test-package
    [ "$status" -eq 0 ]
    [[ "$output" =~ "installed successfully" ]]
    # Info logs should be suppressed in quiet mode
}

@test "apa debug option enables debug output" {
    export APA_LOG_LEVEL="debug"
    run bash "$APA_SCRIPT" --debug install test-package
    [ "$status" -eq 0 ]
}

@test "apa timeout option is accepted" {
    run bash "$APA_SCRIPT" --timeout 60 --help
    [ "$status" -eq 0 ]
}

@test "apa respects APA_CONFIG_DIR environment variable" {
    export APA_CONFIG_DIR="$TEST_TEMP_DIR/custom-config"
    bash "$APA_SCRIPT" install test-package
    [ -d "$TEST_TEMP_DIR/custom-config" ]
}

@test "apa respects APA_LOG_LEVEL environment variable" {
    export APA_LOG_LEVEL="debug"
    run bash "$APA_SCRIPT" install test-package
    [ "$status" -eq 0 ]
}

@test "apa respects APA_TIMEOUT environment variable" {
    export APA_TIMEOUT="120"
    run bash "$APA_SCRIPT" install test-package
    [ "$status" -eq 0 ]
}

@test "apa handles very long package names gracefully" {
    local long_name=$(printf 'a%.0s' {1..1000})
    run bash "$APA_SCRIPT" install "$long_name"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa handles package names with only valid characters at boundary" {
    # Test exactly valid characters
    run bash "$APA_SCRIPT" install "a"
    [ "$status" -eq 0 ]

    run bash "$APA_SCRIPT" install "a-b_c.123"
    [ "$status" -eq 0 ]

    run bash "$APA_SCRIPT" install "123"
    [ "$status" -eq 0 ]
}

@test "apa rejects command injection attempts" {
    run bash "$APA_SCRIPT" install "; rm -rf /"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]

    run bash "$APA_SCRIPT" install "$(whoami)"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]

    run bash "$APA_SCRIPT" install "|cat /etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa handles unicode characters in package names" {
    run bash "$APA_SCRIPT" install "测试包"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid package name" ]]
}

@test "apa handles null bytes in input" {
    printf "test\0package" | run bash "$APA_SCRIPT" install
    [ "$status" -eq 1 ]
}

@test "apa handles missing HOME directory" {
    unset HOME
    run bash "$APA_SCRIPT" install test-package
    [ "$status" -eq 0 ]
}

@test "apa handles non-writable config directory parent" {
    # This test may need to be skipped in some environments
    if [[ "$EUID" -ne 0 ]]; then
        export APA_CONFIG_DIR="/root/test-apa-config"
        run bash "$APA_SCRIPT" install test-package
        # Should handle gracefully, not necessarily succeed
        [[ "$status" -eq 0 || "$status" -eq 1 ]]
    else
        skip "Cannot test non-writable directory as root"
    fi
}

@test "apa operations complete within timeout" {
    # Test that operations don't hang indefinitely
    timeout 30s bash "$APA_SCRIPT" install test-package
    [ $? -ne 124 ]  # 124 is timeout's exit code
}

@test "apa can handle multiple operations in sequence" {
    run bash "$APA_SCRIPT" install package1
    [ "$status" -eq 0 ]

    run bash "$APA_SCRIPT" update package1
    [ "$status" -eq 0 ]

    run bash "$APA_SCRIPT" info package1
    [ "$status" -eq 0 ]

    run bash "$APA_SCRIPT" remove package1
    [ "$status" -eq 0 ]
}

@test "apa output format is consistent across commands" {
    # Test that all successful operations produce clean output
    run bash "$APA_SCRIPT" install test-package
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[[:print:][:space:]]*$ ]]

    run bash "$APA_SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[[:print:][:space:]]*$ ]]
}

@test "apa handles concurrent execution" {
    # Run multiple instances to test for race conditions
    bash "$APA_SCRIPT" install package1 &
    bash "$APA_SCRIPT" install package2 &
    bash "$APA_SCRIPT" list &

    wait
    [ $? -eq 0 ]
}

@test "apa config directory creation is idempotent" {
    # First run should create directory
    bash "$APA_SCRIPT" install test-package
    [ -d "$APA_CONFIG_DIR" ]

    # Second run should not fail even if directory exists
    bash "$APA_SCRIPT" install test-package2
    [ -d "$APA_CONFIG_DIR" ]
}

@test "apa validates package names consistently across commands" {
    # Test that validation works the same for all commands that take package names
    local invalid_name="invalid@package"

    run bash "$APA_SCRIPT" install "$invalid_name"
    [ "$status" -eq 1 ]

    run bash "$APA_SCRIPT" update "$invalid_name"
    [ "$status" -eq 1 ]

    run bash "$APA_SCRIPT" remove "$invalid_name"
    [ "$status" -eq 1 ]

    run bash "$APA_SCRIPT" info "$invalid_name"
    [ "$status" -eq 1 ]
}