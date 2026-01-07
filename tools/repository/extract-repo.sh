#!/usr/bin/env bash

# Extract packages from an existing Debian repository and organize them
# into the input structure expected by repo.sh
#
# Expected input structure:
#   /root/*.deb                    -> main component (common across releases)
#   /extra/{release}-utils/*.deb   -> release-specific utils
#   /extra/{release}-desktop/*.deb -> release-specific desktop

set -e

# Default values
REPO_URL=""
OUTPUT_DIR=""
RELEASES=()
VERBOSE=false
DRY_RUN=false

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        log "$*"
    fi
}

# Display help
show_help() {
    cat << EOF
Extract packages from an existing Debian repository and organize them
for use as input to repo.sh

Usage: $0 -u <repo_url> -o <output_dir> [options]

Required:
  -u, --url <path>              Repository path (local directory)
  -o, --output <dir>            Output directory for extracted packages

Optional:
  -r, --releases <list>         Comma-separated list of releases to extract
                                (default: auto-detect from repository)
  -v, --verbose                 Verbose output
  --dry-run                     Show what would be done without actually doing it
  -h, --help                    Show this help

Output Structure:
  {output_dir}/
    *.deb                       -> Packages for 'main' component
    extra/
      {release}-utils/          -> Release-specific utils packages
        *.deb
      {release}-desktop/        -> Release-specific desktop packages
        *.deb

Examples:
  # Extract from local repository
  $0 -u /path/to/repo/public -o /tmp/extracted

  # Extract specific releases only
  $0 -u /path/to/repo/public -o /tmp/extracted -r jammy,noble,bookworm

  # Dry-run to see what would be extracted
  $0 -u /path/to/repo/public -o /tmp/extracted --dry-run

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--url)
                REPO_URL="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -r|--releases)
                IFS=',' read -r -a RELEASES <<< "$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$REPO_URL" ]]; then
        echo "Error: Repository URL is required"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "Error: Output directory is required"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    if [[ ! -d "$REPO_URL" ]]; then
        echo "Error: Repository path does not exist: $REPO_URL"
        exit 1
    fi
}

