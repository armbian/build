# Suppress "perl: warning: Setting locale failed." on minimal images.
# Only ensure LANG has a fallback value - do NOT set LC_ALL here because
# it overrides every individual LC_* category and breaks update-locale.

if [ -z "$LANG" ]; then
	export LANG="C.UTF-8"
fi
