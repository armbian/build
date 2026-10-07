# SPDX-License-Identifier: GPL-2.0-only
# Build source firmware with Armbian's compiler and package functions.
function mangopi_build_boot0() {
    local source="${SRC}/cache/sources/mangopi-boot0/882671f"
    local build="${WORKDIR}/mangopi-boot0"
    (
        local GIT_FIXED_WORKDIR="" GIT_BARE_REPO_FOR_WORKTREE=""
        fetch_from_repo https://github.com/smaeul/sun20i_d1_spl.git \
            mangopi-boot0/882671f commit:882671fcf53137aaafc3a94fa32e682cb7b921f1 no
    )
    run_host_command_logged git clone --no-hardlinks --local "$source" "$build"
    # Disk layout: move both TOC1 slots below the ext4 partition at 4 MiB.
    run_host_command_logged git -C "$build" apply \
        "${SRC}/patch/boot0/boot0-sun20i-d1/0001-adjust-toc1-sd-locations.patch"
    # Build Boot0 with its existing DRAM and SD initialization.
    run_host_command_logged env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory \
        "GIT_CONFIG_VALUE_0=$build" make -C "$build" \
        -j4 CROSS_COMPILE=riscv64-linux-gnu- p=sun20iw1p1 mmc
    run_host_command_logged cp "$build/nboot/boot0_sdcard_sun20iw1p1.bin" ./
}

function mangopi_build_firmware_dtb() {
    local source="${SRC}/cache/sources/mangopi-firmware-dtb/afc07cec42"
    local build="${WORKDIR}/mangopi-firmware-dtb"
    # Build the firmware DTB consumed by Boot0 and OpenSBI. Keep the kernel's MQ Pro DTB separate.
    (
        local GIT_FIXED_WORKDIR="" GIT_BARE_REPO_FOR_WORKTREE=""
        fetch_from_repo https://github.com/smaeul/u-boot.git \
            mangopi-firmware-dtb/afc07cec42 commit:afc07cec423f17ebb4448a19435292ddacf19c9b no
    )
    run_host_command_logged make -C "$source" "O=$build" CROSS_COMPILE=riscv64-linux-gnu- nezha_defconfig
    run_host_command_logged make -C "$source" "O=$build" CROSS_COMPILE=riscv64-linux-gnu- \
        CONFIG_PYLIBFDT= KCFLAGS=-Wno-error=implicit-function-declaration \
        "ARCH_FLAGS='-march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany'" u-boot.dtb
    run_host_command_logged cp "$build/u-boot.dtb" ./firmware.dtb
}

