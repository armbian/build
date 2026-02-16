#!/usr/bin/env bash
#
# Customize an Armbian ABL rootfs image (Oneplus 8t) from a YAML config.
# Run on Linux (native or inside Docker on Mac). Requires root.
#
# Usage: customize-image.sh <rootfs.img> <config.yaml>
# Output: <rootfs>-customized.rootfs.img (input is not modified; we copy then modify the copy).

set -e

usage() {
	echo "Usage: $0 <rootfs.img> <config.yaml>" >&2
	echo "  Customizes the rootfs image using the YAML config; writes *-customized.rootfs.img" >&2
	exit 1
}

cleanup() {
	local rc=$?
	if [[ -n "$ROOT_MNT" && -d "$ROOT_MNT" ]]; then
		if mountpoint -q "$ROOT_MNT"; then
			umount -l "$ROOT_MNT"/dev/pts 2>/dev/null || true
			umount -l "$ROOT_MNT"/dev 2>/dev/null || true
			umount -l "$ROOT_MNT"/proc 2>/dev/null || true
			umount -l "$ROOT_MNT"/sys 2>/dev/null || true
			if [[ -n "$APT_CACHE_HOST" ]] && mountpoint -q "$ROOT_MNT/var/cache/apt/archives" 2>/dev/null; then
				umount -l "$ROOT_MNT/var/cache/apt/archives" 2>/dev/null || true
			fi
			umount -l "$ROOT_MNT" 2>/dev/null || true
		fi
		rmdir "$ROOT_MNT" 2>/dev/null || true
	fi
	[[ -n "$APT_CACHE_HOST" && -d "$APT_CACHE_HOST" ]] && rm -rf "$APT_CACHE_HOST"
	if [[ -n "$LOOP_DEV" && -b "$LOOP_DEV" ]]; then
		losetup -d "$LOOP_DEV" 2>/dev/null || true
	fi
	if [[ $rc -ne 0 ]]; then
		echo "Customizer failed (exit $rc). Cleanup done." >&2
	fi
	exit $rc
}

# Parse YAML and emit shell variables (sourced by caller).
# Requires python3 and PyYAML (python3-yaml). Keys: root_password, user_name, user_password,
# user_shell, user_sudo, locale, timezone, wifi_ssid, wifi_password, ssh_keys_root, ssh_keys_user, extra_packages, run_commands.
yaml_to_shell() {
	local yaml_file="$1"
	if [[ ! -f "$yaml_file" ]]; then
		echo "Error: Config file not found: $yaml_file" >&2
		return 1
	fi
	python3 - "$yaml_file" <<'PY'
import sys, yaml

try:
    with open(sys.argv[1]) as f:
        d = yaml.safe_load(f) or {}
except Exception as e:
    sys.stderr.write("YAML parse error: %s\n" % e)
    sys.exit(1)

def esc(s):
    if s is None: return ""
    s = str(s).replace("\\", "\\\\").replace("'", "'\\''")
    return s

for k in ("root_password", "user_name", "user_password", "user_shell", "user_sudo", "locale", "timezone", "wifi_ssid", "wifi_password"):
    v = d.get(k)
    print("%s='%s'" % (k, esc(v) if v is not None else ""))

for k in ("ssh_keys_root", "ssh_keys_user", "extra_packages", "run_commands"):
    v = d.get(k)
    if not isinstance(v, list): v = [v] if v is not None else []
    parts = " ".join("'%s'" % esc(x) for x in v if x is not None)
    print("%s=(%s)" % (k, parts))
PY
}

# Resolve ssh_keys entries: paths to files (read content) or inline strings (use as-is).
resolve_ssh_keys() {
	local key="$1"
	local -n arr=$key
	local -a out=()
	local f
	for f in "${arr[@]}"; do
		[[ -z "$f" ]] && continue
		f="${f/#\~/$HOME}"
		if [[ -f "$f" ]]; then
			out+=( "$(cat "$f")" )
		else
			out+=( "$f" )
		fi
	done
	arr=( "${out[@]}" )
}

