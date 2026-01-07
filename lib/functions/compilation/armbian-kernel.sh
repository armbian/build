#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Forced .config options for all Armbian kernels.

# IMPORTANT:
#   armbian_kernel_config hooks are called twice: once for obtaining the version via hashing,
#   and once for actually modifying the kernel .config. They *must* be consistent, and can't depend on
#   the contents of the .config (which is not available during version calculation).
#
#   To facilitate this, use the arrays opts_n/opts_y/opts_m and/or the opts_val dictionary.
#   those will be hashed and applied at the correct moments automatically.
#
#   Be consistent -- both the versioning/hashing mechanism and the fast-rebuild principles depend on it.
#
#   A word on modules or built-in: try use modules if possible. Certain things should be built-in,
#   specially if they're needed before the initramfs is available.
#
#   The exact same also applies to custom_kernel_config hooks.

# Please note: Manually changing options doesn't check the validity of the .config file. This is done at next make time. Check for warnings in build log.

# Enables additional wireless configuration options for Wi-Fi drivers on kernels 6.13 and later.
# ensures that settings for wireless drivers (e.g. cfg80211 and mac80211) are properly enabled
# to avoid build errors due to recent kernel updates.
function armbian_kernel_config__extrawifi_enable_wifi_opts_80211() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.13; then
		# Required by many wifi drivers; otherwise "error: 'struct net_device' has no member named 'ieee80211_ptr'"
		# In 6.13 something changed ref MAC80211 and CFG80211; enable both to preserve wireless drivers
		opts_m+=("CFG80211")
		opts_m+=("MAC80211")
		opts_y+=("MAC80211_MESH")
		opts_y+=("CFG80211_WEXT")
	fi
}

# Enables the NETKIT kernel configuration option for kernels version 6.7 and above.
function armbian_kernel_config__netkit() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.7; then
		opts_y+=("NETKIT")
	fi
}

# Disables various kernel configuration options that conflict with Armbian's kernel build requirements.
# This function disables several kernel configuration options such as
# module signing and automatic versioning to speed up the build
# process and ensure compatibility with Armbian requirements.
# Additionally, it forces EXPERT mode (EXPERT=y) to ensure otherwise
# hidden configurations are visible.
function armbian_kernel_config__disable_various_options() {
	display_alert "Enable EXPERT=y" "armbian-kernel" "debug"
	opts_y+=("EXPERT") # Too many config options are hidden behind EXPERT=y, lets have it always on

	display_alert "Disabling module signing / debug / auto version" "armbian-kernel" "debug"
	opts_n+=("SECURITY_LOCKDOWN_LSM")
	opts_n+=("MODULE_SIG")          # No use signing modules
	opts_n+=("MODULE_SIG_ALL")      # No use auto-signing modules
	opts_n+=("MODULE_SIG_FORCE")    # No forcing of module sign verification
	opts_n+=("IMA_APPRAISE_MODSIG") # No appraisal module-style either

	# DONE: Disable: version shenanigans
	opts_n+=("LOCALVERSION_AUTO") # This causes a mismatch between what Armbian wants and what make produces.
	opts_val["LOCALVERSION"]='""' # Must be empty; make is later invoked with LOCALVERSION and it adds up
}

