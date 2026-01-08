#!/usr/bin/env bash
#
# cleanup-debs.sh
#
# Recursively clean Armbian Debian package artifacts.
#
# This script scans the given directory (and all subdirectories) for
# Debian packages whose filenames start with `armbian-` and end with `.deb`.
#
# For each logical package base (the part of the filename before the first
# underscore), it keeps only the newest version as determined by
# `dpkg --compare-versions` and removes all older versions.
#
# Key properties:
#   - Operates recursively on all subfolders
#   - Affects ONLY files matching `armbian-*.deb`
#   - Keeps the most recent version per package base
#   - Uses proper Debian version comparison (not lexical sorting)
#   - Safe by default: dry-run mode enabled unless DRYRUN=0 is set
#
# Usage:
#   ./armbian-deb-cleanup.sh /path/to/repository
#
# To actually delete files:
#   DRYRUN=0 ./armbian-deb-cleanup.sh /path/to/repository
#
# Notes:
#   - If the same package exists in multiple subdirectories, only the newest
#     version is kept globally (not per directory).
#   - Files not matching `armbian-*.deb` are ignored.
#
set -euo pipefail

ROOT="${1:-.}"
DRYRUN="${DRYRUN:-1}"   # DRYRUN=0 to actually delete

shopt -s nullglob

declare -A best_ver best_file

# Extract base + version from armbian-*.deb
extract_base_ver() {
  local f="$1" bn base ver
  bn="$(basename -- "$f")"

  [[ "$bn" == armbian-*.deb ]] || return 1

  base="${bn%%_*}"                 # before first underscore
  ver="${bn#*_}"; ver="${ver%%_*}" # between first and second underscore

  [[ -n "$base" && -n "$ver" ]] || return 1
  printf '%s\t%s\n' "$base" "$ver"
}

# First pass: find newest version per base (across ALL subfolders)
while IFS= read -r -d '' f; do
  read -r base ver < <(extract_base_ver "$f") || continue

  if [[ -z "${best_ver[$base]:-}" ]]; then
    best_ver["$base"]="$ver"
    best_file["$base"]="$f"
  else
    if dpkg --compare-versions "$ver" gt "${best_ver[$base]}"; then
      best_ver["$base"]="$ver"
      best_file["$base"]="$f"
    fi
  fi
done < <(find "$ROOT" -type f -name 'armbian-*.deb' -print0)

echo "Keeping newest armbian-* package per base (recursive):"
for base in "${!best_file[@]}"; do
  echo "  $base -> ${best_ver[$base]} ($(basename -- "${best_file[$base]}"))"
done
echo

# Second pass: remove older versions
echo "Removing older armbian-* packages:"
while IFS= read -r -d '' f; do
  read -r base ver < <(extract_base_ver "$f") || continue
  if [[ "${best_file[$base]}" != "$f" ]]; then
    if [[ "$DRYRUN" == "1" ]]; then
      echo "  DRYRUN rm -f -- $f"
    else
      rm -f -- "$f"
      echo "  rm -f -- $f"
    fi
  fi
done < <(find "$ROOT" -type f -name 'armbian-*.deb' -print0)

if [[ "$DRYRUN" == "1" ]]; then
  echo
  echo "Dry-run mode. To actually delete:"
  echo "  DRYRUN=0 $0 \"$ROOT\""
fi
