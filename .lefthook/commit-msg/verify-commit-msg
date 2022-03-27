#!/bin/bash
# Author: CXM

# input
INPUT_FILE=$1
START_LINE=$(head -n1 $INPUT_FILE)
# color scheme
RED='\033[0;31m'
GREEN='\033[0;32m'
# pattern
PATTERN="^^(revert: )?(feat|fix|polish|docs|style|refactor|perf|test|workflow|ci|chore|types|build)(\(.+\))?: .{1,50}"

if ! [[ "$START_LINE" =~ $PATTERN ]]; then
	printf "${RED}Proper commit message format is required for automated changelog generation. Examples:\n"
	printf "${GREEN}feat(compiler): add 'comments' option\n"
	exit 1
fi
