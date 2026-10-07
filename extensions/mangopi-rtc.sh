# SPDX-License-Identifier: GPL-2.0-only
# Backport the upstream boot clock fix for fake-hwclock 0.14.
function post_family_tweaks__mangopi_rtc_fake_hwclock() {
	local version
	version=$(dpkg-query --admindir="${SDCARD}/var/lib/dpkg" -W -f '${Version}' fake-hwclock 2>/dev/null) || return 0
	[[ "$version" == "0.14" ]] || return 0

	local stage checksum
	stage=$(mktemp -d "${SDCARD}/tmp/mangopi-rtc.XXXXXX")
	curl --fail --silent --show-error --location --retry 3 \
		-o "$stage/original.deb" "https://deb.debian.org/debian/pool/main/f/fake-hwclock/fake-hwclock_0.14_all.deb"
	printf '%s  %s\n' 'cefc64ceb7d4477cd3c938bef852a35b4ae4ca73174a41c69ade380cba7af7a7' "$stage/original.deb" | sha256sum -c -
	dpkg-deb -R "$stage/original.deb" "$stage/package"
	patch -d "$stage/package/usr/sbin" -p1 < "${SRC}/packages/blobs/rtc/fake-hwclock-force-fix.patch"
	sed -i 's/^Version: 0.14$/Version: 0.14+armbian1/' "$stage/package/DEBIAN/control"
	checksum=$(md5sum "$stage/package/usr/sbin/fake-hwclock" | cut -d' ' -f1)
	awk -v checksum="$checksum" '$2 == "usr/sbin/fake-hwclock" { $1 = checksum } { printf "%s  %s\n", $1, $2 }' \
		"$stage/package/DEBIAN/md5sums" > "$stage/md5sums"
	mv "$stage/md5sums" "$stage/package/DEBIAN/md5sums"
	dpkg-deb --root-owner-group --build "$stage/package" "$stage/backport.deb"
	chroot_sdcard dpkg -i "/tmp/${stage##*/}/backport.deb"
	rm -rf -- "$stage"
}
