# Orange Pi 4 Pro (Allwinner A733 8-core 2-16G RAM GBE USB3 WiFi/BT NVMe eMMC)
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

# Video output DOES work without GPU acceleration but we still don't want to
# build desktop targets.
HAS_VIDEO_OUTPUT="no"
FULL_DESKTOP="no"

# --- Kernel: Orange Pi's vendor BSP tree ---
KERNELSOURCE="https://github.com/orangepi-xunlong/linux-orangepi.git"
KERNELBRANCH="branch:orange-pi-6.6-sun60iw2"
declare -g KERNEL_MAJOR_MINOR="6.6"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"
LINUXCONFIG="linux-sun60iw2-opi-vendor"

# The vendor U-Boot is a 32-bit ARM binary: uInitrd must be tagged arch=arm or
# bootm/booti rejects it ("No Linux ARM Ramdisk Image").
declare -g INITRD_ARCH="arm"
declare -g SERIALCON="ttyS0"
declare -g BOOTSCRIPT="boot-sun60iw2-opi.cmd:boot.cmd"
declare -g OFFSET=32

# NOTE: Don't swap in an out-of-tree AIC8800 DKMS driver — it shadows the
# in-tree bsp symbols and breaks fdrv ("Unknown symbol").
MODULES="aic8800_bsp aic8800_fdrv aic8800_btlpm"

function post_family_tweaks__orangepi4pro() {
	display_alert "Orange Pi 4 Pro rootfs tweaks" "${BOARD}" "info"

	# Boot script loads uInitrd directly; minimal extraargs (headless server).
	echo "extraargs=coherent_pool=2M no_console_suspend fsck.fix=yes fsck.repair=yes" >> "${SDCARD}"/boot/armbianEnv.txt

	# Link AIC8800D80 WiFi/BT firmware blobs from armbian-firmware default
	# location to where the in-tree vendor driver expects them.
	if [[ -d "${SDCARD}/lib/firmware/aic8800/SDIO/aic8800D80" ]]; then
		ln -sfn aic8800/SDIO/aic8800D80 "${SDCARD}/lib/firmware/aic8800d80"
	else
		display_alert "aic8800D80 firmware not found in rootfs" "WiFi may not work; check armbian-firmware" "warn"
	fi

	# mtd-utils provides flash_erase/mtd_debug for MTD Flash > NVMe boot
	chroot_sdcard_apt_get_install mtd-utils
}

function add_host_dependencies__orangepi4pro_uboot_xxd() {
	# xxd is needed to build Orange Pi's custom U-Boot fork from source
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} xxd"
}

