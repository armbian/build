#!/bin/bash
echo "✅ custom_partition_hook.sh loaded (inside build env)"

declare -g USE_HOOK_FOR_PARTITION=yes

# --------------------------------------------------
# Custom partition creation
# --------------------------------------------------
function create_partition_table() {
    local PARTITION_CONF="${USERPATCHES_PATH}/partition.conf"
    display_alert "[🌱] Using custom partition.conf" "${PARTITION_CONF}" "info"

    [[ ! -f "$PARTITION_CONF" ]] && exit_with_error "partition.conf not found at $PARTITION_CONF"

    run_host_command_logged sfdisk "${SDCARD}.raw" < "$PARTITION_CONF" \
        || exit_with_error "Custom partition creation failed"

    sync
}