function armbian_kernel_config__force_pa_va_48_bits_on_arm64() {
	if [[ "${ARCH}" == "arm64" ]]; then
		opts_y+=("ARM64_VA_BITS_48")
		opts_val["ARM64_PA_BITS"]="48"
	fi
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
function armbian_kernel_config__600_enable_ebpf_and_btf_info() {
	if [[ "${KERNEL_BTF}" == "no" ]]; then # If user is explicit by passing "KERNEL_BTF=no", then actually disable all debug info.
		display_alert "Disabling eBPF and BTF info for kernel" "as requested by KERNEL_BTF=no" "info"
		opts_y+=("DEBUG_INFO_NONE")                                                          # Enable the "none" option
		opts_n+=("DEBUG_INFO" "DEBUG_INFO_DWARF5" "DEBUG_INFO_BTF" "DEBUG_INFO_BTF_MODULES") # BTF & CO-RE == off
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
		opts_n+=("DEBUG_INFO_NONE") # Make sure the "none" option is disabled
		opts_y+=(
			"BPF_JIT" "BPF_JIT_DEFAULT_ON" "FTRACE_SYSCALLS" "PROBE_EVENTS_BTF_ARGS" "BPF_KPROBE_OVERRIDE" # eBPF == on
			"DEBUG_INFO" "DEBUG_INFO_DWARF5" "DEBUG_INFO_BTF" "DEBUG_INFO_BTF_MODULES"                     # BTF & CO-RE == off
		)
	fi
}

# Enables ZRAM support by configuring the kernel for compressed memory swap.
#   - Enables compressed swap space (ZSWAP).
#   - Sets the default compression pool for ZSWAP to ZBUD.
#   - Activates the compressed memory allocator (ZSMALLOC).
#   - Enables in-memory compression for swap or temporary storage (ZRAM).
#   - Allows write-back of compressed ZRAM data (ZRAM_WRITEBACK).
#   - Enables memory usage tracking for ZRAM (ZRAM_MEMORY_TRACKING).
#   - Enables various ZRAM compression backend algorithms (LZ4, LZ4HC, ZSTD, DEFLATE, 842, LZO).
function armbian_kernel_config__enable_zram_support() {
	opts_y+=("ZSWAP")                    # Enables compressed swap space in memory
	opts_y+=("ZSWAP_ZPOOL_DEFAULT_ZBUD") # Sets default compression pool for ZSWAP to ZBUD
	opts_m+=("ZSMALLOC")                 # Enables compressed memory allocator for better memory usage
	opts_m+=("ZRAM")                     # Enables in-memory block device compression for swap or temporary storage
	opts_y+=("ZRAM_WRITEBACK")           # Allows write-back of compressed ZRAM data to storage
	opts_y+=("ZRAM_MEMORY_TRACKING")     # Enables tracking of memory usage in ZRAM
	opts_y+=("ZRAM_BACKEND_LZ4")
	opts_y+=("ZRAM_BACKEND_LZ4HC")
	opts_y+=("ZRAM_BACKEND_ZSTD")
	opts_y+=("ZRAM_BACKEND_DEFLATE")
	opts_y+=("ZRAM_BACKEND_842")
	opts_y+=("ZRAM_BACKEND_LZO")
}

# Enables almost all IPTABLES/NFTABLES options as modules.
function armbian_kernel_config__select_nftables() {
	opts_m+=("BRIDGE_NETFILTER")         # Enables netfilter support for the bridge
	opts_m+=("IP6_NF_FILTER")            # Enables IPv6 netfilter filtering support
	opts_m+=("IP6_NF_IPTABLES")          # IP6 tables support (required for filtering)
	opts_m+=("IP6_NF_MANGLE")            # Enables IPv6 netfilter mangling support
	opts_m+=("IP6_NF_MATCH_AH")          # "ah" match support
	opts_m+=("IP6_NF_MATCH_EUI64")       # "eui64" address check
	opts_m+=("IP6_NF_MATCH_FRAG")        # "frag" Fragmentation header match support
	opts_m+=("IP6_NF_MATCH_HL")          # "hl" hoplimit match support
	opts_m+=("IP6_NF_MATCH_IPV6HEADER")  # "ipv6header" IPv6 Extension Headers Match
	opts_m+=("IP6_NF_MATCH_MH")          # "mh" match support
	opts_m+=("IP6_NF_MATCH_OPTS")        # "hbh" hop-by-hop and "dst" opts header match support
	opts_m+=("IP6_NF_MATCH_RPFILTER")    # "rpfilter" reverse path filter match support
	opts_m+=("IP6_NF_MATCH_RT")          # "rt" Routing header match support
	opts_m+=("IP6_NF_MATCH_SRH")         # "srh" Segment Routing header match support
	opts_m+=("IP6_NF_NAT")               # Enables IPv6 network address translation support
	opts_m+=("IP6_NF_RAW")               # Enables raw support for IPv6 netfilter
	opts_m+=("IP6_NF_SECURITY")          # Enables IPv6 netfilter security features
	opts_m+=("IP6_NF_TARGET_HL")         # "HL" hoplimit target support
	opts_m+=("IP6_NF_TARGET_MASQUERADE") # Enables IPv6 netfilter target for masquerading (NAT)
	opts_m+=("IP6_NF_TARGET_NPT")        # NPT (Network Prefix translation) target support
	opts_m+=("IP6_NF_TARGET_REJECT")     # REJECT target support
	opts_m+=("IP6_NF_TARGET_SYNPROXY")   # SYNPROXY target support
	opts_m+=("IP_NF_IPTABLES")           # Enables iptables for IPv4
	opts_m+=("IP_NF_FILTER")             # filter table
	opts_m+=("IP_NF_MANGLE")             # mangle table
	opts_m+=("IP_NF_TARGET_MASQUERADE")  # Enables IPv4 netfilter target for masquerading (NAT)
	opts_m+=("IP_NF_TARGET_NETMAP")      # Enables IPv4 netfilter target for netmap
	opts_m+=("IP_NF_TARGET_REDIRECT")    # Enables IPv4 netfilter target for redirect
	opts_m+=("IP_NF_NAT")                # Enables NAT (Network Address Translation) support for IPv4
	opts_m+=("IP_NF_RAW")                # Enables raw support for IPv4 netfilter
	opts_m+=("IP_NF_SECURITY")           # Enables security features for IPv4 netfilter
	opts_m+=("NET_ACT_IPT")
	opts_m+=("NET_EMATCH_IPT")     # IPtables Matches
	opts_y+=("NETFILTER_BPF_LINK") # BPF link support for netfilter hooks
	opts_m+=("NETFILTER_CONNCOUNT")
	opts_y+=("NETFILTER_EGRESS") # Netfilter egress support
	opts_y+=("NETFILTER_FAMILY_ARP")
	opts_y+=("NETFILTER_FAMILY_BRIDGE")
	opts_y+=("NETFILTER_INGRESS")      # Netfilter ingress support
	opts_m+=("NETFILTER_NETLINK_ACCT") # Netfilter NFACCT over NFNETLINK interface
	opts_y+=("NETFILTER_NETLINK_GLUE_CT")
	opts_m+=("NETFILTER_NETLINK_HOOK") # Netfilter base hook dump support
	opts_m+=("NETFILTER_NETLINK_LOG")  # Netfilter LOG over NFNETLINK interface
	opts_m+=("NETFILTER_NETLINK")
	opts_m+=("NETFILTER_NETLINK_OSF")   # Netfilter OSF over NFNETLINK interface
	opts_m+=("NETFILTER_NETLINK_QUEUE") # Netfilter NFQUEUE over NFNETLINK interface
	opts_m+=("NETFILTER_SYNPROXY")
	opts_y+=("NETFILTER_XTABLES_COMPAT")        # Netfilter Xtables 32bit support
	opts_m+=("NETFILTER_XTABLES")               # Enables x_tables support in netfilter
	opts_m+=("NETFILTER_XT_CONNMARK")           # ctmark target and match support
	opts_m+=("NETFILTER_XT_MARK")               # Enables mark matching for netfilter
	opts_m+=("NETFILTER_XT_MATCH_ADDRTYPE")     # Enables address type matching for netfilter
	opts_m+=("NETFILTER_XT_MATCH_BPF")          # Enables BPF match support in netfilter
	opts_m+=("NETFILTER_XT_MATCH_CGROUP")       # "control group" match support
	opts_m+=("NETFILTER_XT_MATCH_CLUSTER")      # "cluster" match support
	opts_m+=("NETFILTER_XT_MATCH_COMMENT")      # "comment" match support
	opts_m+=("NETFILTER_XT_MATCH_CONNBYTES")    # "connbytes" per-connection counter match support
	opts_m+=("NETFILTER_XT_MATCH_CONNLABEL")    # "connlabel" match support
	opts_m+=("NETFILTER_XT_MATCH_CONNLIMIT")    # "connlimit" match support
	opts_m+=("NETFILTER_XT_MATCH_CONNMARK")     # "connmark" connection mark match support
	opts_m+=("NETFILTER_XT_MATCH_CONNTRACK")    # Enables connection tracking match support in netfilter
	opts_m+=("NETFILTER_XT_MATCH_CPU")          # "cpu" match support
	opts_m+=("NETFILTER_XT_MATCH_DCCP")         # "dccp" protocol match support
	opts_m+=("NETFILTER_XT_MATCH_DEVGROUP")     # "devgroup" match support
	opts_m+=("NETFILTER_XT_MATCH_DSCP")         # "dscp" and "tos" match support
	opts_m+=("NETFILTER_XT_MATCH_ECN")          # "ecn" match support
	opts_m+=("NETFILTER_XT_MATCH_ESP")          # "esp" match support
	opts_m+=("NETFILTER_XT_MATCH_HASHLIMIT")    # "hashlimit" match support
	opts_m+=("NETFILTER_XT_MATCH_HELPER")       # "helper" match support
	opts_m+=("NETFILTER_XT_MATCH_HL")           # "hl" hoplimit/TTL match support
	opts_m+=("NETFILTER_XT_MATCH_IPCOMP")       # "ipcomp" match support
	opts_m+=("NETFILTER_XT_MATCH_IPRANGE")      # "iprange" address range match support
	opts_m+=("NETFILTER_XT_MATCH_IPVS")         # Enables IPVS match support in netfilter
	opts_m+=("NETFILTER_XT_MATCH_L2TP")         # "l2tp" match support
	opts_m+=("NETFILTER_XT_MATCH_LENGTH")       # "length" match support
	opts_m+=("NETFILTER_XT_MATCH_LIMIT")        # "limit" match support
	opts_m+=("NETFILTER_XT_MATCH_MAC")          # "mac" address match support
	opts_m+=("NETFILTER_XT_MATCH_MARK")         # "mark" match support
	opts_m+=("NETFILTER_XT_MATCH_MULTIPORT")    # "multiport" Multiple port match support
	opts_m+=("NETFILTER_XT_MATCH_NFACCT")       # "nfacct" match support
	opts_m+=("NETFILTER_XT_MATCH_OSF")          # "osf" Passive OS fingerprint match
	opts_m+=("NETFILTER_XT_MATCH_OWNER")        # "owner" match support
	opts_m+=("NETFILTER_XT_MATCH_PHYSDEV")      # "physdev" match support
	opts_m+=("NETFILTER_XT_MATCH_PKTTYPE")      # "pkttype" packet type match support
	opts_m+=("NETFILTER_XT_MATCH_POLICY")       # IPsec "policy" match support
	opts_m+=("NETFILTER_XT_MATCH_QUOTA")        # "quota" match support
	opts_m+=("NETFILTER_XT_MATCH_RATEEST")      # "rateest" match support
	opts_m+=("NETFILTER_XT_MATCH_REALM")        # "realm" match support
	opts_m+=("NETFILTER_XT_MATCH_RECENT")       # "recent" match support
	opts_m+=("NETFILTER_XT_MATCH_SCTP")         # "sctp" protocol match support
	opts_m+=("NETFILTER_XT_MATCH_SOCKET")       # "socket" match support
	opts_m+=("NETFILTER_XT_MATCH_STATE")        # "state" match support
	opts_m+=("NETFILTER_XT_MATCH_STATISTIC")    # "statistic" match support
	opts_m+=("NETFILTER_XT_MATCH_STRING")       # "string" match support
	opts_m+=("NETFILTER_XT_MATCH_TCPMSS")       # "tcpmss" match support
	opts_m+=("NETFILTER_XT_MATCH_TIME")         # "time" match support
	opts_m+=("NETFILTER_XT_MATCH_U32")          # "u32" match support
	opts_m+=("NETFILTER_XT_NAT")                # "SNAT and DNAT" targets support
	opts_m+=("NETFILTER_XT_SET")                # set target and match support
	opts_m+=("NETFILTER_XT_TARGET_AUDIT")       # AUDIT target support
	opts_m+=("NETFILTER_XT_TARGET_CHECKSUM")    # CHECKSUM target support
	opts_m+=("NETFILTER_XT_TARGET_CLASSIFY")    # "CLASSIFY" target support
	opts_m+=("NETFILTER_XT_TARGET_CONNMARK")    # "CONNMARK" target support
	opts_m+=("NETFILTER_XT_TARGET_CONNSECMARK") # "CONNSECMARK" target support
	opts_m+=("NETFILTER_XT_TARGET_CT")          # "CT" target support
	opts_m+=("NETFILTER_XT_TARGET_DSCP")        # "DSCP" and "TOS" target support
	opts_m+=("NETFILTER_XT_TARGET_FLOWOFFLOAD")
	opts_m+=("NETFILTER_XT_TARGET_HL")          # "HL" hoplimit target support
	opts_m+=("NETFILTER_XT_TARGET_HMARK")       # "HMARK" target support
	opts_m+=("NETFILTER_XT_TARGET_IDLETIMER")   # IDLETIMER target support
	opts_m+=("NETFILTER_XT_TARGET_LED")         # "LED" target support
	opts_m+=("NETFILTER_XT_TARGET_LOG")         # LOG target support
	opts_m+=("NETFILTER_XT_TARGET_MARK")        # "MARK" target support
	opts_m+=("NETFILTER_XT_TARGET_MASQUERADE")  # Enables masquerade target for netfilter
	opts_m+=("NETFILTER_XT_TARGET_NETMAP")      # "NETMAP" target support
	opts_m+=("NETFILTER_XT_TARGET_NFLOG")       # "NFLOG" target support
	opts_m+=("NETFILTER_XT_TARGET_NFQUEUE")     # "NFQUEUE" target Support
	opts_m+=("NETFILTER_XT_TARGET_NOTRACK")     # "NOTRACK" target support (DEPRECATED)
	opts_m+=("NETFILTER_XT_TARGET_RATEEST")     # "RATEEST" target support
	opts_m+=("NETFILTER_XT_TARGET_REDIRECT")    # REDIRECT target support
	opts_m+=("NETFILTER_XT_TARGET_SECMARK")     # "SECMARK" target support
	opts_m+=("NETFILTER_XT_TARGET_TCPMSS")      # "TCPMSS" target support
	opts_m+=("NETFILTER_XT_TARGET_TCPOPTSTRIP") # "TCPOPTSTRIP" target support
	opts_m+=("NETFILTER_XT_TARGET_TEE")         # "TEE" - packet cloning to alternate destination
	opts_m+=("NETFILTER_XT_TARGET_TPROXY")      # "TPROXY" target transparent proxying support
	opts_m+=("NETFILTER_XT_TARGET_TRACE")       # "TRACE" target support
	opts_y+=("NETFILTER")                       # Enables support for netfilter framework
	opts_y+=("NETFILTER_ADVANCED")              # Enables advanced netfilter options
	opts_m+=("NET_IP_TUNNEL")
	opts_y+=("NF_TABLES_ARP") # ARP nf_tables support
	opts_m+=("NF_TABLES_BRIDGE")
	opts_y+=("NF_TABLES_INET") # Enables IPv4 and IPv6 support for nf_tables
	opts_y+=("NF_TABLES_IPV4")
	opts_y+=("NF_TABLES_IPV6")
	opts_m+=("NF_TABLES")              # Enables nf_tables framework support
	opts_y+=("NF_TABLES_NETDEV")       # Enables netdevice support for nf_tables
	opts_m+=("NF_CONNTRACK")           # Enables connection tracking support
	opts_m+=("NF_CONNTRACK_FTP")       # Enables FTP connection tracking support
	opts_m+=("NF_CONNTRACK_IRC")       # Enables IRC connection tracking support
	opts_y+=("NF_CONNTRACK_MARK")      # Enables connection mark support in netfilter
	opts_m+=("NF_CONNTRACK_PPTP")      # Enables PPTP connection tracking support
	opts_m+=("NF_CONNTRACK_TFTP")      # Enables TFTP connection tracking support
	opts_y+=("NF_CONNTRACK_ZONES")     # Enables connection tracking zones support
	opts_y+=("NF_CONNTRACK_EVENTS")    # Enables connection tracking events support
	opts_y+=("NF_CONNTRACK_LABELS")    # Enables connection tracking labels support
	opts_m+=("NF_NAT")                 # Enables NAT support in nf_conntrack
	opts_m+=("NF_NAT_MASQUERADE_IPV4") # Enables IPv4 masquerading for NAT in nf_conntrack
	opts_m+=("NF_NAT_IPV4")            # Enables IPv4 NAT support in nf_conntrack
	opts_m+=("NF_NAT_FTP")             # Enables FTP NAT support in nf_conntrack
	opts_m+=("NF_NAT_TFTP")            # Enables TFTP NAT support in nf_conntrack
	opts_m+=("NFT_BRIDGE_META")        # Netfilter nf_table bridge meta support
	opts_m+=("NFT_BRIDGE_REJECT")      # Netfilter nf_tables bridge reject support
	opts_m+=("NFT_COMPAT_ARP")
	opts_m+=("NFT_COMPAT")    # Enables compatibility support for older nftables versions
	opts_m+=("NFT_CONNLIMIT") # Netfilter nf_tables connlimit module
	opts_m+=("NFT_COUNTER")
	opts_m+=("NFT_CT")         # Netfilter nf_tables conntrack module
	opts_m+=("NFT_DUP_IPV4")   # IPv4 nf_tables packet duplication support
	opts_m+=("NFT_DUP_IPV6")   # IPv6 nf_tables packet duplication support
	opts_m+=("NFT_DUP_NETDEV") # Enables duplicate netdev (network device) support in nftables
	opts_m+=("NFT_FIB_INET")
	opts_m+=("NFT_FIB_IPV4") # nf_tables fib / ip route lookup support
	opts_m+=("NFT_FIB_IPV6") # nf_tables fib / ipv6 route lookup support
	opts_m+=("NFT_FIB")
	opts_m+=("NFT_FIB_NETDEV")   # Netfilter nf_tables netdev fib lookups support
	opts_m+=("NFT_FLOW_OFFLOAD") # Netfilter nf_tables hardware flow offload module
	opts_m+=("NFT_FWD_NETDEV")   # Enables forward netdev support in nftables
	opts_m+=("NFT_HASH")         # Enables hash-based set operations support in nftables
	opts_m+=("NFT_LIMIT")        # Netfilter nf_tables limit module
	opts_m+=("NFT_LOG")          # Netfilter nf_tables log module
	opts_m+=("NFT_MASQ")
	opts_m+=("NFT_NAT")    # Enables NAT (Network Address Translation) support in nftables
	opts_m+=("NFT_NUMGEN") # Netfilter nf_tables number generator module
	opts_m+=("NFT_OBJREF")
	opts_m+=("NFT_OSF")
	opts_m+=("NFT_QUEUE") # Netfilter nf_tables queue module
	opts_m+=("NFT_QUOTA") # Enables quota support in nftables
	opts_m+=("NFT_REDIR")
	opts_m+=("NFT_REJECT_INET")
	opts_m+=("NFT_REJECT_IPV4")
	opts_m+=("NFT_REJECT_IPV6")
	opts_m+=("NFT_REJECT")        # Enables reject target support in nftables
	opts_m+=("NFT_REJECT_NETDEV") # Enables reject netdev support in nftables
	opts_m+=("NFT_SOCKET")        # Enables socket operations support in nftables
	opts_m+=("NFT_SYNPROXY")      # Enables SYN proxy support in nftables
	opts_m+=("NFT_TPROXY")        # Enables transparent proxy support in nftables
	opts_m+=("NFT_TUNNEL")        # Enables tunneling support in nftables
	opts_m+=("NFT_XFRM")          # Enables transformation support in nftables
	opts_m+=("IP_SET")            # IP Set core
	opts_m+=("IP_SET_HASH_IP")
	opts_m+=("IP_SET_HASH_NET")
	opts_m+=("IP_SET_HASH_IPPORT")
	opts_m+=("IP_SET_HASH_NETPORT")
	opts_m+=("IP_SET_HASH_IPPORTNET")
	opts_m+=("IP_SET_BITMAP_IP")
	opts_m+=("IP_SET_BITMAP_PORT")
}

# Enables various filesystems that we expect our users to need/demand in boot dependencies.
# OVERLAY_FS isn't here b/c it's never required for boot [that this author is aware of as of 2026Jan]
# if you as a kernel family maintainer want to override this, make a function call like below:
# extension_hook_opt_out "armbian_kernel_config__enable_various_filesystems"
# and then copy this function to your config/sources/families modified as appropriate.
function armbian_kernel_config__enable_various_filesystems() {
	opts_m+=("BTRFS_FS")                  # Enables the BTRFS file system support
	opts_y+=("BTRFS_FS_POSIX_ACL")        # Enables POSIX ACL support for BTRFS
	opts_y+=("EXT4_FS")                   # Enables EXT4 file system support
	opts_y+=("EXT4_FS_POSIX_ACL")         # Enables POSIX ACL support for EXT4
	opts_y+=("EXT4_FS_SECURITY")          # Enables security extensions for EXT4 file system
	opts_m+=("EROFS_FS")                  # Extended ReadOnly FS, useful for docker images
}

# Enables Docker support by configuring a comprehensive set of kernel options required for Docker functionality.
#   sets a wide range of kernel configuration options necessary for Docker, including support for
#   control groups (cgroups), networking, security, and various netfilter
#   components. These settings ensure that the kernel is properly configured to support containerized environments.
# ATTENTION: filesystems like EXT4 and BTRFS are now omitted, so it's each kernel's .config responsibility to enable
#            them as builtin or modules as each sees fit.
function armbian_kernel_config__enable_docker_support() {
	opts_y+=("BLK_CGROUP")                # Enables block layer control groups (cgroups)
	opts_y+=("BLK_DEV_THROTTLING")        # Enables block device IO throttling
	opts_y+=("BRIDGE_VLAN_FILTERING")     # Enables VLAN filtering on network bridges
	opts_y+=("BRIDGE")                    # Enables support for Ethernet bridges
	opts_y+=("CFQ_GROUP_IOSCHED")         # Enables CFQ (Completely Fair Queueing) I/O scheduler for cgroups
	opts_y+=("CGROUP_BPF")                # Enables BPF-based control groups
	opts_y+=("CGROUP_CPUACCT")            # Enables CPU accounting in cgroups
	opts_y+=("CGROUP_DEVICE")             # Enables device control in cgroups
	opts_y+=("CGROUP_FREEZER")            # Enables freezer for suspending tasks in cgroups
	opts_y+=("CGROUP_HUGETLB")            # Enables huge page control in cgroups
	opts_y+=("CGROUP_NET_CLASSID")        # Enables network classid control in cgroups
	opts_y+=("CGROUP_NET_PRIO")           # Enables network priority control in cgroups
	opts_y+=("CGROUP_PERF")               # Enables performance counter control in cgroups
	opts_y+=("CGROUP_PIDS")               # Enables process ID control in cgroups
	opts_y+=("CGROUP_SCHED")              # Enables scheduler control in cgroups
	opts_y+=("CGROUPS")                   # Enables general cgroup functionality
	opts_y+=("CPUSETS")                   # Enables CPU set support for cgroups
	opts_m+=("CRYPTO")                    # Enables cryptographic algorithms support as modules
	opts_m+=("CRYPTO_AEAD")               # Enables AEAD (Authenticated Encryption with Associated Data) algorithms support
	opts_m+=("CRYPTO_GCM")                # Enables GCM (Galois/Counter Mode) cipher support
	opts_m+=("CRYPTO_GHASH")              # Enables GHASH algorithm support
	opts_m+=("CRYPTO_SEQIV")              # Enables sequential initialization vector support for cryptographic operations
	opts_y+=("EVENTFD")                   # Enables eventfd system calls for event notification
	opts_y+=("BPF_SYSCALL")               # Enables BPF (Berkeley Packet Filter) system call support
	opts_y+=("CFS_BANDWIDTH")             # Enables bandwidth control for CFS (Completely Fair Scheduler)
	opts_m+=("DUMMY")                     # Enables dummy network driver module
	opts_y+=("DEVPTS_MULTIPLE_INSTANCES") # Enables multiple instances of devpts (pseudo-terminal master/slave pairs)
	opts_y+=("ENCRYPTED_KEYS")            # Enables support for encrypted keys in the kernel
	opts_m+=("IPVLAN")                    # Enables IPvlan network driver support
	opts_y+=("INET")                      # Enables Internet protocol (IPv4) support
	opts_y+=("FAIR_GROUP_SCHED")          # Enables fair group scheduling support
	opts_m+=("INET_ESP")                  # Enables ESP (Encapsulating Security Payload) for IPv4
	opts_y+=("IP_VS_NFCT")                # Enables connection tracking for IPVS (IP Virtual Server)
	opts_y+=("IP_VS_PROTO_TCP")           # Enables TCP protocol support for IPVS
	opts_y+=("IP_VS_PROTO_UDP")           # Enables UDP protocol support for IPVS
	opts_m+=("IP_VS")                     # Enables IPVS (IP Virtual Server) support as a module
	opts_m+=("IP_VS_RR")                  # Enables round-robin scheduling for IPVS
	opts_y+=("KEY_DH_OPERATIONS")         # Enables Diffie-Hellman key exchange operations
	opts_y+=("KEYS")                      # Enables key management framework support
	opts_m+=("MACVLAN")                   # Enables MACVLAN network driver support
	opts_y+=("MEMCG")                     # Enables memory controller for cgroups
	opts_y+=("MEMCG_KMEM")                # Enables memory controller for kmem (kernel memory) cgroups
	opts_m+=("NET_CLS_CGROUP")            # Enables network classification using cgroups
	opts_y+=("NET_CORE")                  # Enables core networking stack support
	opts_y+=("NET_L3_MASTER_DEV")         # Enables master device support for Layer 3 (L3) networking
	opts_y+=("NET_NS")                    # Enables network namespace support
	opts_y+=("NET_SCHED")                 # Enables network scheduler support
	opts_y+=("NETDEVICES")                # Enables support for network devices
	opts_y+=("NAMESPACES")                # Enables support for namespaces (including network namespaces)
	opts_m+=("OVERLAY_FS")                # Enables support for OverlayFS
	opts_y+=("PID_NS")                    # Enables PID (Process ID) namespace support
	opts_y+=("POSIX_MQUEUE")              # Enables POSIX message queues support
	opts_y+=("PROC_PID_CPUSET")           # Enables CPU set control for /proc/{pid}/cpuset
	opts_y+=("PERSISTENT_KEYRINGS")       # Enables persistent keyring support
	opts_m+=("RESOURCE_COUNTERS")         # Enables resource counters support in cgroups
	opts_y+=("RT_GROUP_SCHED")            # Enables real-time group scheduling
	opts_y+=("SECURITY_APPARMOR")         # Enables AppArmor security module support
	opts_y+=("SECCOMP")                   # Enables seccomp (secure computing) support
	opts_y+=("SECCOMP_FILTER")            # Enables seccomp filtering
	opts_y+=("USER_NS")                   # Enables user namespace support
	opts_m+=("VXLAN")                     # Enables VXLAN network driver support
	opts_m+=("VETH")                      # Enables Virtual Ethernet (veth) network driver support
	opts_m+=("VLAN_8021Q")                # Enables 802.1Q VLAN tagging support
	opts_y+=("XFRM")                      # Enables transform (XFRM) framework support
	opts_m+=("XFRM_ALGO")                 # Enables cryptographic algorithm support for XFRM
	opts_m+=("XFRM_USER")                 # Enables user space XFRM framework support
}

# Enables live system access to the kernel configuration via /proc/config.gz.
function armbian_kernel_config__enable_config_access_in_live_system() {
	opts_y+=("IKCONFIG") # This information can be extracted from the kernel image file with the script scripts/extract-ikconfig and used as input to rebuild the current kernel or to build another kernel
	opts_y+=("IKPROC")   # This option enables access to the kernel configuration file through /proc/config.gz
}

function armbian_kernel_config__restore_enable_gpio_sysfs() {
	opts_y+=("GPIO_SYSFS") # This was a victim of not having EXPERT=y due to some _DEBUG conflicts in old times. Re-enable it forcefully.
}

# NTSYNC support for Windows NT synchronization primitives (Wine/Proton performance)
# Available and functional since kernel 6.14 (was marked BROKEN in 6.10-6.13)
# Skip vendor kernels due to their inconsistent upstream merge status
function armbian_kernel_config__enable_ntsync() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.14; then
		if [[ "${BRANCH}" =~ 'vendor' ]]; then
			display_alert "Skipping NTSYNC for vendor kernel" "${BRANCH} branch, ${KERNEL_MAJOR_MINOR} version" "debug"
		else
			display_alert "Enabling NTSYNC support" "for Wine/Proton compatibility" "debug"
			opts_m+=("NTSYNC")
		fi
	fi
}

