#!/bin/bash

while read -r file; do
    echo $LOL
	# shellcheck source=/dev/null
	source "$file"
done <<< "$(find "${SRC}/lib/functions" -name "*.sh")"
