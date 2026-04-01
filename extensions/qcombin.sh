#!/usr/bin/env bash
function fetch_sources_tools__qcombin() {
	fetch_from_repo "${QCOMBIN_GIT_URL:-"https://github.com/armbian/qcombin"}" "qcombin" "branch:${QCOMBIN_GIT_BRANCH:-"main"}"
}
