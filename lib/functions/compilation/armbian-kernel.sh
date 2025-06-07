#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Forced .config options for all Armbian kernels.
# Please note: Manually changing options doesn't check the validity of the .config file. This is done at next make time. Check for warnings in build log.

# Enables additional wireless configuration options for Wi-Fi drivers on kernels 6.13 and later.
#
# This internal function updates the kernel configuration by adding necessary wireless options
# to a global modification list, and if a .config file exists, it applies these changes directly.
# It ensures that settings for wireless drivers (e.g. cfg80211 and mac80211) are properly enabled
# to avoid build errors due to recent kernel updates.
#
# Globals:
#   KERNEL_MAJOR_MINOR            - Current kernel version in major.minor format.
#   kernel_config_modifying_hashes - Array accumulating configuration changes.
#
function armbian_kernel_config__extrawifi_enable_wifi_opts_80211() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.13; then
		kernel_config_modifying_hashes+=("CONFIG_CFG80211=m" "CONFIG_MAC80211=m" "CONFIG_MAC80211_MESH=y" "CONFIG_CFG80211_WEXT=y")
		if [[ -f .config ]]; then
			# Required by many wifi drivers; otherwise "error: 'struct net_device' has no member named 'ieee80211_ptr'"
			# In 6.13 something changed ref CONFIG_MAC80211 and CONFIG_CFG80211; enable both to preserve wireless drivers
			kernel_config_set_m CONFIG_CFG80211
			kernel_config_set_m CONFIG_MAC80211
			kernel_config_set_y CONFIG_MAC80211_MESH
			kernel_config_set_y CONFIG_CFG80211_WEXT
		fi
	fi
}

# Enables the NETKIT kernel configuration option for kernels version 6.7 and above.
#
# Globals:
#   KERNEL_MAJOR_MINOR - The kernel version string used to verify the minimum required version.
#
# This function checks if the current kernel's version is at least 6.7 and confirms the presence of a .config file.
# If both conditions are met, it alerts the user about enabling NETKIT and sets the NETKIT option to 'y' in the kernel configuration.
#
function armbian_kernel_config__netkit() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.7; then
		if [[ -f .config ]]; then
			display_alert "Enable NETKIT=y" "armbian-kernel" "debug"
			kernel_config_set_y NETKIT
		fi
	fi
}

# Disables various kernel configuration options that conflict with Armbian's kernel build requirements.
#
# Globals:
#   kernel_config_modifying_hashes - Array tracking the configuration option changes.
#   KERNEL_MAJOR_MINOR            - Kernel version used to apply version-specific configuration updates.
#
# Outputs:
#   Displays alerts to notify about the configuration changes being applied.
#
# Description:
#   This function disables several kernel configuration options such as module compression, module signing,
#   and automatic versioning to speed up the build process and ensure compatibility with Armbian requirements.
#   It forces EXPERT mode (EXPERT=y) to ensure hidden configurations are visible and applies different module
#   compression settings based on the kernel version. All modifications are only performed if the .config file exists.
#
function armbian_kernel_config__disable_various_options() {
	kernel_config_modifying_hashes+=("CONFIG_MODULE_COMPRESS_NONE=y" "CONFIG_MODULE_SIG=n" "CONFIG_LOCALVERSION_AUTO=n" "EXPERT=y")
	if [[ -f .config ]]; then
		display_alert "Enable CONFIG_EXPERT=y" "armbian-kernel" "debug"
		kernel_config_set_y EXPERT # Too many config options are hidden behind EXPERT=y, lets have it always on

		display_alert "Disabling module compression and signing / debug / auto version" "armbian-kernel" "debug"
		# DONE: Disable: signing, and compression of modules, for speed.
		kernel_config_set_n CONFIG_MODULE_COMPRESS_XZ # No use double-compressing modules
		kernel_config_set_n CONFIG_MODULE_COMPRESS_ZSTD
		kernel_config_set_n CONFIG_MODULE_COMPRESS_GZIP

		if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.12; then
			kernel_config_set_n CONFIG_MODULE_COMPRESS # Introduced in 6.12 (see https://github.com/torvalds/linux/commit/c7ff693fa2094ba0a9d0a20feb4ab1658eff9c33)
		elif linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.0; then
			kernel_config_set_y CONFIG_MODULE_COMPRESS_NONE # Introduced in 6.0
		else
			kernel_config_set_n CONFIG_MODULE_COMPRESS # Only available up to 5.12
		fi

		kernel_config_set_n CONFIG_SECURITY_LOCKDOWN_LSM
		kernel_config_set_n CONFIG_MODULE_SIG     # No use signing modules
		kernel_config_set_n CONFIG_MODULE_SIG_ALL # No use auto-signing modules
		kernel_config_set_n MODULE_SIG_FORCE      # No forcing of module sign verification
		kernel_config_set_n IMA_APPRAISE_MODSIG   # No appraisal module-style either

		# DONE: Disable: version shenanigans
		kernel_config_set_n CONFIG_LOCALVERSION_AUTO      # This causes a mismatch between what Armbian wants and what make produces.
		kernel_config_set_string CONFIG_LOCALVERSION '""' # Must be empty; make is later invoked with LOCALVERSION and it adds up
	fi
}

