function prepare_armbian_mountpoints_description_dict() {
	# array for the generic armbian 'volumes' and their paths.
	# bash dicts do NOT keep their insertion order, instead "hash order", which is a bit better than random for our purposes.
	# keep an array with the correct order, unfortunately
	declare -g -a ARMBIAN_MOUNTPOINTS_ARRAY=(
		".tmp"
		"output" "output/images" "output/debs" "output/logs"
		"cache"
		"cache/git-bare"
		"cache/git-bundles"
		"cache/toolchain"
		"cache/aptcache"
		"cache/rootfs"
		"cache/initrd"
		"cache/sources"
		"cache/sources/linux-kernel-worktree"
		"cache/ccache"
	)

	declare -A -g ARMBIAN_MOUNTPOINTS_DESC_DICT=(
		[".tmp"]="docker_kind_linux=anonymous docker_kind_darwin=anonymous"                             # tmpfs, discard, anonymous; whatever you wanna call  it. It just needs to be 100% local to the container, and there's very little value in being able to look at it from the host.
		["output"]="docker_kind_linux=bind docker_kind_darwin=bind"                                     # catch-all output. specific subdirs are mounted below. it's a bind mount by default on both Linux and Darwin.
		["output/images"]="docker_kind_linux=bind docker_kind_darwin=bind"                              # 99% of users want this as the result of their build, no matter if it's slow or not. bind on both.
		["output/debs"]="docker_kind_linux=bind docker_kind_darwin=bind"                                # generated output .deb files. most people are interested in this, to update kernels or dtbs after initial build. bind on both Linux and Darwin.
		["output/logs"]="docker_kind_linux=bind docker_kind_darwin=bind"                                # log files produced. 100% of users want this. Bind on both Linux and Darwin. Is used to integrate launcher and actual-build logs, so must exist and work otherwise confusion ensues.
		["cache"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                               # catch-all cache, could be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/git-bare"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                      # Git bare repos (kernel/u-boot). On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/git-bundles"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                   # Downloads of git bundles, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/toolchain"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                     # toolchain cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/aptcache"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                      # .deb apt cache, replaces apt-cacher-ng. Can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/rootfs"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                        # rootfs .tar.zst cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/initrd"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                        # initrd.img cache, can be bind-mounted or a volume. On Darwin it's too slow to bind-mount, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/sources"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                       # operating directory. many things are cloned in here, and some are even built inside. needs to be local to the container, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/sources/linux-kernel-worktree"]="docker_kind_linux=bind docker_kind_darwin=namedvolume" # working tree for kernel builds. huge. contains both sources and the built object files. needs to be local to the container, so it's a volume by default. On Linux, it's a bind-mount by default.
		["cache/ccache"]="docker_kind_linux=bind docker_kind_darwin=namedvolume"                        # ccache object store. limited to 5gb by default. needs to be local to the container, so it's a volume by default. On Linux, it's a bind-mount by default.
	)

	# These, if found, will be removed on `dockerpurge` and other cleanups.
	# They "used to be" used by the build system, but no longer.
	declare -g -a ARMBIAN_MOUNTPOINTS_DEPRECATED=(
		"cache/gitballs"
		"cache/sources/kernel"
		"cache/sources/linux-kernel"
	)
}

function loop_over_armbian_mountpoints() {
	prepare_armbian_mountpoints_description_dict
	# loop over all mountpoints and call the function passed as first argument
	: "${1:?loop_over_mountpoints needs a function as first argument}"
	local func="$1"
	shift
	local mountpoint
	for mountpoint in "${ARMBIAN_MOUNTPOINTS_ARRAY[@]}"; do
		# call func passing the key and the values as arguments
		local values="${ARMBIAN_MOUNTPOINTS_DESC_DICT[$mountpoint]}"
		eval "$values"

		# This is contrived. Would be easier to just eval (and use Linux/Darwin instead of linux/darwin)
		declare docker_kind="unknown"
		case "${DOCKER_ARMBIAN_HOST_OS_UNAME}" in
			Linux)
				# shellcheck disable=SC2154 # defined during loop_over_armbian_mountpoints
				docker_kind="${docker_kind_linux}"
				;;

			Darwin)
				# shellcheck disable=SC2154 # defined during loop_over_armbian_mountpoints
				docker_kind="${docker_kind_darwin}"
				;;
			*)
				display_alert "Unsupported host OS" "${DOCKER_ARMBIAN_HOST_OS_UNAME} - cant map mountpoint to Docker volume" "warn"
				;;
		esac

		# volume_id is the mountpoint with all slashes replaced with dashes
		local volume_id="${mountpoint//\//-}"

		# shellcheck disable=SC2086
		eval "$values docker_kind=$docker_kind $func '$mountpoint'"
	done
}
