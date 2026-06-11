# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
OVERLAY_PREFIX="sun60i-a733"
IMAGE_PARTITION_TABLE="msdos"

# --- Kernel: Orange Pi's vendor BSP tree ---
# The sun60iw2 family file intentionally leaves kernel source to the board, so
# multiple A733 boards (which use different vendor kernel trees) can share the
# family. The Armbian build sources this board file before the family file, so
# these assignments win.

# Note: the full github.com URL is hardcoded (not ${GITHUB_SOURCE}) because that
# mirror variable is only defined *after* board configs are sourced.
KERNELSOURCE="https://github.com/orangepi-xunlong/linux-orangepi.git"

# Vendor BSP 6.6 (orange-pi-6.6-sun60iw2) is the only branch supported/validated
# for this board, so KERNEL_TARGET="vendor" above and the values are set directly.
# A 5.15 "legacy" BSP exists upstream (its only real draw is bullseye-era GPU/VPU
# blobs, irrelevant to this headless board). To add it later: set
# KERNEL_TARGET="vendor,legacy", introduce a $BRANCH case here, and add a
# linux-sun60iw2-opi-legacy.config + patch/kernel/archive/sun60iw2-opi-legacy/.
KERNELBRANCH="branch:orange-pi-6.6-sun60iw2"
declare -g KERNEL_MAJOR_MINOR="6.6"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"
LINUXCONFIG="linux-sun60iw2-opi-vendor"

# --- Boot: vendor U-Boot specifics ---
# The vendor U-Boot is a 32-bit ARM binary: uInitrd must be tagged arch=arm or
# bootm/booti rejects it ("No Linux ARM Ramdisk Image").
declare -g INITRD_ARCH="arm"
declare -g SERIALCON="ttyS0"
declare -g BOOTSCRIPT="boot-sun60iw2-opi.cmd:boot.cmd"
declare -g OFFSET=32

# Boot images (boot0_sdcard.fex / boot0_spinor.fex / boot_package.fex) are built
# entirely from pinned Orange Pi sources at image-build time by the
# build_custom_uboot__orangepi4pro() hook at the bottom of this file — nothing
# binary is committed. Pins live inline in that function so changes bust Armbian's
# u-boot artifact cache. The family then flashes the result at the SoC-standard
# offsets (write_uboot_platform/_mtd).

# --- WiFi/BT: AICSemi AIC8800D80 on SDIO (sdc1) ---
# Vendor's in-tree aic8800 modules (=m in the 6.6 BSP). Loading aic8800_fdrv
# pulls aic8800_bsp (symbol dep), powers the chip, enumerates the SDIO card and
# creates wlan0. Firmware comes from armbian-firmware via the symlink in
# post_family_tweaks below. aic8800_btlpm = Bluetooth.
# Don't swap in an out-of-tree AIC8800 DKMS driver — it shadows the in-tree bsp
# symbols and breaks fdrv ("Unknown symbol").
MODULES="aic8800_bsp aic8800_fdrv aic8800_btlpm"

# --- Board-specific rootfs tweaks (Armbian hook; runs after family_tweaks) ---
function post_family_tweaks__orangepi4pro() {
	display_alert "Orange Pi 4 Pro rootfs tweaks" "${BOARD}" "info"

	# Boot script loads uInitrd directly; minimal extraargs (headless server).
	echo "extraargs=coherent_pool=2M no_console_suspend fsck.fix=yes fsck.repair=yes" >> "${SDCARD}"/boot/armbianEnv.txt

	# AIC8800D80 WiFi/BT firmware: armbian-firmware ships the blobs at
	# /lib/firmware/aic8800/SDIO/aic8800D80/, but the in-tree vendor driver
	# requests them at the flat lowercase path /lib/firmware/aic8800d80/.
	if [[ -d "${SDCARD}/lib/firmware/aic8800/SDIO/aic8800D80" ]]; then
		ln -sfn aic8800/SDIO/aic8800D80 "${SDCARD}/lib/firmware/aic8800d80"
	else
		display_alert "aic8800D80 firmware not found in rootfs" "WiFi may not work; check armbian-firmware" "warn"
	fi

	# mtd-utils provides flash_erase/mtd_debug, needed by write_uboot_platform_mtd
	# (armbian-install "Boot from MTD Flash - system on NVMe").
	chroot_sdcard_apt_get_install mtd-utils
}

# --- Boot images: built from pinned Orange Pi sources, nothing committed ---
# The Orange Pi vendor U-Boot Makefile generates board/sunxi/sunxi_challenge.c
# with `xxd`, absent from Armbian's base container (on Ubuntu Noble xxd is split
# into its own package). It is needed only because THIS board builds U-Boot from
# source (below), so the dependency lives here, not in the SoC family file.
function add_host_dependencies__orangepi4pro_uboot_xxd() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} xxd"
}

