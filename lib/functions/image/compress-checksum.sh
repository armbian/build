#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function output_images_compress_and_checksum() {
	[[ -n $SEND_TO_SERVER ]] && return 0

	# check that 'version' is set
	[[ -z $version ]] && exit_with_error "version is not set"
	# compression_type: declared in outer scope

	declare prefix_images="${1}"
	# find all files that match prefix_images
	declare -a images=("${prefix_images}"*)
	# if no files match prefix_images, exit
	if [[ ${#images[@]} -eq 0 ]]; then
		display_alert "No files to compress and checksum" "no images will be compressed" "wrn"
		return 0
	fi

	# Maximize CPU + RAM use. Threads = full nproc (kernel time-slices when
	# peer xz/zstd jobs contend; when they idle, we get the cores). Memory
	# *is* fair-shared among peers, with a 60% safety margin, so the level
	# selection below picks the strongest preset that fits without OOMing
	# even if every peer also reaches for its top level at the same instant.
	declare host_threads active_jobs compress_threads mem_avail_mb mem_budget_mb
	host_threads=$(nproc)
	compress_threads=$host_threads
	active_jobs=$(pgrep -cx 'xz|zstd|zstdmt' 2>/dev/null || true)
	[[ -z "${active_jobs}" ]] && active_jobs=0

	mem_avail_mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)
	mem_budget_mb=$(( mem_avail_mb * 6 / 10 / (active_jobs + 1) ))

	# Pick the strongest xz preset that fits BOTH memory and CPU class. Each
	# entry is "level:per-thread-MB:min-threads" — the min-threads floor
	# protects weak ARM hosts (2-4 cores) where higher levels would be
	# CPU-bound and slower than the old static -1 default. Memory check uses
	# compress_threads * per_thread_MB <= budget. Per-thread mem from xz
	# manpage; thread floors picked from typical compress-MB/s/thread:
	#   -9 needs ~8 threads to keep wall time tolerable
	#   -6 needs ~4 threads
	#   -3 needs ~2 threads
	declare xz_elastic_level="1"
	for entry in 9:674:8 6:94:4 3:32:2 1:9:1; do
		lvl="${entry%%:*}"
		rest="${entry#*:}"
		pt="${rest%%:*}"
		floor="${rest##*:}"
		if (( compress_threads >= floor )) && (( compress_threads * pt <= mem_budget_mb )); then
			xz_elastic_level="$lvl"
			break
		fi
	done

	# zstd: tier by threads + memory. Old static default was -9; the new
	# elastic walk only escalates above that when both CPU and RAM clearly
	# support it. Keeps weak ARM hosts (2-4 cores) at a sensible level.
	declare zstd_elastic_level="9"
	(( compress_threads >= 4 )) && zstd_elastic_level="12"
	(( compress_threads >= 8 && mem_budget_mb >= 2048 )) && zstd_elastic_level="19"
	(( compress_threads >= 16 && mem_budget_mb >= 4096 )) && zstd_elastic_level="22"

	# Trace each xz preset considered against the budget AND the cpu floor;
	# useful when the picked level looks surprising in a build log.
	declare xz_walk_trace=""
	for entry in 9:674:8 6:94:4 3:32:2 1:9:1; do
		lvl="${entry%%:*}"
		rest="${entry#*:}"
		pt="${rest%%:*}"
		floor="${rest##*:}"
		need=$(( compress_threads * pt ))
		if (( compress_threads < floor )); then
			xz_walk_trace+="-${lvl}:cpu<${floor} skip; "
			continue
		fi
		if (( need <= mem_budget_mb )); then
			xz_walk_trace+="-${lvl}:${need}MB<=budget OK; "
			break
		else
			xz_walk_trace+="-${lvl}:${need}MB>budget skip; "
		fi
	done

	declare mem_total_mb loadavg total_input_mb=0 input_count=0
	mem_total_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
	loadavg=$(awk '{print $1"/"$2"/"$3}' /proc/loadavg)
	for f in "${images[@]}"; do
		[[ -L "$f" || ! -f "$f" || "$f" == *.txt ]] && continue
		total_input_mb=$(( total_input_mb + $(stat -c %s "$f") / 1024 / 1024 ))
		input_count=$(( input_count + 1 ))
	done

	display_alert "Compression host" \
		"nproc=${host_threads} loadavg=${loadavg} MemTotal=${mem_total_mb}MB MemAvail=${mem_avail_mb}MB" \
		"info"
	display_alert "Compression resource share" \
		"active_xz/zstd=${active_jobs} -> threads=${compress_threads}, budget=${mem_budget_mb}MB; pick xz=-${xz_elastic_level} zstd=-${zstd_elastic_level}" \
		"info"
	display_alert "Compression xz level walk" "${xz_walk_trace%; }" "info"
	display_alert "Compression input" "${input_count} file(s), ${total_input_mb}MB total" "info"

	# loop over images
	for uncompressed_file in "${images[@]}"; do
		# if image is a symlink, skip it
		[[ -L "${uncompressed_file}" ]] && continue
		# if image is not a file, skip it
		[[ ! -f "${uncompressed_file}" ]] && continue
		# if filename ends in .txt, skip it
		[[ "${uncompressed_file}" == *.txt ]] && continue

		# get just the filename, sans path
		declare uncompressed_file_basename
		uncompressed_file_basename=$(basename "${uncompressed_file}")
		# Stable release builds (BETA=no) deploy to own infra (no size cap) and
		# favour speed: force xz -0. Nightly/user builds publish to GitHub releases
		# (2 GB asset cap) and use the elastic level to compress as much as the
		# per-job memory budget allows.
		declare xz_default_ratio="${xz_elastic_level}"
		[[ "${BETA}" == "no" ]] && xz_default_ratio="0"
		declare xz_compression_ratio_image="${IMAGE_XZ_COMPRESSION_RATIO:-${xz_default_ratio}}"
		declare zstd_level="${ZSTD_COMPRESSION_LEVEL:-${zstd_elastic_level}}"

		# File-size-aware thread cap: xz multithreads on blocks of ~3x dict size,
		# so threads beyond (file_size / block_size) sit idle and waste per-thread
		# memory. Cap to whatever the file can actually use.
		declare file_size_mb file_threads xz_block_mb xz_per_thread_mb peak_mem_mb
		file_size_mb=$(( $(stat -c %s "${uncompressed_file}") / 1024 / 1024 ))
		case "${xz_compression_ratio_image}" in
			9|9e) xz_block_mb=192; xz_per_thread_mb=674 ;;
			7|8)  xz_block_mb=48;  xz_per_thread_mb=186 ;;
			6)    xz_block_mb=24;  xz_per_thread_mb=94 ;;
			3|4|5) xz_block_mb=12; xz_per_thread_mb=32 ;;
			0)    xz_block_mb=3;   xz_per_thread_mb=2 ;;
			*)    xz_block_mb=3;   xz_per_thread_mb=9 ;;
		esac
		file_threads=$(( file_size_mb / xz_block_mb ))
		(( file_threads < 1 )) && file_threads=1
		(( file_threads > compress_threads )) && file_threads=$compress_threads
		peak_mem_mb=$(( file_threads * xz_per_thread_mb ))

		declare t_start t_elapsed compressed_mb ratio_pct mb_per_sec
		t_start=$SECONDS

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing with xz" "${uncompressed_file_basename}.xz (-${xz_compression_ratio_image}, threads: ${file_threads}/${compress_threads}, size: ${file_size_mb}MB, block: ${xz_block_mb}MB, peak: ~${peak_mem_mb}MB)" "info"
			xz -T "${file_threads}" "-${xz_compression_ratio_image}" "${uncompressed_file}" # "If xz is provided with input but no output, it will delete the input"
			compression_type=".xz"
		elif [[ $COMPRESS_OUTPUTIMAGE == *zst* ]]; then
			# zstd auto-scales workers to input size, so no explicit cap needed here.
			# --long=27 forces a 128 MB matching window. Only worth it at -19+
			# where the ratio win justifies the 128 MB decoder memory cost; at
			# lower levels zstd's default windowLog (~4-16 MB) decompresses
			# much cheaper on small devices.
			declare -a zstd_args=(-T"${compress_threads}")
			(( zstd_level >= 19 )) && zstd_args+=(--long=27)
			(( zstd_level >= 20 )) && zstd_args+=(--ultra)
			display_alert "Compressing with zstd" "${uncompressed_file_basename}.zst (-${zstd_level}, threads: ${compress_threads}, size: ${file_size_mb}MB)" "info"
			zstdmt "${zstd_args[@]}" "-${zstd_level}" "${uncompressed_file}" -o "${uncompressed_file}.zst"
			rm -f "${uncompressed_file}"
			compression_type=".zst"
		fi

		t_elapsed=$(( SECONDS - t_start ))
		(( t_elapsed < 1 )) && t_elapsed=1
		compressed_mb=$(( $(stat -c %s "${uncompressed_file}${compression_type}" 2>/dev/null || echo 0) / 1024 / 1024 ))
		(( file_size_mb > 0 )) && ratio_pct=$(( compressed_mb * 100 / file_size_mb )) || ratio_pct=0
		mb_per_sec=$(( file_size_mb / t_elapsed ))
		display_alert "Compressed" "${uncompressed_file_basename}${compression_type}: ${file_size_mb}MB -> ${compressed_mb}MB (${ratio_pct}%), ${t_elapsed}s, ${mb_per_sec} MB/s" "info"

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			display_alert "SHA256 calculating" "${uncompressed_file_basename}${compression_type}" "info"
			# awk manipulation is needed to get rid of temporal folder path from SHA signature
			sha256sum -b "${uncompressed_file}${compression_type}" | awk '{split($2, a, "/"); print $1, a[length(a)]}' > "${uncompressed_file}${compression_type}".sha
		fi

	done

}
