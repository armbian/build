cat <<'EOF'
# Patch fancontrol
patch --silent --forward --no-backup-if-mismatch -r - /usr/sbin/fancontrol /usr/share/${DPKG_MAINTSCRIPT_PACKAGE}/fancontrol.patch >/dev/null 2>&1

EOF
