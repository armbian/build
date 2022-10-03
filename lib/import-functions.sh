#!/bin/bash

while read -r file; do
	# shellcheck source=/dev/null
	source "$file"
done <<<"$(find "${SRC}/lib/functions" -name "*.sh")"
