# Helper function, to get clean "stack traces" that do not include the hook/extension infrastructure code.
function get_extension_hook_stracktrace() {
	local sources_str="$1" # Give this ${BASH_SOURCE[*]} - expanded
	local lines_str="$2"   # And this # Give this ${BASH_LINENO[*]} - expanded
	local sources lines index final_stack=""
	IFS=' ' read -r -a sources <<< "${sources_str}"
	IFS=' ' read -r -a lines <<< "${lines_str}"
	for index in "${!sources[@]}"; do
		local source="${sources[index]}" line="${lines[((index - 1))]}"
		# skip extension infrastructure sources, these only pollute the trace and add no insight to users
		[[ ${source} == */extension_function_definition.sh ]] && continue
		[[ ${source} == *lib/extensions.sh ]] && continue
		[[ ${source} == *lib/functions/logging.sh ]] && continue
		[[ ${source} == */compile.sh ]] && continue
		[[ ${line} -lt 1 ]] && continue
		# relativize the source, otherwise too long to display
		source="${source#"${SRC}/"}"
		# remove 'lib/'. hope this is not too confusing.
		source="${source#"lib/functions/"}"
		source="${source#"lib/"}"
		# add to the list
		# shellcheck disable=SC2015 # i know. thanks. I won't write an if here
		arrow="$([[ "$final_stack" != "" ]] && echo "-> " || true)"
		final_stack="${source}:${line} ${arrow} ${final_stack} "
	done
	# output the result, no newline
	# shellcheck disable=SC2086 # I wanna suppress double spacing, thanks
	echo -n $final_stack
}

function show_caller_full() {
	{
		local i=1 # skip the first frame
		local line_no
		local function_name
		local file_name
		while caller $i; do
			((i++))
		done | while read -r line_no function_name file_name; do
			local padded_function_name=$(printf "%30s" "$function_name")
			local short_file_name="${file_name/"${SRC}/"/"./"}"
			echo -e "$padded_function_name --> $short_file_name:$line_no"
		done
	} || true # always success
}
