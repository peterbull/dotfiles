#!/usr/bin/env bash
set -euo pipefail

for a in "$@"; do
	case "$a" in
	--user-data-dir=*) dir_arg="$a" ;;
	esac
done

if [[ -n "${dir_arg:-}" ]]; then
	pgrep -f "Google Chrome.*${dir_arg}" | xargs -r kill 2>/dev/null || true
	for _ in $(seq 1 20); do
		pgrep -f "Google Chrome.*${dir_arg}" >/dev/null 2>&1 || break
		sleep 0.25
	done
fi

exec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "$@"