# Detect releases from repository
detect_releases() {
    local repo_base="$1"

    log "Detecting releases from repository..."

    if [[ -d "$repo_base/dists" ]]; then
        # Capture find/basename output and check for errors
        local releases_output
        local releases_exit_code
        releases_output=$(find "$repo_base/dists" -maxdepth 1 -type d -not -name "dists" -exec basename {} \; 2>&1 | sort)
        releases_exit_code=$?

        if [[ $releases_exit_code -ne 0 ]]; then
            log "Error: Failed to detect releases (find exit code: $releases_exit_code)" >&2
            log "Output: $releases_output" >&2
            DETECTED_RELEASES=()
            return 1
        fi

        # Check if output is non-empty before feeding to mapfile
        if [[ -n "$releases_output" ]]; then
            mapfile -t DETECTED_RELEASES <<< "$releases_output"
        else
            DETECTED_RELEASES=()
        fi
    else
        DETECTED_RELEASES=()
    fi

    if [[ ${#DETECTED_RELEASES[@]} -eq 0 ]]; then
        log "Warning: Could not auto-detect releases"
        DETECTED_RELEASES=()
    else
        log "Detected releases: ${DETECTED_RELEASES[*]}"
    fi
}

# Copy all .deb files from a directory recursively
copy_debs_from_dir() {
    local source_dir="$1"
    local target_dir="$2"

    if [[ ! -d "$source_dir" ]]; then
        return
    fi

    # Find all .deb files recursively in the source directory
    while IFS= read -r -d '' deb_file; do
        echo "$deb_file"
    done < <(find "$source_dir" -type f -name "*.deb" -print0 2>/dev/null)
}

# Extract packages from repository
extract_packages() {
    local repo_base="$1"
    local output_base="$2"

    log "Starting package extraction..."
    log "Repository: $repo_base"
    log "Output: $output_base"

    # Create output directories
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$output_base/extra"
    fi

    local total_packages=0
    local copied_packages=0
    local skipped_packages=0
    local error_packages=0

    # Determine which releases to process
    local releases_to_process=()
    if [[ ${#RELEASES[@]} -gt 0 ]]; then
        releases_to_process=("${RELEASES[@]}")
    else
        if [[ ${#DETECTED_RELEASES[@]} -eq 0 ]]; then
            detect_releases "$repo_base"
        fi
        releases_to_process=("${DETECTED_RELEASES[@]}")
    fi

    if [[ ${#releases_to_process[@]} -eq 0 ]]; then
        log "Error: No releases found to process"
        exit 1
    fi

    log "Processing releases: ${releases_to_process[*]}"

    # Process each release
    for release in "${releases_to_process[@]}"; do
        log "Processing release: $release"

        # Define components to check
        # 'main' component has packages that go to root
        # '{release}-utils' and '{release}-desktop' have release-specific packages
        local components=("main" "${release}-utils" "${release}-desktop")

        for component in "${components[@]}"; do
            log_verbose "Processing component: $release/$component"

            # Determine source and target directories
            local source_dir=""
            local target_dir=""

            if [[ "$component" == "main" ]]; then
                # Main component packages go to root
                source_dir="$repo_base/pool/main"
                target_dir="$output_base"
            else
                # Release-specific components go to extra/
                source_dir="$repo_base/pool/$component"
                target_dir="$output_base/extra/$component"
                if [[ "$DRY_RUN" == false ]]; then
                    mkdir -p "$target_dir"
                fi
            fi

            if [[ ! -d "$source_dir" ]]; then
                log_verbose "Source directory not found: $source_dir"
                continue
            fi

            # Get list of all .deb files recursively
            mapfile -t packages < <(copy_debs_from_dir "$source_dir" "$target_dir")

            if [[ ${#packages[@]} -eq 0 ]]; then
                log_verbose "No packages found in $source_dir"
                continue
            fi

            log "Found ${#packages[@]} packages in $source_dir"

            # Process each package
            for source_path in "${packages[@]}"; do
                ((total_packages++)) || true

                local package_name=$(basename "$source_path")
                local target_path="$target_dir/$package_name"

                # Copy package
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would copy: $package_name -> $target_dir"
                    ((copied_packages++)) || true
                else
                    if [[ -f "$source_path" ]]; then
                        # Check if file already exists and is identical
                        if [[ -f "$target_path" ]]; then
                            # Compare files
                            if cmp -s "$source_path" "$target_path"; then
                                log_verbose "Skipping (identical): $package_name"
                                ((skipped_packages++)) || true
                            else
                                log_verbose "Copying (updated): $package_name"
                                # Try hard link first, fall back to copy
                                cp -l "$source_path" "$target_path" 2>/dev/null || cp "$source_path" "$target_path"
                                ((copied_packages++)) || true
                            fi
                        else
                            log_verbose "Copying: $package_name"
                            # Try hard link first, fall back to copy
                            cp -l "$source_path" "$target_path" 2>/dev/null || cp "$source_path" "$target_path"
                            ((copied_packages++)) || true
                        fi
                    else
                        log "Warning: Source file not found: $source_path"
                        ((error_packages++)) || true
                    fi
                fi
            done
        done
    done

    # Print summary
    log "=========================================="
    log "Extraction complete!"
    log "Total packages found: $total_packages"
    log "Packages copied: $copied_packages"
    log "Packages skipped: $skipped_packages"
    if [[ $error_packages -gt 0 ]]; then
        log "Packages with errors: $error_packages"
    fi
    log "Output directory: $output_base"
    log "=========================================="

    # Show output structure
    if [[ "$DRY_RUN" == false ]] && [[ -d "$output_base" ]]; then
        log ""
        log "Output structure:"
        find "$output_base" -maxdepth 2 -type d | sed 's|'"$output_base"'||' | sort | while read -r dir; do
            if [[ -n "$dir" ]]; then
                local count=$(find "$output_base$dir" -maxdepth 1 -name "*.deb" 2>/dev/null | wc -l)
                if [[ $count -gt 0 ]]; then
                    log "  $dir: $count packages"
                fi
            fi
        done
    fi
}

# Main execution
main() {
    parse_args "$@"

    # Normalize repository URL
    local repo_base="$REPO_URL"
    # Remove trailing slash
    repo_base="${repo_base%/}"

    # Auto-detect releases if not specified
    if [[ ${#RELEASES[@]} -eq 0 ]]; then
        detect_releases "$repo_base"
        RELEASES=("${DETECTED_RELEASES[@]}")
    fi

    log "Repository extraction configuration:"
    log "  Source: $repo_base"
    log "  Output: $OUTPUT_DIR"
    log "  Releases: ${RELEASES[*]:-auto-detect}"
    log "  Dry-run: $DRY_RUN"
    log ""

    # Perform extraction
    extract_packages "$repo_base" "$OUTPUT_DIR"
}

# Run main function
main "$@"
