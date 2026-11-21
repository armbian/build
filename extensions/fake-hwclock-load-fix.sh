#!/usr/bin/env bash
# @description Installs fake-hwclock 0.14 with the upstream fix for its inverted `load` test (Debian #1093227, upstream commit 875c169). In 0.14, `load` without `force` sets the clock to the saved time even when the saved time is older. Acts only on 0.14 (Debian trixie) and 0.14buildN (Ubuntu 26.04).

#
# SPDX-License-Identifier: GPL-2.0-only
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Generalised from the mangopi-rtc extension (#10908). Can be removed when every
# supported release ships a fixed fake-hwclock (a stable update, or 0.15).

function post_family_tweaks__fake_hwclock_load_fix() {
	local query version
	# Only an installed package ("ii"): one removed with its config kept still reports a version
	query=$(dpkg-query --admindir="${SDCARD}/var/lib/dpkg" -W -f '${db:Status-Abbrev}|${Version}' fake-hwclock 2>/dev/null) || return 0
	# Debian trixie ships 0.14; Ubuntu 26.04 ships the same script as 0.14build1
	[[ "$query" =~ ^ii\ \|0\.14(build[0-9]+)?$ ]] || return 0
	version="${query#*|}"
	display_alert "fake-hwclock ${version}" "installing ${version}+armbian1 (inverted load test, Debian #1093227)" "info"

	local stage
	stage=$(mktemp -d "${SDCARD}/tmp/fake-hwclock-fix.XXXXXX")
	if ! fake_hwclock_load_fix_build "$stage" "$version"; then
		display_alert "fake-hwclock" "could not build the fixed package; leaving ${version} installed" "wrn"
		rm -rf -- "$stage"
		return 0
	fi
	chroot_sdcard dpkg -i "/tmp/${stage##*/}/backport.deb"
	rm -rf -- "$stage"
}

# Download Debian's 0.14 package, apply the fix and version it "<installed version>+armbian1".
# That sorts above the broken package and below the distribution fixes, so apt replaces it.
function fake_hwclock_load_fix_build() {
	local stage="$1" version="$2" url checksum verified="no"
	local sha256="cefc64ceb7d4477cd3c938bef852a35b4ae4ca73174a41c69ade380cba7af7a7"
	# The pinned checksum makes plain http from the configured mirror safe; snapshot keeps 0.14 after the pool drops it
	for url in \
		"http://${DEBIAN_MIRROR:-deb.debian.org/debian}/pool/main/f/fake-hwclock/fake-hwclock_0.14_all.deb" \
		"https://snapshot.debian.org/file/ecdfc1315d2d1fb4ecb9a80c80e925f046d448e2"; do
		if curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 \
			-o "$stage/original.deb" "$url" &&
			printf '%s  %s\n' "$sha256" "$stage/original.deb" | sha256sum --check --quiet -; then
			verified="yes"
			break
		fi
		rm -f -- "$stage/original.deb"
	done
	[[ "$verified" == "yes" ]] || return 1
	dpkg-deb -R "$stage/original.deb" "$stage/package" || return 1
	patch --batch -d "$stage/package/usr/sbin" -p1 < "${SRC}/packages/blobs/rtc/fake-hwclock-force-fix.patch" || return 1
	sed -i "s/^Version: 0\.14\$/Version: ${version}+armbian1/" "$stage/package/DEBIAN/control" || return 1
	grep -qx "Version: ${version}+armbian1" "$stage/package/DEBIAN/control" || return 1
	checksum=$(md5sum "$stage/package/usr/sbin/fake-hwclock" | cut -d' ' -f1)
	[[ "$checksum" =~ ^[0-9a-f]{32}$ ]] || return 1
	awk -v checksum="$checksum" '$2 == "usr/sbin/fake-hwclock" { $1 = checksum } { printf "%s  %s\n", $1, $2 }' \
		"$stage/package/DEBIAN/md5sums" > "$stage/md5sums" || return 1
	mv "$stage/md5sums" "$stage/package/DEBIAN/md5sums" || return 1
	dpkg-deb --root-owner-group --build "$stage/package" "$stage/backport.deb" || return 1
}
