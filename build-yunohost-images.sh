#!/bin/bash

readonly SUPPORTED_BOARDS="orangepipcplus lime lime2"
readonly normal=$(printf '\033[0m')
readonly bold=$(printf '\033[1m')
readonly red=$(printf '\033[31m')

function die()
{
  local msg=${1}
  echo "[${bold}${red}FAIL${normal}] ${msg}" >&2
  exit 1
}

function validate_boards()
{
    [[ -n "$1" ]] || die "You need to provide at least one board among : $SUPPORTED_BOARDS"
    for BOARD in "$@"
    do
       [[ "$SUPPORTED_BOARDS" =~ (^|[[:space:]])"$BOARD"($|[[:space:]]) ]] \
          || die "'$BOARD' is not supported so far. Accepted boards are : $SUPPORTED_BOARDS"
    done
}

function main()
{
    validate_boards $@

    for BOARD in "$@"
    do
        ./compile.sh CLEAN_LEVEL="make,debs,alldebs,cache,sources,extras" KERNEL_ONLY="no" KERNEL_CONFIGURE="no" BUILD_DESKTOP="no" BUILD_ALL="no" BOARD="$BOARD" BRANCH="next" RELEASE="stretch"
    done
}

main $@