function armbian_kernel_config__force_pa_va_48_bits_on_arm64() {
	declare -A opts_val=()
	declare -a opts_y=() opts_n=()
	if [[ "${ARCH}" == "arm64" ]]; then
		opts_y+=("CONFIG_ARM64_VA_BITS_48")
		opts_val["CONFIG_ARM64_PA_BITS"]="48"
	fi
	armbian_kernel_config_apply_opts_from_arrays
}

# Configures kernel options to enable or disable eBPF and BTF debug information.
#
# This function adjusts kernel configuration settings based on the value of the global
# variable KERNEL_BTF and the amount of available system memory. When KERNEL_BTF is set
# to "no", the function disables all debug and BTF options (while leaving eBPF options unchanged).
# Otherwise, it checks if the system has at least 6451 MiB of available RAM. If memory is
# insufficient and KERNEL_BTF is not explicitly set to "yes", the function exits with an error.
# When sufficient memory is available or KERNEL_BTF is forced to "yes", it enables eBPF and BTF
# support, including a set of related debug options.
#
# Globals:
#   KERNEL_BTF   - Determines whether BTF debug information should be enabled ("yes" to enable,
#                  "no" to disable).
#   /proc/meminfo - Used to calculate available system memory in MiB.
#
# Outputs:
#   Alerts are displayed via the display_alert function to indicate configuration changes.
#   The function may exit with an error message if the available memory is insufficient.
#
# Returns:
#   0 on successful configuration application.
#
function armbian_kernel_config__600_enable_ebpf_and_btf_info() {
	declare -A opts_val=()
	declare -a opts_y=() opts_n=()

	if [[ "${KERNEL_BTF}" == "no" ]]; then # If user is explicit by passing "KERNEL_BTF=no", then actually disable all debug info.
		display_alert "Disabling eBPF and BTF info for kernel" "as requested by KERNEL_BTF=no" "info"
		opts_y+=("CONFIG_DEBUG_INFO_NONE")                                                                               # Enable the "none" option
		opts_n+=("CONFIG_DEBUG_INFO" "CONFIG_DEBUG_INFO_DWARF5" "CONFIG_DEBUG_INFO_BTF" "CONFIG_DEBUG_INFO_BTF_MODULES") # BTF & CO-RE == off
		# We don't disable the eBPF options, as eBPF itself doesn't require BTF (debug info) and doesnt' consume as much memory during build as BTF debug info does.
	else
		declare -i available_physical_memory_mib
		available_physical_memory_mib=$(($(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1024)) # MiB
		display_alert "Considering available RAM for BTF build" "${available_physical_memory_mib} MiB" "info"

		if [[ ${available_physical_memory_mib} -lt 6451 ]]; then # If less than 6451 MiB of RAM is available, then exit with an error, telling the user to avoid pain and set KERNEL_BTF=no ...
			if [[ "${KERNEL_BTF}" == "yes" ]]; then                 # ... except if the user knows better, and has set KERNEL_BTF=yes, then we'll just warn.
				display_alert "Not enough RAM available (${available_physical_memory_mib}Mib) for BTF build" "but KERNEL_BTF=yes is set; enabling BTF" "warn"
			else
				exit_with_error "Not enough RAM available (${available_physical_memory_mib}Mib) for BTF build. Please set 'KERNEL_BTF=no' to avoid running out of memory during the kernel LD/BTF build step; or ignore this check by setting 'KERNEL_BTF=yes' -- that might put a lot of load on your swap disk, if any."
			fi
		fi

		display_alert "Enabling eBPF and BTF info" "for fully BTF & CO-RE enabled kernel" "info"
		opts_n+=("CONFIG_DEBUG_INFO_NONE") # Make sure the "none" option is disabled
		opts_y+=(
			"CONFIG_BPF_JIT" "CONFIG_BPF_JIT_DEFAULT_ON" "CONFIG_FTRACE_SYSCALLS" "CONFIG_PROBE_EVENTS_BTF_ARGS" "CONFIG_BPF_KPROBE_OVERRIDE" # eBPF == on
			"CONFIG_DEBUG_INFO" "CONFIG_DEBUG_INFO_DWARF5" "CONFIG_DEBUG_INFO_BTF" "CONFIG_DEBUG_INFO_BTF_MODULES"                            # BTF & CO-RE == off
		)
	fi
	armbian_kernel_config_apply_opts_from_arrays

	return 0
}

# Enables ZRAM support by configuring the kernel for compressed memory swap.
#
# This function appends "CONFIG_ZRAM=y" to the global array tracking kernel modifications.
# If a .config file is present, it sets several related kernel options:
#   - Enables compressed swap space (ZSWAP).
#   - Sets the default compression pool for ZSWAP to ZBUD.
#   - Activates the compressed memory allocator (ZSMALLOC).
#   - Enables in-memory compression for swap or temporary storage (ZRAM).
#   - Allows write-back of compressed ZRAM data (ZRAM_WRITEBACK).
#   - Enables memory usage tracking for ZRAM (ZRAM_MEMORY_TRACKING).
#
# Globals:
#   kernel_config_modifying_hashes - Array used to store configuration changes.
#
function armbian_kernel_config__enable_zram_support() {
	kernel_config_modifying_hashes+=("CONFIG_ZRAM=y")
	if [[ -f .config ]]; then
		kernel_config_set_y ZSWAP                           # Enables compressed swap space in memory
		kernel_config_set_y ZSWAP_ZPOOL_DEFAULT_ZBUD        # Sets default compression pool for ZSWAP to ZBUD
		kernel_config_set_m ZSMALLOC                        # Enables compressed memory allocator for better memory usage
		kernel_config_set_m ZRAM                            # Enables in-memory block device compression for swap or temporary storage
		kernel_config_set_y ZRAM_WRITEBACK                  # Allows write-back of compressed ZRAM data to storage
		kernel_config_set_y ZRAM_MEMORY_TRACKING            # Enables tracking of memory usage in ZRAM
	fi
}

# Enables Docker support by configuring a comprehensive set of kernel options required for Docker functionality.
#
# Globals:
#   kernel_config_modifying_hashes - Global array that tracks configuration changes to be applied.
#
# Description:
#   This function appends "CONFIG_DOCKER=y" to the global modification array. If the .config file exists,
#   it sets a wide range of kernel configuration options necessary for Docker, including support for
#   filesystems (e.g., BTRFS, EXT4), control groups (cgroups), networking, security, and various netfilter
#   components. These settings ensure that the kernel is properly configured to support containerized environments.
#
function armbian_kernel_config__enable_docker_support() {
	kernel_config_modifying_hashes+=("CONFIG_DOCKER=y")
	if [[ -f .config ]]; then
		kernel_config_set_y BTRFS_FS                        # Enables the BTRFS file system support
		kernel_config_set_y BTRFS_FS_POSIX_ACL              # Enables POSIX ACL support for BTRFS
		kernel_config_set_y BLK_CGROUP                      # Enables block layer control groups (cgroups)
		kernel_config_set_y BLK_DEV_THROTTLING              # Enables block device IO throttling
		kernel_config_set_y BRIDGE_VLAN_FILTERING           # Enables VLAN filtering on network bridges
		kernel_config_set_m BRIDGE_NETFILTER                # Enables netfilter support for the bridge
		kernel_config_set_y BRIDGE                          # Enables support for Ethernet bridges
		kernel_config_set_y CFQ_GROUP_IOSCHED               # Enables CFQ (Completely Fair Queueing) I/O scheduler for cgroups
		kernel_config_set_y CGROUP_BPF                      # Enables BPF-based control groups
		kernel_config_set_y CGROUP_CPUACCT                  # Enables CPU accounting in cgroups
		kernel_config_set_y CGROUP_DEVICE                   # Enables device control in cgroups
		kernel_config_set_y CGROUP_FREEZER                  # Enables freezer for suspending tasks in cgroups
		kernel_config_set_y CGROUP_HUGETLB                  # Enables huge page control in cgroups
		kernel_config_set_y CGROUP_NET_CLASSID              # Enables network classid control in cgroups
		kernel_config_set_y CGROUP_NET_PRIO                 # Enables network priority control in cgroups
		kernel_config_set_y CGROUP_PERF                     # Enables performance counter control in cgroups
		kernel_config_set_y CGROUP_PIDS                     # Enables process ID control in cgroups
		kernel_config_set_y CGROUP_SCHED                    # Enables scheduler control in cgroups
		kernel_config_set_y CGROUPS                         # Enables general cgroup functionality
		kernel_config_set_y CPUSETS                         # Enables CPU set support for cgroups
		kernel_config_set_m CRYPTO                          # Enables cryptographic algorithms support as modules
		kernel_config_set_m CRYPTO_AEAD                     # Enables AEAD (Authenticated Encryption with Associated Data) algorithms support
		kernel_config_set_m CRYPTO_GCM                      # Enables GCM (Galois/Counter Mode) cipher support
		kernel_config_set_m CRYPTO_GHASH                    # Enables GHASH algorithm support
		kernel_config_set_m CRYPTO_SEQIV                    # Enables sequential initialization vector support for cryptographic operations
		kernel_config_set_y EVENTFD                         # Enables eventfd system calls for event notification
		kernel_config_set_y BPF_SYSCALL                     # Enables BPF (Berkeley Packet Filter) system call support
		kernel_config_set_y NF_TABLES                       # Enables nf_tables framework support
		kernel_config_set_y NF_TABLES_INET                  # Enables IPv4 and IPv6 support for nf_tables
		kernel_config_set_y NF_TABLES_NETDEV                # Enables netdevice support for nf_tables
		kernel_config_set_y CFS_BANDWIDTH                   # Enables bandwidth control for CFS (Completely Fair Scheduler)
		kernel_config_set_m DUMMY                           # Enables dummy network driver module
		kernel_config_set_y DEVPTS_MULTIPLE_INSTANCES       # Enables multiple instances of devpts (pseudo-terminal master/slave pairs)
		kernel_config_set_y ENCRYPTED_KEYS                  # Enables support for encrypted keys in the kernel
		kernel_config_set_m EXT4_FS                         # Enables EXT4 file system support as a module
		kernel_config_set_y EXT4_FS_POSIX_ACL               # Enables POSIX ACL support for EXT4
		kernel_config_set_y EXT4_FS_SECURITY                # Enables security extensions for EXT4 file system
		kernel_config_set_m IP6_NF_FILTER                   # Enables IPv6 netfilter filtering support
		kernel_config_set_m IP6_NF_MANGLE                   # Enables IPv6 netfilter mangling support
		kernel_config_set_m IP6_NF_NAT                      # Enables IPv6 network address translation support
		kernel_config_set_m IP6_NF_RAW                      # Enables raw support for IPv6 netfilter
		kernel_config_set_m IP6_NF_SECURITY                 # Enables IPv6 netfilter security features
		kernel_config_set_m IP6_NF_TARGET_MASQUERADE        # Enables IPv6 netfilter target for masquerading (NAT)
		kernel_config_set_m IPVLAN                          # Enables IPvlan network driver support
		kernel_config_set_y INET                            # Enables Internet protocol (IPv4) support
		kernel_config_set_y FAIR_GROUP_SCHED                # Enables fair group scheduling support
		kernel_config_set_m INET_ESP                        # Enables ESP (Encapsulating Security Payload) for IPv4
		kernel_config_set_y IP_NF_FILTER                    # Enables IPv4 netfilter filtering support
		kernel_config_set_m IP_NF_TARGET_MASQUERADE         # Enables IPv4 netfilter target for masquerading (NAT)
		kernel_config_set_m IP_NF_TARGET_NETMAP             # Enables IPv4 netfilter target for netmap
		kernel_config_set_m IP_NF_TARGET_REDIRECT           # Enables IPv4 netfilter target for redirect
		kernel_config_set_y IP_NF_IPTABLES                  # Enables iptables for IPv4
		kernel_config_set_m IP_NF_NAT                       # Enables NAT (Network Address Translation) support for IPv4
		kernel_config_set_m IP_NF_RAW                       # Enables raw support for IPv4 netfilter
		kernel_config_set_y IP_NF_SECURITY                  # Enables security features for IPv4 netfilter
		kernel_config_set_y IP_VS_NFCT                      # Enables connection tracking for IPVS (IP Virtual Server)
		kernel_config_set_y IP_VS_PROTO_TCP                 # Enables TCP protocol support for IPVS
		kernel_config_set_y IP_VS_PROTO_UDP                 # Enables UDP protocol support for IPVS
		kernel_config_set_m IP_VS                           # Enables IPVS (IP Virtual Server) support as a module
		kernel_config_set_m IP_VS_RR                        # Enables round-robin scheduling for IPVS
		kernel_config_set_y KEY_DH_OPERATIONS               # Enables Diffie-Hellman key exchange operations
		kernel_config_set_y KEYS                            # Enables key management framework support
		kernel_config_set_m MACVLAN                         # Enables MACVLAN network driver support
		kernel_config_set_y MEMCG                           # Enables memory controller for cgroups
		kernel_config_set_y MEMCG_KMEM                      # Enables memory controller for kmem (kernel memory) cgroups
		kernel_config_set_m NFT_NAT                         # Enables NAT (Network Address Translation) support in nftables
		kernel_config_set_m NFT_TUNNEL                      # Enables tunneling support in nftables
		kernel_config_set_m NFT_QUOTA                       # Enables quota support in nftables
		kernel_config_set_m NFT_REJECT                      # Enables reject target support in nftables
		kernel_config_set_m NFT_COMPAT                      # Enables compatibility support for older nftables versions
		kernel_config_set_m NFT_HASH                        # Enables hash-based set operations support in nftables
		kernel_config_set_m NFT_XFRM                        # Enables transformation support in nftables
		kernel_config_set_m NFT_SOCKET                      # Enables socket operations support in nftables
		kernel_config_set_m NFT_TPROXY                      # Enables transparent proxy support in nftables
		kernel_config_set_m NFT_SYNPROXY                    # Enables SYN proxy support in nftables
		kernel_config_set_m NFT_DUP_NETDEV                  # Enables duplicate netdev (network device) support in nftables
		kernel_config_set_m NFT_FWD_NETDEV                  # Enables forward netdev support in nftables
		kernel_config_set_m NFT_REJECT_NETDEV               # Enables reject netdev support in nftables
		kernel_config_set_m NF_CONNMARK_IPV4                # Enables connection mark support for IPv4 netfilter
		kernel_config_set_y NF_CONNTRACK                    # Enables connection tracking support
		kernel_config_set_m NF_CONNTRACK_FTP                # Enables FTP connection tracking support
		kernel_config_set_m NF_CONNTRACK_IRC                # Enables IRC connection tracking support
		kernel_config_set_y NF_CONNTRACK_MARK               # Enables connection mark support in netfilter
		kernel_config_set_m NF_CONNTRACK_PPTP               # Enables PPTP connection tracking support
		kernel_config_set_m NF_CONNTRACK_TFTP               # Enables TFTP connection tracking support
		kernel_config_set_y NF_CONNTRACK_ZONES              # Enables connection tracking zones support
		kernel_config_set_y NF_CONNTRACK_EVENTS             # Enables connection tracking events support
		kernel_config_set_y NF_CONNTRACK_LABELS             # Enables connection tracking labels support
		kernel_config_set_m NF_NAT                          # Enables NAT support in nf_conntrack
		kernel_config_set_m NF_NAT_MASQUERADE_IPV4          # Enables IPv4 masquerading for NAT in nf_conntrack
		kernel_config_set_m NF_NAT_IPV4                     # Enables IPv4 NAT support in nf_conntrack
		kernel_config_set_m NF_NAT_NEEDED                   # Enables NAT support in nf_conntrack when needed
		kernel_config_set_m NF_NAT_FTP                      # Enables FTP NAT support in nf_conntrack
		kernel_config_set_m NF_NAT_TFTP                     # Enables TFTP NAT support in nf_conntrack
		kernel_config_set_m NET_CLS_CGROUP                  # Enables network classification using cgroups
		kernel_config_set_y NET_CORE                        # Enables core networking stack support
		kernel_config_set_y NET_L3_MASTER_DEV               # Enables master device support for Layer 3 (L3) networking
		kernel_config_set_y NET_NS                          # Enables network namespace support
		kernel_config_set_y NET_SCHED                       # Enables network scheduler support
		kernel_config_set_y NETFILTER                       # Enables support for netfilter framework
		kernel_config_set_y NETFILTER_ADVANCED              # Enables advanced netfilter options
		kernel_config_set_m NETFILTER_XT_MATCH_ADDRTYPE     # Enables address type matching for netfilter
		kernel_config_set_m NETFILTER_XT_MATCH_BPF          # Enables BPF match support in netfilter
		kernel_config_set_m NETFILTER_XT_MATCH_CONNTRACK    # Enables connection tracking match support in netfilter
		kernel_config_set_m NETFILTER_XT_MATCH_IPVS         # Enables IPVS match support in netfilter
		kernel_config_set_m NETFILTER_XT_MARK               # Enables mark matching for netfilter
		kernel_config_set_m NETFILTER_XTABLES               # Enables x_tables support in netfilter
		kernel_config_set_m NETFILTER_XT_TARGET_MASQUERADE  # Enables masquerade target for netfilter
		kernel_config_set_y NETDEVICES                      # Enables support for network devices
		kernel_config_set_y NAMESPACES                      # Enables support for namespaces (including network namespaces)
		kernel_config_set_m OVERLAY_FS                      # Enables support for OverlayFS
		kernel_config_set_y PID_NS                          # Enables PID (Process ID) namespace support
		kernel_config_set_y POSIX_MQUEUE                    # Enables POSIX message queues support
		kernel_config_set_y PROC_PID_CPUSET                 # Enables CPU set control for /proc/{pid}/cpuset
		kernel_config_set_y PERSISTENT_KEYRINGS             # Enables persistent keyring support
		kernel_config_set_m RESOURCE_COUNTERS               # Enables resource counters support in cgroups
		kernel_config_set_y RT_GROUP_SCHED                  # Enables real-time group scheduling
		kernel_config_set_y SECURITY_APPARMOR               # Enables AppArmor security module support
		kernel_config_set_y SECCOMP                         # Enables seccomp (secure computing) support
		kernel_config_set_y SECCOMP_FILTER                  # Enables seccomp filtering
		kernel_config_set_y USER_NS                         # Enables user namespace support
		kernel_config_set_m VXLAN                           # Enables VXLAN network driver support
		kernel_config_set_m VETH                            # Enables Virtual Ethernet (veth) network driver support
		kernel_config_set_m VLAN_8021Q                      # Enables 802.1Q VLAN tagging support
		kernel_config_set_y XFRM                            # Enables transform (XFRM) framework support
		kernel_config_set_m XFRM_ALGO                       # Enables cryptographic algorithm support for XFRM
		kernel_config_set_m XFRM_USER                       # Enables user space XFRM framework support
	fi
}


# Enables live system access to the kernel configuration via /proc/config.gz.
#
# This function appends "CONFIG_IKCONFIG_PROC=y" to the global list of kernel
# configuration modifications. If the ".config" file exists, it ensures that both
# CONFIG_IKCONFIG and CONFIG_IKCONFIG_PROC are enabled, allowing the current kernel's
# configuration to be accessible and extracted for further use.
#
# Globals:
#   kernel_config_modifying_hashes - Array holding pending kernel configuration changes.
#
function armbian_kernel_config__enable_config_access_in_live_system() {
	kernel_config_modifying_hashes+=("CONFIG_IKCONFIG_PROC=y")
	if [[ -f .config ]]; then
		kernel_config_set_y CONFIG_IKCONFIG      # This information can be extracted from the kernel image file with the script scripts/extract-ikconfig and used as input to rebuild the current kernel or to build another kernel
		kernel_config_set_y CONFIG_IKCONFIG_PROC # This option enables access to the kernel configuration file through /proc/config.gz
	fi
}

function armbian_kernel_config__restore_enable_gpio_sysfs() {
	kernel_config_modifying_hashes+=("CONFIG_GPIO_SYSFS=y")
	if [[ -f .config ]]; then
		kernel_config_set_y CONFIG_GPIO_SYSFS # This was a victim of not having EXPERT=y due to some _DEBUG conflicts in old times. Re-enable it forcefully.
	fi
}

# +++++++++++ HELPERS CORNER +++++++++++
#
# Helpers for manipulating kernel config.
#
function kernel_config_set_m() {
	declare module="$1"
	state=$(./scripts/config --state "$module")

	if [ "$state" == "y" ]; then
		display_alert "${module} is already enabled as built-in"
	else
		display_alert "Enabling kernel module" "${module}=m" "debug"
		run_host_command_logged ./scripts/config --module "$module"
	fi
}

function kernel_config_set_y() {
	declare config="$1"
	display_alert "Enabling kernel config/built-in" "${config}=y" "debug"
	run_host_command_logged ./scripts/config --enable "${config}"
}

function kernel_config_set_n() {
	declare config="$1"
	display_alert "Disabling kernel config/module" "${config}=n" "debug"

	# Only set to "n" if the config option can be found in the config file.
	# Otherwise the option would maybe be considered as misconfiguration.
	if grep -qE "(\b${config}\=|CONFIG_${config}\=)" .config; then
		run_host_command_logged ./scripts/config --disable "${config}"
	elif grep -qE "(\b${config} is not set|\bCONFIG_${config} is not set)" .config; then
		display_alert "Kernel config/module was already disabled" "${config}=n skipped" "debug"
	else
		display_alert "Kernel config/module was not found in the config file" "${config}=n was not added to prevent misconfiguration" "debug"
	fi

}

function kernel_config_set_string() {
	declare config="$1"
	declare value="${2}"
	display_alert "Setting kernel config/module string" "${config}=${value}" "debug"
	run_host_command_logged ./scripts/config --set-str "${config}" "${value}"
}

function kernel_config_set_val() {
	declare config="$1"
	declare value="${2}"
	display_alert "Setting kernel config/module value" "${config}=${value}" "debug"
	run_host_command_logged ./scripts/config --set-val "${config}" "${value}"
}

# This takes opts_n, opts_y, arrays from parent scope; also the opts_val dictionary;
# it and applies them to the hashes and to the .config if it exists.
function armbian_kernel_config_apply_opts_from_arrays() {
	declare opt_y opt_val opt_n
	for opt_n in "${opts_n[@]}"; do
		kernel_config_modifying_hashes+=("${opt_n}=n")
	done

	for opt_y in "${opts_y[@]}"; do
		kernel_config_modifying_hashes+=("${opt_y}=y")
	done

	for opt_val in "${!opts_val[@]}"; do
		kernel_config_modifying_hashes+=("${opt_val}=${opts_val[$opt_val]}")
	done

	if [[ -f .config ]]; then
		for opt_n in "${opts_n[@]}"; do
			display_alert "Disabling kernel opt" "${opt_n}=n" "debug"
			kernel_config_set_n "${opt_n}"
		done

		for opt_y in "${opts_y[@]}"; do
			display_alert "Enabling kernel opt" "${opt_y}=y" "debug"
			kernel_config_set_y "${opt_y}"
		done

		for opt_val in "${!opts_val[@]}"; do
			display_alert "Setting kernel opt" "${opt_val}=${opts_val[$opt_val]}" "debug"
			kernel_config_set_val "${opt_val}" "${opts_val[$opt_val]}"
		done
	fi
}
