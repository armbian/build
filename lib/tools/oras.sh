#!/usr/bin/env bash

set -e

SRC="$(
	cd "$(dirname "$0")/../.."
	pwd -P
)"

# shellcheck source=lib/single.sh
source "${SRC}"/lib/single.sh

# initialize logging variables.
logging_init

run_tool_oras "$@"