function post_family_config__mangopi_source_boot() {
    declare -g ATFBRANCH="tag:v1.9" ATFPATCHDIR="atf-opensbi-v1.9"
    declare -g BOOTBRANCH="commit:2e89b706f5c956a70c989cd31665f1429e9a0b48"
    declare -g UBOOT_TARGET_MAP="u-boot.bin u-boot.dtb u-boot.img;;u-boot.img u-boot.toc1 boot0_sdcard_sun20iw1p1.bin"
    # Disk layout: one ext4 partition starts at 4 MiB. Reserve space for GPT and firmware.
    declare -g IMAGE_PARTITION_TABLE="gpt" OFFSET=4 BOOTSIZE=0 BOOTFS_TYPE="" SRC_EXTLINUX=yes
    local input_hash
    input_hash=$(cat "${BASH_SOURCE[0]}" \
        "${SRC}/patch/boot0/boot0-sun20i-d1/0001-adjust-toc1-sd-locations.patch" | sha256sum)
    declare -g UBOOT_HASH_EXTRA="${input_hash%% *}"
    function write_uboot_platform() {
        [[ -s ${1}/boot0_sdcard_sun20iw1p1.bin && -s ${1}/u-boot.toc1 ]] || return 1
        # Disk layout: Boot0 at 128 KiB; primary TOC1 at 2 MiB; backup TOC1 at 256 KiB.
        dd if="${1}/boot0_sdcard_sun20iw1p1.bin" of="${2}" bs=512 seek=256 conv=notrunc
        dd if="${1}/u-boot.toc1" of="${2}" bs=512 seek=4096 conv=notrunc
        dd if="${1}/u-boot.toc1" of="${2}" bs=512 seek=512 conv=notrunc
    }
}
function post_create_partitions__mangopi_source_boot() {
    # Disk layout: place GPT entries immediately before ext4, outside both TOC1 slots.
    run_host_command_logged sgdisk --move-main-table=8160 "${SDCARD}.raw"
}
function post_config_uboot_target__mangopi_source_boot() {
    run_host_command_logged ./scripts/config --set-val TEXT_BASE 0x4a000000 \
        --enable EFI_PARTITION --enable PARTITION_UUIDS --enable CMD_SYSBOOT --enable FS_EXT4 --enable CMD_EXT4 \
        --enable SUNXI_MANGOPI_MQ_BOOT0
    run_host_command_logged make CROSS_COMPILE=riscv64-linux-gnu- olddefconfig
}
function post_uboot_custom_postprocess__mangopi_source_boot() {
    mangopi_build_boot0
    mangopi_build_firmware_dtb
    mangopi_pack_toc1 fw_dynamic.bin firmware.dtb u-boot.bin u-boot.toc1
}

function mangopi_pack_toc1() {
    local output=$4 index name payload entry size address checksum
    mangopi_toc1_write_u32() {
        local value=$2
        printf '%b' "$(printf '\\%03o' "$((value & 255))" "$((value >> 8 & 255))" \
            "$((value >> 16 & 255))" "$((value >> 24 & 255))")" |
            dd of="$output" bs=1 seek="$1" conv=notrunc status=none
    }
    # TOC1 has a 64-byte header and three 368-byte entries, aligned to 512 bytes.
    truncate -s 0 "$output"
    truncate -s 1536 "$output"
    mangopi_toc1_write_u32 16 $((0x89119800))
    mangopi_toc1_write_u32 20 $((0x5f0a6c39))
    mangopi_toc1_write_u32 32 3
    printf 'MIE;' | dd of="$output" bs=1 seek=60 conv=notrunc status=none
    index=0
    for name in opensbi dtb u-boot; do
        payload=$1
        shift
        [[ -s $payload && $(od -An -tx1 -N4 "$payload" | tr -d ' \n') != 7f454c46 ]]
        entry=$((64 + index * 368))
        size=$(stat -c %s "$payload")
        printf '%s' "$name" | dd of="$output" bs=1 seek="$entry" conv=notrunc status=none
        mangopi_toc1_write_u32 "$((entry + 64))" "$(stat -c %s "$output")"
        mangopi_toc1_write_u32 "$((entry + 68))" "$size"
        case $name in
            opensbi) address=$((0x40000000)) ;;
            dtb) address=$((0x44000000)) ;;
            u-boot) address=$((0x4a000000)) ;;
        esac
        mangopi_toc1_write_u32 "$((entry + 80))" "$address"
        printf 'IIE;' | dd of="$output" bs=1 seek="$((entry + 364))" conv=notrunc status=none
        cat "$payload" >> "$output"
        head -c "$(( (512 - size % 512) % 512 ))" /dev/zero | tr '\000' '\377' >> "$output"
        index=$((index + 1))
    done
    # Disk layout: the backup TOC1 must end before the primary TOC1 at sector 4096.
    size=$(stat -c %s "$output")
    [[ $size -le $(( (4096 - 512) * 512 )) ]]
    mangopi_toc1_write_u32 36 "$size"
    checksum=$(od -An -v -tu4 --endian=little "$output" |
        awk '{ for (i = 1; i <= NF; i++) sum = (sum + $i) % 4294967296 } END { printf "%.0f", sum }')
    mangopi_toc1_write_u32 20 "$checksum"
}
