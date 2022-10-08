## Hooks
function extension_metadata_ready__499_display_docs_generation_start_info() {
	display_alert "Generating hook documentation and sample extension"
}

function extension_metadata_ready__docs_markdown() {
	generate_markdown_docs_to_stdout > "${EXTENSION_MANAGER_TMP_DIR}/hooks.auto.docs.md"
}

function extension_metadata_ready__docs_sample_extension() {
	mkdir -p "${SRC}/userpatches/extensions"
	generate_sample_extension_to_stdout > "${SRC}/userpatches/extensions/sample-extension.sh"
}

## Internal functions

### Common stuff
function read_common_data() {
	export HOOK_POINT_CALLS_COUNT=$(wc -l < "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt")
	export HOOK_POINT_CALLS_UNIQUE_COUNT=$(sort < "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt" | uniq | wc -l)
	export HOOK_POINTS_WITH_MULTIPLE_CALLS=""

	# Read the hook_points (main, official names) from the hook point ordering file.
	export ALL_HOOK_POINT_CALLS=$(xargs echo -n < "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt")
}

function loop_over_hook_points_and_call() {
	local callback="$1"
	HOOK_POINT_COUNTER=0
	for one_hook_point in ${ALL_HOOK_POINT_CALLS}; do
		export HOOK_POINT_COUNTER=$((HOOK_POINT_COUNTER + 1))
		export HOOK_POINT="${one_hook_point}"
		export MARKDOWN_HEAD="$(head -1 "${EXTENSION_MANAGER_TMP_DIR}/${one_hook_point}.orig.md")"
		export MARKDOWN_BODY="$(tail -n +2 "${EXTENSION_MANAGER_TMP_DIR}/${one_hook_point}.orig.md")"
		export COMPATIBILITY_NAMES="$(xargs echo -n < "${EXTENSION_MANAGER_TMP_DIR}/${one_hook_point}.compat")"
		${callback}
	done
}

## Markdown stuff
function generate_markdown_docs_to_stdout() {
	read_common_data
	cat << MASTER_HEADER
# Armbian build system extensibility documentation
- This documentation is auto-generated.
MASTER_HEADER

	[[ $HOOK_POINT_CALLS_COUNT -gt $HOOK_POINT_CALLS_UNIQUE_COUNT ]] && {
		# Some hook points were called multiple times, determine which.
		HOOK_POINTS_WITH_MULTIPLE_CALLS=$(comm -13 <(sort < "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt" | uniq) <(sort < "${EXTENSION_MANAGER_TMP_DIR}/hook_point_calls.txt") | sort | uniq | xargs echo -n)

		cat << MULTIPLE_CALLS_WARNING
- *Important:* The following hook points where called multiple times during the documentation generation. This can be indicative of a bug in the build system. Please check the sources for the invocation of the following hooks: \`${HOOK_POINTS_WITH_MULTIPLE_CALLS}\`.
MULTIPLE_CALLS_WARNING

	}

	cat << PRE_HOOKS_HEADER
## Hooks
- Hooks are listed in the order they are called.
PRE_HOOKS_HEADER

	loop_over_hook_points_and_call "generate_markdown_one_hook_point_to_stdout"

	cat << MASTER_FOOTER
------------------------------------------------------------------------------------------
MASTER_FOOTER

}

function generate_markdown_one_hook_point_to_stdout() {
	# Hook name in 3rd level title, first line of description in a blockquote.
	# The rest in a normal block.
	cat << HOOK_DOCS
### \`${one_hook_point}\`
> ${MARKDOWN_HEAD}

${MARKDOWN_BODY}

HOOK_DOCS

	[[ "${COMPATIBILITY_NAMES}" != "" ]] && {
		echo -e "\n\nAlso known as (for backwards compatibility only):"
		for old_name in ${COMPATIBILITY_NAMES}; do
			echo "- \`${old_name}\`"
		done
	}

	echo ""
}

## Bash sample extension stuff
generate_sample_extension_to_stdout() {
	read_common_data
	cat << HEADER
# Sample Armbian build system extension with all extension methods.
# This file is auto-generated from and by the build system itself.
# Please, always use the latest version of this file as a starting point for your own extensions.
# Generation date: $(date)
# Read more about the build system at https://docs.armbian.com/Developer-Guide_Build-Preparation/

HEADER

	loop_over_hook_points_and_call "generate_bash_sample_for_hook_point"
}

generate_bash_sample_for_hook_point() {
	# Include the markdown documentation as a comment.
	# Right now clean it up naively (remove backticks, mostly) but we could pipe through stuff to get better plaintext. (pandoc is a 155mb binary FYI)
	local COMMENT_HEAD="#### $(echo "${MARKDOWN_HEAD}" | tr '`' '"')"
	# shellcheck disable=SC2001
	local COMMENT_BODY="$(echo "${MARKDOWN_BODY}" | tr '`' '"' | sed -e 's/^/###  /')"

	cat << SAMPLE_BASH_CODE
${COMMENT_HEAD}
${COMMENT_BODY}
function ${HOOK_POINT}__be_more_awesome() {
	# @TODO: Please rename this function to reflect what it does, but preserve the "${HOOK_POINT}__" prefix.
	display_alert "Being awesome at \${HOOK_POINT}" "\${EXTENSION}" "info"
}

SAMPLE_BASH_CODE
}
