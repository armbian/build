#!/bin/bash

################################################################################
# Simple Network Failover Script with DNS and Traffic/Downtime Reporting
#
# This script automatically switches outgoing internet traffic from a
# PRIMARY interface (e.g. wired LAN) to a BACKUP interface (e.g. WiFi)
# if connectivity via PRIMARY is lost (detected by failed ICMP ping
# AND DNS resolution). When PRIMARY recovers, it switches back.
#
# It also tracks:
#  - Total downtime spent on the backup interface
#  - Volume of traffic (TX+RX bytes) sent via the backup interface
#  - Logs statistics on each recovery event
#
# Requires: bash, iproute2, awk, ping, dig or nslookup
# Must be run as root (for 'ip route ...' and access to /proc/net/dev)
################################################################################

# === CONFIGURATION ===

# PRIMARY_IF:
#   Main preferred interface for internet access (e.g. "end0", "eth0")
PRIMARY_IF="end0"

# BACKUP_IF:
#   Backup/secondary interface (e.g. "wlan0")
BACKUP_IF="wlan0"

# PING_TARGETS:
#   List of external IPv4 addresses for connectivity check (public DNS recommended)
PING_TARGETS="1.1.1.1 8.8.8.8"

# PING_COUNT:
#   Number of ICMP echo requests per check, per target
PING_COUNT=2

# PING_TIMEOUT:
#   Timeout (in seconds) per ICMP echo request
PING_TIMEOUT=2

# FAIL_THRESH:
#   Minimum number of failed ping targets to trigger failover
FAIL_THRESH=5

# DNS_TEST_DOMAIN / DNS_RESOLVER:
#   DNS test: domain name to resolve and DNS server IP to query.
#   Failover occurs if DNS test fails as well.
DNS_TEST_DOMAIN="google.com"
DNS_RESOLVER="8.8.8.8"

# CHECK_INTERVAL:
#   How frequently (seconds) to check and possibly switch interfaces
CHECK_INTERVAL=10

################################################################################
# ---- NO USER SETTINGS BELOW THIS POINT ----

# Returns 0 (success) if interface $1 is up, 1 otherwise
if_is_up() {
    [[ "$(cat /sys/class/net/$1/operstate 2>/dev/null)" == "up" ]]
}

# Returns current default gateway IP for interface $1 (empty if down/not set)
get_gw_by_if() {
    IFACE="$1"
    ip route | awk -v dev="$IFACE" '$1=="default" && $5==dev {print $3; exit}'
}

# Returns interface which owns current default route
get_current_default_gwdev() {
    ip route | awk '$1 == "default" {print $5; exit}'
}

# Returns number of PING_TARGETS for which ping fails
check_ping() {
    failcount=0
    for IP in $PING_TARGETS; do
        if ! ping -I "$PRIMARY_IF" -c "$PING_COUNT" -W "$PING_TIMEOUT" "$IP" > /dev/null; then
            ((failcount++))
        fi
    done
    echo "$failcount"
}

# Returns 0 if DNS is working (domain resolves to an IP), 1 if not
check_dns() {
    if command -v dig >/dev/null 2>&1; then
        dig @"$DNS_RESOLVER" "$DNS_TEST_DOMAIN" +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'
        return $?
    else
        nslookup "$DNS_TEST_DOMAIN" "$DNS_RESOLVER" 2>/dev/null | grep -q "Address: "
        return $?
    fi
}

# Returns total bytes (RX + TX) transferred on interface $1
iface_bytes() {
    IF="$1"
    awk -v ifname="$IF" '$1 == ifname":" {print $2 + $10}' /proc/net/dev
}

################################################################################
# ---- MAIN LOGIC ----

# CURRENT_MODE:
#   "primary" if PRIMARY_IF is active, "backup" if BACKUP_IF is used for default route.
CURRENT_MODE="primary"

# DOWNTIME_START:
#   Holds Unix timestamp when failover starts (i.e., backup interface takes over)
DOWNTIME_START=0

# TOTAL_DOWNTIME:
#   Accumulated failover duration (seconds) over one script run
TOTAL_DOWNTIME=0

