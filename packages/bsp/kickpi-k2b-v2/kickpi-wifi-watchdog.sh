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
# Carrier-absence guard (review 2026-10-04): do not count an absent
# carrier during initial setup or while NetworkManager retries the link.
STARTUP_GRACE=180     # seconds after service start
RECONNECT_GRACE=120   # seconds after carrier was last seen

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

# Should an absent carrier be counted as a failure right now?
wifi_carrier_expected() {
    local now
    # Radio switched off in NetworkManager: WiFi is not meant to be connected
    if command -v nmcli >/dev/null 2>&1; then
        [ "$(nmcli radio wifi 2>/dev/null)" = "disabled" ] && return 1
    fi
    now=$(date +%s)
    # Initial setup: the driver creates wlan0 long before association completes
    [ $((now - start_ts)) -lt "$STARTUP_GRACE" ] && return 1
    # Reconnection: carrier just dropped, give NetworkManager time to retry
    if [ -n "$last_alive_ts" ]; then
        [ $((now - last_alive_ts)) -lt "$RECONNECT_GRACE" ] && return 1
    fi
    return 0
}

check_wifi_responding() {
    local gw iface neigh
    iface=$(first_wlan) || return 1
    # The gateway must be reachable *through this interface*: the system-wide
    # default route may belong to Ethernet and sit on an unrelated subnet.
    gw=$(ip -4 route show default dev "$iface" 2>/dev/null |
        awk '/default/ && $2 == "via" {print $3; exit}')
    if [ -z "$gw" ] && command -v nmcli >/dev/null 2>&1; then
        gw=$(nmcli -g IP4.GATEWAY device show "$iface" 2>/dev/null | head -n1)
        [ "$gw" = "--" ] && gw=""
    fi
    if [ -z "$gw" ]; then
        # No L3 route over WiFi (Ethernet carries connectivity): link state only
        local operstate
        operstate=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)
        [ "$operstate" = "up" ] && return 0
        return 1
    fi
    ping -c 1 -W 2 -I "$iface" "$gw" >/dev/null 2>&1 && return 0
    # Some routers drop ICMP echo: a probe that traverses the router proves the
    # WiFi path still forwards traffic, so echo-blocked gateway != WiFi hang.
    if ip -4 route show default dev "$iface" >/dev/null 2>&1 &&
        ping -c 1 -W 2 -I "$iface" 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    # Last resort: the gateway ARP entry still resolves over this interface
    # (layer 2 works, only ICMP is being ignored). Never fail on ping alone.
    neigh=$(ip neigh show "$gw" dev "$iface" 2>/dev/null)
    if echo "$neigh" | grep -qE "REACHABLE|STALE|DELAY|PROBE"; then
        return 0
    fi
    return 1
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
start_ts=$(date +%s)
last_alive_ts="" # last timestamp carrier was seen; anchors reconnect grace
log_msg "WiFi watchdog started (PID $$) fixed"

while true; do
    # No wlan interface at all (driver not present/not loaded): idle quietly
    # instead of counting failures and flooding the log every ~30s.
    if ! first_wlan >/dev/null; then
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if check_wifi_alive; then
        last_alive_ts=$(date +%s)
        if ! check_wifi_responding; then
            log_msg "WiFi carrier up but not responding to probe"
            failed_count=$((failed_count + 1))
        else
            if [ "$failed_count" -gt 0 ]; then
                log_msg "WiFi recovered (failed=$failed_count)"
            fi
            failed_count=0
        fi
    else
        if wifi_carrier_expected; then
            log_msg "No WiFi carrier detected"
            failed_count=$((failed_count + 1))
        else
            if [ "$failed_count" -gt 0 ]; then
                log_msg "carrier absent inside grace/intent window, clearing failed=$failed_count"
            fi
            failed_count=0
        fi
    fi

    if [ "$failed_count" -ge "$MAX_FAILED_PINGS" ]; then
        restart_wifi
        failed_count=0
    fi

    sleep "$CHECK_INTERVAL"
done