# Build the Orange Pi 4 Pro boot images using Orange Pi's build tools and
# U-Boot fork (both released as source). Clone the repos at pinned commits,
# build the tooling, and the build the uboot images.
function build_custom_uboot__orangepi4pro() {
	local opi_uboot_repo="${OPI_UBOOT_REPO:-https://github.com/orangepi-xunlong/u-boot-orangepi.git}"
	local opi_uboot_ref="${OPI_UBOOT_REF:-b791be842935b27268ae3d00e943a9075495f30a}"   # branch v2018.05-sun60iw2

	local opi_build_repo="${OPI_BUILD_REPO:-https://github.com/orangepi-xunlong/orangepi-build.git}"
	local opi_build_ref="${OPI_BUILD_REF:-7f776a209b72b92e8c6a06abc83b1e7597eef5af}"   # branch next

	local uboot_defconfig="${UBOOT_DEFCONFIG:-sun60iw2p1_t736_defconfig}"
	local cross_compile="${CROSS_COMPILE:-arm-linux-gnueabi-}"   # vendor U-Boot is 32-bit ARM

	[[ -z "${uboottempdir:-}" ]] && exit_with_error "build_custom_uboot: uboottempdir not set by caller"
	[[ -z "${uboot_name:-}" ]] && exit_with_error "build_custom_uboot: uboot_name not set by caller"

	local orig_pwd="${PWD}"
	local out_dir="${uboottempdir}/usr/lib/${uboot_name}"
	local work_dir="$(mktemp -d)"
	local uboot_src="${work_dir}/u-boot"
	local pack_dir="${work_dir}/opibuild/external/packages/pack-uboot"
	run_host_command_logged mkdir -p "${out_dir}"

	local tool
	for tool in git "${cross_compile}gcc" cc flex bison m4 xxd; do
		command -v "${tool}" > /dev/null 2>&1 || exit_with_error "build_custom_uboot: missing host tool '${tool}'"
	done

	# The Allwinner pack tools from orangepi-build are x86-only ELF binaries
	# so on arm64 hosts they run under qemu-x86_64-static.
	local -a qemu=()
	if [[ "$(uname -m)" != "x86_64" ]]; then
		local qemu_bin
		qemu_bin="$(command -v qemu-x86_64-static || true)"
		[[ -n "${qemu_bin}" ]] || exit_with_error "build_custom_uboot: qemu-x86_64-static needed to run the x86 pack tools on $(uname -m)"
		qemu=(env -u QEMU_CPU "${qemu_bin}")
	fi

	display_alert "Cloning Orange Pi U-Boot fork" "${opi_uboot_ref:0:12}" "info"
	run_host_command_logged git init -q "${uboot_src}"
	run_host_command_logged git -C "${uboot_src}" remote add origin "${opi_uboot_repo}"
	run_host_command_logged git -C "${uboot_src}" fetch -q --depth 1 origin "${opi_uboot_ref}"
	run_host_command_logged git -C "${uboot_src}" checkout -q FETCH_HEAD

	display_alert "Cloning pack-uboot from orangepi-build" "${opi_build_ref:0:12}" "info"
	run_host_command_logged git init -q "${work_dir}/opibuild"
	run_host_command_logged git -C "${work_dir}/opibuild" remote add origin "${opi_build_repo}"
	run_host_command_logged git -C "${work_dir}/opibuild" config core.sparseCheckout true
	echo "external/packages/pack-uboot/*" > "${work_dir}/opibuild/.git/info/sparse-checkout"
	run_host_command_logged git -C "${work_dir}/opibuild" fetch -q --depth 1 origin "${opi_build_ref}"
	run_host_command_logged git -C "${work_dir}/opibuild" checkout -q FETCH_HEAD
	[[ -d "${pack_dir}/sun60iw2/bin" && -d "${pack_dir}/tools" ]] || exit_with_error "build_custom_uboot: pack-uboot layout missing in orangepi-build @ ${opi_build_ref}"

	# Build Orange Pi U-Boot fork (AArch32; gcc-compat flags for this old vendor
	# tree). The vendor tree ships an x86-only scripts/dtc/dtc, rebuilt natively.
	display_alert "Building Orange Pi U-Boot fork" "${uboot_defconfig}" "info"
	cd "${uboot_src}" || exit_with_error "build_custom_uboot: cannot cd ${uboot_src}"
	run_host_command_logged make CROSS_COMPILE="${cross_compile}" "${uboot_defconfig}"
	if ! ./scripts/dtc/dtc --version > /dev/null 2>&1; then
		run_host_command_logged rm -f scripts/dtc/dtc
		make -f scripts/Makefile.build obj=scripts/dtc srctree=. objtree="${uboot_src}" HOSTCC=cc HOSTCFLAGS="-O2 -fcommon" LEX=flex YACC=bison \
			|| exit_with_error "build_custom_uboot: native scripts/dtc rebuild failed"   # direct: HOSTCFLAGS value has a space
	fi
	run_host_command_logged make CROSS_COMPILE="${cross_compile}" include/config/auto.conf   # board-header #defines -> make vars
	local kcflags="-fcommon -Wno-error -Wno-attributes -Wno-array-bounds -Wno-maybe-uninitialized -Wno-stringop-overflow"
	make -j"$(nproc)" CROSS_COMPILE="${cross_compile}" KCFLAGS="${kcflags}" \
		|| exit_with_error "build_custom_uboot: u-boot build failed"   # direct: KCFLAGS value has spaces
	[[ -f u-boot.bin ]] || exit_with_error "build_custom_uboot: u-boot.bin was not produced"

	# Pack boot0 + boot_package (mirrors orangepi-build's postprocess). The boot0
	# blobs, TF-A monitor, SCP firmware, sys_config, boot_package.cfg and the dts
	# come from the pinned pack-uboot/sun60iw2/bin; the x86 pack tools run via qemu.
	display_alert "Packing boot images" "${BOARD}" "info"
	cd "${work_dir}" || exit_with_error "build_custom_uboot: cannot cd ${work_dir}"

	run_host_command_logged cp -r "${pack_dir}/sun60iw2/bin/"* .
	run_host_command_logged cp boot0_sdcard_a733.fex boot0_sdcard.fex
	run_host_command_logged cp boot0_spinor_a733.fex boot0_spinor.fex

	run_host_command_logged cp "${uboot_src}/u-boot.bin" u-boot.fex
	run_host_command_logged "${uboot_src}/scripts/dtc/dtc" -p 2048 -W no-unit_address_vs_reg -@ -O dtb -o opi4pro-u-boot.dtb -b 0 dts/u-boot-current.dts
	run_host_command_logged cp sys_config/sys_config.fex sys_config.fex
	sed -i 's/$/\r/' sys_config.fex || exit_with_error "build_custom_uboot: CRLF conversion of sys_config.fex failed"   # direct: sed CR
	run_host_command_logged "${qemu[@]}" "${pack_dir}/tools/script" sys_config.fex

	run_host_command_logged cp opi4pro-u-boot.dtb sunxi.fex
	run_host_command_logged "${qemu[@]}" "${pack_dir}/tools/update_dtb" sunxi.fex 4096
	run_host_command_logged "${qemu[@]}" "${pack_dir}/tools/update_uboot" -no_merge u-boot.fex sys_config.bin
	sed -i 's/$/\r/' boot_package.cfg || exit_with_error "build_custom_uboot: CRLF conversion of boot_package.cfg failed"   # direct: sed CR
	run_host_command_logged "${qemu[@]}" "${pack_dir}/tools/dragonsecboot" -pack boot_package.cfg

	# Deliver the three blobs to the artifact dir.
	run_host_command_logged cp "${work_dir}/boot0_sdcard.fex" "${work_dir}/boot0_spinor.fex" "${work_dir}/boot_package.fex" "${out_dir}/"

	[[ -f "${out_dir}/boot_package.fex" && -f "${out_dir}/boot0_sdcard.fex" && -f "${out_dir}/boot0_spinor.fex" ]] \
		|| exit_with_error "build_custom_uboot: bootloader build failed — missing one of boot_package/boot0_sdcard/boot0_spinor .fex"
	cd "${orig_pwd}" || true   # leave a valid cwd before deleting work_dir
	rm -rf "${work_dir}"

	declare -g EXTENSION_BUILT_UBOOT="yes"
	return 0
}
