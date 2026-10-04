#!/bin/bash
# WiFi watchdog - detects WiFi hang and restarts interface
# For VS6621S dual-band stability
#
# FIX (2026-09-24): first_wlan() must NOT use
#   ls /sys/class/net/wlan* | head -1 | xargs basename
# that lists directory contents (addr_assign_type...), not the iface name,
# so ping -I always failed and the watchdog force-restarted wlan0 every ~94s
# (3 * 30s), causing reason=3 / setup TXBA failed disconnects.

LOG="/tmp/kickpi-wifi-watchdog.log"
CHECK_INTERVAL=30
MAX_FAILED_PINGS=3

log_msg() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") $1" >> "$LOG"
}

first_wlan() {
    local d
    for d in /sys/class/net/wlan*; do
        [ -e "$d" ] || continue
        basename "$d"
        return 0
    done
    return 1
}

check_wifi_alive() {
    local d carrier
    for d in /sys/class/net/wlan*; do
        [ -e "$d" ] || continue
        carrier=$(cat "$d/carrier" 2>/dev/null || echo 0)
        [ "$carrier" = "1" ] && return 0
    done
    return 1
}

check_wifi_responding() {
    local gw iface
    gw=$(ip route show default 2>/dev/null | awk "/default/{print \$3; exit}")
    iface=$(first_wlan) || return 1
    if [ -z "$gw" ]; then
        local operstate
        operstate=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)
        [ "$operstate" = "up" ] && return 0
        return 1
    fi
    ping -c 1 -W 2 -I "$iface" "$gw" >/dev/null 2>&1
    return $?
}

restart_wifi() {
    local iface
    log_msg "WiFi hang detected, restarting all wlan interfaces..."
    for iface in /sys/class/net/wlan*; do
        [ -e "$iface" ] || continue
        iface=$(basename "$iface")
        log_msg "Restarting $iface"
        ip link set "$iface" down 2>>"$LOG"
        sleep 1
        ip link set "$iface" up 2>>"$LOG"
    done
    sleep 3
    log_msg "WiFi restart complete"
}

failed_count=0
log_msg "WiFi watchdog started (PID $$) fixed"

while true; do
    # No wlan interface at all (driver not present/not loaded): idle quietly
    # instead of counting failures and flooding the log every ~30s.
    if ! first_wlan >/dev/null; then
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if ! check_wifi_alive; then
        log_msg "No WiFi carrier detected"
        failed_count=$((failed_count + 1))
    elif ! check_wifi_responding; then
        log_msg "WiFi not responding to ping"
        failed_count=$((failed_count + 1))
    else
        if [ "$failed_count" -gt 0 ]; then
            log_msg "WiFi recovered (failed=$failed_count)"
        fi
        failed_count=0
    fi

    if [ "$failed_count" -ge "$MAX_FAILED_PINGS" ]; then
        restart_wifi
        failed_count=0
    fi

    sleep "$CHECK_INTERVAL"
done