# Implements the build_custom_uboot hook point (called by compile_uboot via
# call_extension_method) for this board. The '__orangepi4pro' suffix is REQUIRED,
# not cosmetic: Armbian only feeds *extension-method implementations* — functions
# whose name carries the '__' delimiter — into the u-boot artifact version hash
# (artifact_uboot_prepare_version -> dump_extension_method_sources_function
# "build_custom_uboot"). A plainly-named build_custom_uboot() would still RUN but
# be INVISIBLE to that hash, so cache invalidation would silently miss every
# change. Keep the '__' suffix.
function build_custom_uboot__orangepi4pro() {
	# Build the Orange Pi 4 Pro (A733 / sun60iw2) boot images entirely from Orange
	# Pi's published sources at pinned commits. NOTHING binary is committed to
	# Armbian: this clones the two upstream Orange Pi repos at build time and packs
	#   boot0_sdcard.fex / boot0_spinor.fex  - first-stage loaders (carry the
	#                                          proprietary DRAM-init blob)
	#   boot_package.fex                     - U-Boot (compiled here from source)
	#                                          + TF-A monitor + SCP firmware
	# Conceptually this is the equivalent of Radxa's fetched u-boot .deb, which
	# Orange Pi does not publish, so we clone + build/pack on demand. The family's
	# write_uboot_platform/_mtd then flash these at the SoC-standard offsets.
	#
	# The whole builder is INLINED below (not a separate script) so that — combined
	# with the '__' naming above — ANY edit here (an upstream pin or a logic tweak)
	# changes this function body, moves the H hash, and busts the u-boot artifact
	# cache automatically. To debug the builder standalone, copy the heredoc body
	# below into a file and run it with `OUT=/some/dir bash that-file`.
	[[ -z "${uboottempdir:-}" ]] && exit_with_error "uboottempdir is not set by caller"
	[[ -z "${uboot_name:-}" ]] && exit_with_error "uboot_name is not set by caller"
	local out_dir="${uboottempdir}/usr/lib/${uboot_name}"
	mkdir -p "${out_dir}"
	display_alert "Building Orange Pi U-Boot from source (pinned upstream clones)" "${BOARD}" "info"

	# Quoted heredoc (<<'EOF'): the builder text is verbatim and fully captured by
	# the function-body hash. Inputs arrive via the environment: OUT (output dir),
	# plus optional OPI_UBOOT_REF / OPI_BUILD_REF / UBOOT_DEFCONFIG overrides; the
	# pinned defaults live inside the heredoc (and are therefore hashed too).
	local uboot_builder
	uboot_builder="$(cat <<'BUILD_BOOT_PACKAGE_EOF'
set -euo pipefail

# --- Pinned upstream sources (override via env to bump) ----------------------
OPI_UBOOT_REPO="${OPI_UBOOT_REPO:-https://github.com/orangepi-xunlong/u-boot-orangepi.git}"
OPI_UBOOT_REF="${OPI_UBOOT_REF:-b791be842935b27268ae3d00e943a9075495f30a}"   # branch v2018.05-sun60iw2
OPI_BUILD_REPO="${OPI_BUILD_REPO:-https://github.com/orangepi-xunlong/orangepi-build.git}"
OPI_BUILD_REF="${OPI_BUILD_REF:-7f776a209b72b92e8c6a06abc83b1e7597eef5af}"   # branch next
UBOOT_DEFCONFIG="${UBOOT_DEFCONFIG:-sun60iw2p1_t736_defconfig}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabi-}"   # vendor U-Boot runs in AArch32

OUT="${OUT:-$(pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${OUT}"

# --- Dependency / host checks ------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING TOOL: $1 ($2)"; exit 3; }; }
need git "git"
need "${CROSS_COMPILE}gcc" "32-bit ARM cross-compiler (apt: gcc-arm-linux-gnueabi)"
need cc "host C compiler (build-essential)"
need flex "flex"; need bison "bison"; need m4 "m4"
need xxd "xxd (apt: xxd) - vendor U-Boot generates sunxi_challenge.c with it"

QEMU=""
if [[ "$(uname -m)" != "x86_64" ]]; then
    qemu_bin="$(command -v qemu-x86_64-static || command -v qemu-x86_64 || true)"
    [[ -n "${qemu_bin}" ]] || { echo "MISSING TOOL: qemu-x86_64-static (apt: qemu-user-static) - needed to run Allwinner x86 pack tools on $(uname -m)"; exit 3; }
    # Armbian exports QEMU_CPU=cortex-a53 for its aarch64 chroot emulation. That
    # value is meaningless to qemu-x86_64 ("unable to find CPU model 'cortex-a53'")
    # and aborts the x86 pack tools, so strip it from their environment.
    QEMU="env -u QEMU_CPU ${qemu_bin}"
fi

clone_pinned() {  # repo ref dest [sparse_path]
    local repo="$1" ref="$2" dest="$3" sparse="${4:-}"
    git init -q "${dest}"
    git -C "${dest}" remote add origin "${repo}"
    if [[ -n "${sparse}" ]]; then
        git -C "${dest}" config core.sparseCheckout true
        echo "${sparse}" > "${dest}/.git/info/sparse-checkout"
    fi
    # Fetch the exact commit shallowly (GitHub allows fetch-by-SHA).
    git -C "${dest}" fetch -q --depth 1 origin "${ref}"
    git -C "${dest}" checkout -q FETCH_HEAD
}

echo ">>> Cloning Orange Pi U-Boot @ ${OPI_UBOOT_REF:0:12} ..."
clone_pinned "${OPI_UBOOT_REPO}" "${OPI_UBOOT_REF}" "${WORK}/u-boot"
echo ">>> Cloning orangepi-build pack-uboot @ ${OPI_BUILD_REF:0:12} ..."
clone_pinned "${OPI_BUILD_REPO}" "${OPI_BUILD_REF}" "${WORK}/opibuild" "external/packages/pack-uboot/*"

UBOOT_SRC="${WORK}/u-boot"
PACK="${WORK}/opibuild/external/packages/pack-uboot"
[[ -d "${PACK}/sun60iw2/bin" && -d "${PACK}/tools" ]] || { echo "pack-uboot layout not found in orangepi-build @ ${OPI_BUILD_REF}"; exit 4; }

# --- 1. Build vendor U-Boot from source (AArch32, gcc-compat flags) ----------
echo ">>> Building U-Boot (${UBOOT_DEFCONFIG}) ..."
cd "${UBOOT_SRC}"
export CROSS_COMPILE
export KCFLAGS="-fcommon -Wno-error -Wno-attributes -Wno-array-bounds -Wno-maybe-uninitialized -Wno-stringop-overflow"
make "${UBOOT_DEFCONFIG}"
# The vendor tree ships an x86-only scripts/dtc/dtc; rebuild it natively if needed.
if ! ./scripts/dtc/dtc --version >/dev/null 2>&1; then
    rm -f scripts/dtc/dtc
    make -f scripts/Makefile.build obj=scripts/dtc srctree=. objtree="$(pwd)" \
         HOSTCC=cc HOSTCFLAGS="-O2 -fcommon" LEX=flex YACC=bison
fi
# Ensure include/autoconf.mk exists (board-header #defines -> make vars).
make CROSS_COMPILE="${CROSS_COMPILE}" include/config/auto.conf
make -j"$(nproc)" CROSS_COMPILE="${CROSS_COMPILE}" KCFLAGS="${KCFLAGS}"
[[ -f u-boot.bin ]] || { echo "u-boot.bin was not produced"; exit 5; }

# --- 2. Pack boot0 + boot_package (mirrors orangepi-build postprocess) -------
echo ">>> Packing boot images ..."
cd "${WORK}"
cp -r "${PACK}/sun60iw2/bin/"* .
cp boot0_sdcard_a733.fex boot0_sdcard.fex
cp boot0_spinor_a733.fex boot0_spinor.fex
cp "${UBOOT_SRC}/u-boot.bin" u-boot.fex
"${UBOOT_SRC}/scripts/dtc/dtc" -p 2048 -W no-unit_address_vs_reg -@ -O dtb \
    -o opi4pro-u-boot.dtb -b 0 dts/u-boot-current.dts
cp sys_config/sys_config.fex sys_config.fex
sed -i 's/$/\r/' sys_config.fex                     # unix2dos
${QEMU:+$QEMU} "${PACK}/tools/script"      sys_config.fex     # -> sys_config.bin
cp opi4pro-u-boot.dtb sunxi.fex
${QEMU:+$QEMU} "${PACK}/tools/update_dtb"  sunxi.fex 4096
${QEMU:+$QEMU} "${PACK}/tools/update_uboot" -no_merge u-boot.fex sys_config.bin
sed -i 's/$/\r/' boot_package.cfg
${QEMU:+$QEMU} "${PACK}/tools/dragonsecboot" -pack boot_package.cfg

# --- 3. Deliver -------------------------------------------------------------
for f in boot0_sdcard.fex boot0_spinor.fex boot_package.fex; do
    [[ -f "${WORK}/${f}" ]] || { echo "expected output missing: ${f}"; exit 6; }
    cp "${WORK}/${f}" "${OUT}/${f}"
done
echo ">>> Done. Outputs in ${OUT}:"
ls -la "${OUT}"/boot0_sdcard.fex "${OUT}"/boot0_spinor.fex "${OUT}"/boot_package.fex
BUILD_BOOT_PACKAGE_EOF
)"
	OUT="${out_dir}" run_host_command_logged bash -c "${uboot_builder}"

	[[ -f "${out_dir}/boot_package.fex" && -f "${out_dir}/boot0_sdcard.fex" ]] || \
		exit_with_error "U-Boot boot-package build failed (no .fex produced) - see log"
	declare -g EXTENSION_BUILT_UBOOT="yes"
	return 0
}