# BACKUP_BYTES_START:
#   Value of RX+TX bytes for BACKUP_IF when failover begins
BACKUP_BYTES_START=0

# BACKUP_BYTES_TOTAL:
#   Accumulated number of bytes sent via BACKUP_IF over all failover intervals
BACKUP_BYTES_TOTAL=0

while true; do
    # 1. Check if both interfaces are physically up
    if if_is_up "$PRIMARY_IF"; then
        PRIMARY_OK=1
    else
        PRIMARY_OK=0
    fi
    if if_is_up "$BACKUP_IF"; then
        BACKUP_OK=1
    else
        BACKUP_OK=0
    fi

    # 2. Connectivity tests:
    FAILS=$(check_ping)
    check_dns
    DNS_OK=$?

    # 3. Get dynamic current DHCP gateways
    PRIMARY_GW=$(get_gw_by_if "$PRIMARY_IF")
    BACKUP_GW=$(get_gw_by_if "$BACKUP_IF")
    CUR_GWDEV=$(get_current_default_gwdev)

    # Log status for debugging / observation
    echo "PINGfails:$FAILS DNS:$DNS_OK PRIMARY_GW:$PRIMARY_GW BACKUP_GW:$BACKUP_GW DEF_IF:$CUR_GWDEV"

    #####################
    # Main switching logic
    #
    # If using primary, check for failover conditions (ICMP/DNS/iface fail)
    if [[ "$CURRENT_MODE" == "primary" ]]; then
        if (( FAILS >= FAIL_THRESH )) || [[ $PRIMARY_OK -eq 0 ]] || [[ $DNS_OK -ne 0 ]]; then
            if [[ -n "$BACKUP_GW" ]] && [[ $BACKUP_OK -eq 1 ]]; then
                echo "FAILOVER: Switching to backup: $BACKUP_IF gw $BACKUP_GW (Ping/DNS failed or IF down)"
                ip route replace default via "$BACKUP_GW" dev "$BACKUP_IF"
                CURRENT_MODE="backup"
                DOWNTIME_START=$(date +%s)
                BACKUP_BYTES_START=$(iface_bytes "$BACKUP_IF")
            else
                echo "Failover blocked: Backup $BACKUP_IF unavailable (not up or no gateway)"
            fi
        fi
    #
    # If using backup, check for recovery (primary restored: ICMP+DNS+gateway+UP)
    else
        if (( FAILS < FAIL_THRESH )) && [[ $PRIMARY_OK -eq 1 ]] && [[ $DNS_OK -eq 0 ]] && [[ -n "$PRIMARY_GW" ]]; then
            echo "RECOVERY: Switching back to primary: $PRIMARY_IF gw $PRIMARY_GW"
            ip route replace default via "$PRIMARY_GW" dev "$PRIMARY_IF"
            # Calculate and display failover stats:
            NOW=$(date +%s)
            DURATION=$(( NOW - DOWNTIME_START ))
            TOTAL_DOWNTIME=$(( TOTAL_DOWNTIME + DURATION ))
            CUR_BACKUP_BYTES=$(iface_bytes "$BACKUP_IF")
            USAGE=$(( CUR_BACKUP_BYTES - BACKUP_BYTES_START ))
            BACKUP_BYTES_TOTAL=$(( BACKUP_BYTES_TOTAL + USAGE ))

            echo "---- FAILOVER STATS ----"
            echo "Downtime (latest event): $DURATION sec"
            echo "Traffic sent on backup:  $USAGE bytes"
            echo "Total downtime:          $TOTAL_DOWNTIME sec"
            echo "Total traffic on backup: $BACKUP_BYTES_TOTAL bytes"
            echo "------------------------"

            # Reset per-event counters
            DOWNTIME_START=0
            BACKUP_BYTES_START=0
            CURRENT_MODE="primary"
        #
        # Backup interface has disappeared altogether (WiFi disconnected?)
        elif ! if_is_up "$BACKUP_IF"; then
            echo "WARNING: Backup IF $BACKUP_IF has gone! Default route deleted."
            ip route del default
            CURRENT_MODE="unknown"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done