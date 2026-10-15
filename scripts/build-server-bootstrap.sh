#!/bin/bash
set -e
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/resource-loader.sh"

kr_build_unix_bootstrap() {
    local base="$1" timeout="$2" output="${3:-$KR_PROJECT_ROOT/sh}" relative hash lines='' literal temp
    base=$(kr_http_base "$base") || return 1
    [[ "$timeout" =~ ^[1-9][0-9]{0,2}$ && "$timeout" -le 300 ]] || { kr_error 'Invalid timeout.'; return 1; }
    for relative in resource-loader.sh keyrun.sh scripts/platform-paths.sh scripts/install.sh scripts/install-unix.sh scripts/diagnose-idea-paths.sh; do
        [ -f "$KR_PROJECT_ROOT/$relative" ] && [ ! -L "$KR_PROJECT_ROOT/$relative" ] || { kr_error "Missing local code: $relative"; return 1; }
        bash -n "$KR_PROJECT_ROOT/$relative" || return 1
        hash=$(kr_sha256 "$KR_PROJECT_ROOT/$relative") || return 1
        lines="${lines}${relative}|${hash}"$'\n'
    done
    literal=$(printf '%s' "$base" | jq -Rrs '@sh') || return 1
    [ ! -L "$output" ] || { kr_error 'Linked bootstrap output rejected.'; return 1; }
    temp=$(mktemp "${output%/*}/.keyrun-bootstrap.XXXXXX") || return 1
    if [ -f "$output" ]; then
        if ! cp -p "$output" "$temp"; then rm -f "$temp"; return 1; fi
    else chmod 644 "$temp" || { rm -f "$temp"; return 1; }; fi
    if ! jq -jrn --rawfile template "$KR_PROJECT_ROOT/scripts/server-bootstrap.template.sh" \
        --arg base "$literal" --arg timeout "$timeout" --arg hashes "${lines%$'\n'}" \
        '$template | split("__KEYRUN_HTTP_BASE_LITERAL__") | join($base)
          | split("__KEYRUN_TIMEOUT_SECONDS__") | join($timeout)
          | split("__KEYRUN_HASH_LINES__") | join($hashes)' > "$temp"; then rm -f "$temp"; return 1; fi
    if ! bash -n "$temp"; then rm -f "$temp"; return 1; fi
    mv -f "$temp" "$output"
    printf 'Shell server bootstrap generated: %s\n' "$base"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    kr_require jq
    [ $# -ge 1 ] || { kr_error 'Usage: bash scripts/build-server-bootstrap.sh URL [timeout]'; exit 1; }
    kr_build_unix_bootstrap "$1" "${2:-20}"
fi