# +++++++++++ HELPERS CORNER +++++++++++
#
# Helpers for manipulating kernel config.
#
function kernel_config_set_m() {
	declare module="$1"
	display_alert "Enabling kernel module" "${module}=m" "debug"
	run_host_command_logged ./scripts/config --module "${module}"
}

function kernel_config_set_y() {
	declare config="$1"
	display_alert "Enabling kernel config/built-in" "${config}=y" "debug"
	run_host_command_logged ./scripts/config --enable "${config}"
}

function kernel_config_set_n() {
	declare config="$1"
	display_alert "Disabling kernel config/module" "${config}=n" "debug"
	run_host_command_logged ./scripts/config --disable "${config}"

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
	declare opt_y opt_val opt_n opt_m
	for opt_n in "${opts_n[@]}"; do
		kernel_config_modifying_hashes+=("${opt_n}=n")
	done

	for opt_y in "${opts_y[@]}"; do
		kernel_config_modifying_hashes+=("${opt_y}=y")
	done

	for opt_m in "${opts_m[@]}"; do
		kernel_config_modifying_hashes+=("${opt_m}=m")
	done

	for opt_val in "${!opts_val[@]}"; do
		kernel_config_modifying_hashes+=("${opt_val}=${opts_val[$opt_val]}")
	done

	if [[ -f .config ]]; then
		for opt_n in "${opts_n[@]}"; do
			kernel_config_set_n "${opt_n}"
		done

		for opt_y in "${opts_y[@]}"; do
			kernel_config_set_y "${opt_y}"
		done

		for opt_m in "${opts_m[@]}"; do
			kernel_config_set_m "${opt_m}"
		done

		for opt_val in "${!opts_val[@]}"; do
			kernel_config_set_val "${opt_val}" "${opts_val[$opt_val]}"
		done
	fi
}
