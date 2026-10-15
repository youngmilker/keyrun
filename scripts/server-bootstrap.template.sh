#!/bin/bash
# Generated standalone entry. Regenerate before publishing matching project files.
set -e
KR_BOOT_BASE=__KEYRUN_HTTP_BASE_LITERAL__
KR_BOOT_TIMEOUT=__KEYRUN_TIMEOUT_SECONDS__
for KR_BOOT_DEP in curl jq; do
    command -v "$KR_BOOT_DEP" >/dev/null 2>&1 || { printf 'Missing dependency: %s\n' "$KR_BOOT_DEP" >&2; exit 1; }
done
case "$(uname -s)" in Darwin|Linux) ;; *) printf 'Only macOS/Linux are supported.\n' >&2; exit 1;; esac
if command -v shasum >/dev/null 2>&1; then
    kr_boot_hash() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
    kr_boot_hash() { sha256sum "$1" | awk '{print $1}'; }
else printf 'Missing shasum or sha256sum.\n' >&2; exit 1; fi
KR_BOOT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keyrun-http.XXXXXX")
trap 'rm -rf "$KR_BOOT_DIR"' EXIT
# Fetch and verify every code file before invoking any downloaded code.
while IFS='|' read -r KR_BOOT_REL KR_BOOT_HASH; do
    mkdir -p "$KR_BOOT_DIR/$(dirname "$KR_BOOT_REL")"
    KR_BOOT_STATUS=$(curl --silent --show-error --globoff --proto '=http,https' \
        --connect-timeout "$KR_BOOT_TIMEOUT" --max-time "$KR_BOOT_TIMEOUT" \
        --output "$KR_BOOT_DIR/$KR_BOOT_REL" --write-out '%{http_code}' "$KR_BOOT_BASE/$KR_BOOT_REL")
    case "$KR_BOOT_STATUS" in 2[0-9][0-9]) ;; *) printf 'HTTP %s: %s\n' "$KR_BOOT_STATUS" "$KR_BOOT_REL" >&2; exit 1;; esac
    [ "$(kr_boot_hash "$KR_BOOT_DIR/$KR_BOOT_REL")" = "$KR_BOOT_HASH" ] || {
        printf 'SHA-256 mismatch: %s. Regenerate and publish matching files.\n' "$KR_BOOT_REL" >&2; exit 1;
    }
done <<'KEYRUN_CODE_HASHES'
__KEYRUN_HASH_LINES__
KEYRUN_CODE_HASHES
jq -n --arg base "$KR_BOOT_BASE" --argjson timeout "$KR_BOOT_TIMEOUT" \
    '{mode:"http",localRoot:".",httpBase:$base,timeoutSeconds:$timeout}' > "$KR_BOOT_DIR/source-config.json"
printf 'Server source: %s\n' "$KR_BOOT_BASE"
bash "$KR_BOOT_DIR/keyrun.sh" --install "$@"