[[ $# -ge 2 ]] || usage
ROOTFS_IMAGE="$(realpath "$1")"
CONFIG_YAML="$(realpath "$2")"
[[ -f "$ROOTFS_IMAGE" ]] || { echo "Error: Rootfs image not found: $ROOTFS_IMAGE" >&2; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Error: This script must be run as root (or with sudo)." >&2; exit 1; }

# Output path: add -customized before .rootfs.img (strip any existing -customized to avoid double suffix).
OUTPUT_BASE="${ROOTFS_IMAGE%.rootfs.img}"
OUTPUT_BASE="${OUTPUT_BASE%-customized}"
OUTPUT_IMAGE="${OUTPUT_BASE}-customized.rootfs.img"
if [[ "$OUTPUT_IMAGE" == "$ROOTFS_IMAGE" ]]; then
	OUTPUT_IMAGE="${ROOTFS_IMAGE%.img}-customized.img"
fi
echo "Output image: $OUTPUT_IMAGE"

# Copy so we don't modify the original (skip if overwriting same path).
if [[ "$OUTPUT_IMAGE" != "$ROOTFS_IMAGE" ]]; then
	echo "Copying rootfs image to $OUTPUT_IMAGE ..."
	cp -f "$ROOTFS_IMAGE" "$OUTPUT_IMAGE"
fi

ROOT_MNT=""
LOOP_DEV=""
trap cleanup EXIT INT TERM

LOOP_DEV=$(losetup --find --show "$OUTPUT_IMAGE")
ROOT_MNT=$(mktemp -d /tmp/armbian-customize.XXXXXX)
mount "$LOOP_DEV" "$ROOT_MNT"

# Bind-mount for chroot and network
mount --bind /dev "$ROOT_MNT/dev"
mount -t proc none "$ROOT_MNT/proc"
mount -t sysfs none "$ROOT_MNT/sys"
mount -t devpts none "$ROOT_MNT/dev/pts" 2>/dev/null || mount --bind /dev/pts "$ROOT_MNT/dev/pts"
# Replace resolv.conf in image so chroot has DNS (image may have a dangling symlink)
if [[ -f /etc/resolv.conf ]]; then
	rm -f "$ROOT_MNT/etc/resolv.conf"
	cp -f /etc/resolv.conf "$ROOT_MNT/etc/resolv.conf"
fi

# Parse config
CONFIG_DIR="$(dirname "$CONFIG_YAML")"
eval "$(yaml_to_shell "$CONFIG_YAML")"

# Resolve SSH key paths (relative to config dir)
cd "$CONFIG_DIR"
resolve_ssh_keys ssh_keys_root
resolve_ssh_keys ssh_keys_user
cd - >/dev/null

# Disable firstboot
rm -f "$ROOT_MNT/root/.not_logged_in_yet"
chroot "$ROOT_MNT" systemctl disable armbian-firstrun.service 2>/dev/null || true

# Timezone (e.g. America/Chicago for US Central)
if [[ -n "$timezone" ]]; then
	if [[ -f "$ROOT_MNT/usr/share/zoneinfo/$timezone" ]]; then
		echo "$timezone" > "$ROOT_MNT/etc/timezone"
		ln -sf "/usr/share/zoneinfo/$timezone" "$ROOT_MNT/etc/localtime"
		echo "Set timezone: $timezone"
	else
		echo "Warning: timezone file not found: /usr/share/zoneinfo/$timezone" >&2
	fi
fi

# Locale (e.g. en_US.UTF-8): enable in locale.gen, run locale-gen, set LANG
if [[ -n "$locale" ]]; then
	locale_escaped="${locale//./\\.}"  # escape dots for sed
	if grep -qF "^# *${locale} " "$ROOT_MNT/etc/locale.gen" 2>/dev/null; then
		sed -i "s/^# *${locale_escaped} /${locale_escaped} /" "$ROOT_MNT/etc/locale.gen"
	fi
	if ! grep -qF "^${locale} " "$ROOT_MNT/etc/locale.gen" 2>/dev/null; then
		echo "${locale} UTF-8" >> "$ROOT_MNT/etc/locale.gen"
	fi
	chroot "$ROOT_MNT" locale-gen 2>/dev/null || true
	chroot "$ROOT_MNT" update-locale LANG="$locale" 2>/dev/null || true
	echo "Set locale: $locale"
fi

# WiFi: create NetworkManager connection so the system connects on first boot (requires NetworkManager in image)
if [[ -n "$wifi_ssid" ]]; then
	NM_CONN_DIR="$ROOT_MNT/etc/NetworkManager/system-connections"
	mkdir -p "$NM_CONN_DIR"
	# Pass password via env so shell does not expand ! (history) or other chars in the password
	WIFI_SSID="$wifi_ssid" WIFI_PASSWORD="$wifi_password" python3 - "$NM_CONN_DIR" <<'PYWIFI'
import sys, os
conn_dir = sys.argv[1]
ssid = (os.environ.get("WIFI_SSID") or "").strip()
pwd = (os.environ.get("WIFI_PASSWORD") or "").strip()
# SSID: write unquoted when possible so NM passes it to wpa_supplicant correctly (quoted SSID was seen as literal "Name")
def ssid_line(s):
    if not s: return "ssid="
    s = str(s)
    if not any(c in s for c in " \t=#;\n\\\""):
        return "ssid=" + s
    esc = s.replace("\\", "\\\\").replace('"', '\\"')
    return 'ssid="' + esc + '"'
# Password: always write unquoted (quoted psk is treated as literal and breaks connection on boot)
def psk_line(s):
    if s is None: s = ""
    s = str(s)
    # Keyfile unquoted value = rest of line; only newline would break the format
    return "psk=" + s.replace("\n", " ").replace("\r", " ")
content = """[connection]
id=armbian-wifi
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
""" + ssid_line(ssid) + """

[wifi-security]
key-mgmt=wpa-psk
""" + psk_line(pwd) + """

[ipv4]
method=auto

[ipv6]
method=auto
"""
path = os.path.join(conn_dir, "armbian-wifi.nmconnection")
with open(path, "w") as f:
    f.write(content)
PYWIFI
	chmod 600 "$NM_CONN_DIR/armbian-wifi.nmconnection"
	chroot "$ROOT_MNT" systemctl enable NetworkManager.service 2>/dev/null || true
	echo "Set WiFi: SSID $wifi_ssid (connects on first boot if NetworkManager is present)"
fi

# Root password
if [[ -n "$root_password" ]]; then
	echo "root:$root_password" | chroot "$ROOT_MNT" chpasswd
fi

# New user
if [[ -n "$user_name" ]]; then
	chroot "$ROOT_MNT" useradd -m -s "${user_shell:-/bin/bash}" "$user_name" 2>/dev/null || true
	if [[ -n "$user_password" ]]; then
		echo "$user_name:$user_password" | chroot "$ROOT_MNT" chpasswd
	fi
	if [[ -n "$user_sudo" ]]; then
		# user_sudo is the sudoers spec (e.g. ALL=(ALL) NOPASSWD:ALL)
	chroot "$ROOT_MNT" bash -c "echo '$user_name $user_sudo' > /etc/sudoers.d/99-custom-user && chmod 440 /etc/sudoers.d/99-custom-user"
	fi
	mkdir -p "$ROOT_MNT/home/$user_name/.ssh"
	for line in "${ssh_keys_user[@]}"; do
		[[ -z "$line" ]] && continue
		echo "$line" >> "$ROOT_MNT/home/$user_name/.ssh/authorized_keys"
	done
	chroot "$ROOT_MNT" chown -R "$user_name:$user_name" "/home/$user_name/.ssh"
	chmod 700 "$ROOT_MNT/home/$user_name/.ssh"
	chmod 600 "$ROOT_MNT/home/$user_name/.ssh/authorized_keys" 2>/dev/null || true
fi

# Root SSH keys
mkdir -p "$ROOT_MNT/root/.ssh"
for line in "${ssh_keys_root[@]}"; do
	[[ -z "$line" ]] && continue
	echo "$line" >> "$ROOT_MNT/root/.ssh/authorized_keys"
done
chmod 700 "$ROOT_MNT/root/.ssh"
chmod 600 "$ROOT_MNT/root/.ssh/authorized_keys" 2>/dev/null || true

# Extra packages (run apt-get update so package lists are current; no -qq so update errors are visible)
if [[ ${#extra_packages[@]} -gt 0 ]]; then
	chroot "$ROOT_MNT" env DEBIAN_FRONTEND=noninteractive apt-get update
	chroot "$ROOT_MNT" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${extra_packages[@]}"
	# Free space in the image for run_commands (e.g. apt-get upgrade) by clearing apt cache
	chroot "$ROOT_MNT" apt-get clean
fi

# Run commands: use a bind-mounted temp dir for apt cache so apt-get upgrade (etc.) don't
# require hundreds of MB free inside the fixed-size image
APT_CACHE_HOST=""
if [[ ${#run_commands[@]} -gt 0 ]]; then
	APT_CACHE_HOST="$(mktemp -d)"
	mount --bind "$APT_CACHE_HOST" "$ROOT_MNT/var/cache/apt/archives"
	# Let _apt access the cache so apt can run sandboxed (avoids "Download is performed unsandboxed" warning)
	chroot "$ROOT_MNT" chown _apt:root /var/cache/apt/archives 2>/dev/null || true
	chroot "$ROOT_MNT" chmod 775 /var/cache/apt/archives 2>/dev/null || true
fi
for cmd in "${run_commands[@]}"; do
	[[ -z "$cmd" ]] && continue
	echo "Running: $cmd"
	chroot "$ROOT_MNT" bash -c "$cmd"
done
if [[ -n "$APT_CACHE_HOST" ]]; then
	chroot "$ROOT_MNT" apt-get clean 2>/dev/null || true
	umount "$ROOT_MNT/var/cache/apt/archives"
	rm -rf "$APT_CACHE_HOST"
	APT_CACHE_HOST=""
fi

# Unmount (trap will also run; do it explicitly for clarity)
umount "$ROOT_MNT/dev/pts" 2>/dev/null || true
umount "$ROOT_MNT/dev" 2>/dev/null || true
umount "$ROOT_MNT/proc" 2>/dev/null || true
umount "$ROOT_MNT/sys" 2>/dev/null || true
umount "$ROOT_MNT"
losetup -d "$LOOP_DEV"
LOOP_DEV=""
rmdir "$ROOT_MNT"
ROOT_MNT=""
trap - EXIT INT TERM

echo "Done. Customized image: $OUTPUT_IMAGE"
