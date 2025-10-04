#!/bin/bash

PREFIX="$(
        cd "$(dirname "$0")/.."
        pwd -P
)"

RELEASE=${RELEASE:-bookworm}

set -e # if this compile.sh fails, there's no point to continuing
$PREFIX/compile.sh inventory-boards PREFER_DOCKER=yes

[[ -e "$PREFIX/output/info/image-info.json" ]] || ( echo "output/info/image-info.json missing. Aborting."; exit 1 )
jq -r '.[].out | .LINUXFAMILY + " " + .HOST  ' \
	< "$PREFIX/output/info/image-info.json" \
	|sort -u |awk '!seen[$1]++' \
	> "$PREFIX/linux-families.lst"
[[ -s "$PREFIX/linux-families.lst" ]] || ( echo "List of linux families is empty. Aborting."; exit 1 )

# some boards or branches may fail, so we must continue going anyway.
set +e
while IFS=' ' read -r LINUXFAMILY BOARD; do
	[[ -z "$LINUXFAMILY" ]] && continue
	for branch in vendor legacy current edge; do
		[[ -e "${PREFIX}/config/kernel/linux-${LINUXFAMILY}-${branch}.config" ]] || continue
		$PREFIX/compile.sh rewrite-kernel-config PREFER_DOCKER=yes BOARD=$BOARD RELEASE=$RELEASE BRANCH=$branch
	done
	for t in $PREFIX/cache/sources/linux-kernel-worktree/*__${LINUXFAMILY}__*;
	do
		[[ -e "$t" ]] || continue # skip if glob failed to match anything.
		# reduce disc space used
		if ! sudo make -C $t clean 2>&1 >/dev/null; then
			# it failed, whether that was b/c we can't sudo or something in the Makefile couldn't be done.
			# so retry, and only give warning if that fails too.
			make -C $t clean 2>&1 >/dev/null || echo "Warning: cleanup of $t failed"
		fi
	done
done < $PREFIX/linux-families.lst
