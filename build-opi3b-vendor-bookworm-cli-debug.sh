#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

exec ./compile.sh opi3b-vendor-bookworm-cli-debug build PREFER_DOCKER=yes DOCKER_NICE=5
