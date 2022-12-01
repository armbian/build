#!/usr/bin/env bash

SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-0.8.0} # https://github.com/koalaman/shellcheck/releases

SRC="$(
	cd "$(dirname "$0")/../.."
	pwd -P
)"
echo "SRC: ${SRC}"

DIR_SHELLCHECK="${SRC}/cache/tools/shellcheck"
mkdir -p "${DIR_SHELLCHECK}"

MACHINE="${BASH_VERSINFO[5]}"
case "$MACHINE" in
	*darwin*) SHELLCHECK_OS="darwin" ;;
	*linux*) SHELLCHECK_OS="linux" ;;
	*)
		echo "unknown os: $MACHINE"
		exit 3
		;;
esac

case "$MACHINE" in
	*aarch64*) SHELLCHECK_ARCH="aarch64" ;;
	*x86_64*) SHELLCHECK_ARCH="x86_64" ;;
	*)
		echo "unknown arch: $MACHINE"
		exit 2
		;;
esac

# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.darwin.x86_64.tar.xz
# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.linux.aarch64.tar.xz
# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.linux.x86_64.tar.xz

SHELLCHECK_FN="shellcheck-v${SHELLCHECK_VERSION}.${SHELLCHECK_OS}.${SHELLCHECK_ARCH}"
SHELLCHECK_FN_TARXZ="${SHELLCHECK_FN}.tar.xz"
DOWN_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${SHELLCHECK_FN_TARXZ}"
SHELLCHECK_BIN="${DIR_SHELLCHECK}/${SHELLCHECK_FN}"

echo "MACHINE: ${MACHINE}"
echo "Down URL: ${DOWN_URL}"
echo "SHELLCHECK_BIN: ${SHELLCHECK_BIN}"

if [[ ! -f "${SHELLCHECK_BIN}" ]]; then
	set -x
	echo "Cache miss, downloading..."
	wget -O "${SHELLCHECK_BIN}.tar.xz" "${DOWN_URL}"
	tar -xf "${SHELLCHECK_BIN}.tar.xz" -C "${DIR_SHELLCHECK}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
	mv -v "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${SHELLCHECK_BIN}"
	rm -rf "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}" "${SHELLCHECK_BIN}.tar.xz"
	chmod +x "${SHELLCHECK_BIN}"
fi


ACTUAL_VERSION="$("${SHELLCHECK_BIN}" --version | grep "^version")"
echo "Running shellcheck ${ACTUAL_VERSION}"

# formats:
# checkstyle -- some XML format
# gcc - one per line, compact references; does not show the source
# tty - default for checkstyle

cd "${SRC}" || exit 3
# "${SHELLCHECK_BIN}" --help
"${SHELLCHECK_BIN}" --check-sourced --color=always --external-sources --shell=bash --severity=warning --format=tty compile.sh

