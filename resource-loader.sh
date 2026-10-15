#!/bin/bash
# Bash 3.2 compatible. Source this local module; jq is the JSON parser.
KR_PROJECT_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd) || return 1
KR_CONFIG_PATH="$KR_PROJECT_ROOT/source-config.json"

kr_error() { printf 'KeyRun: %s\n' "$*" >&2; return 1; }
kr_require() { command -v "$1" >/dev/null 2>&1 || kr_error "缺少依赖 / Missing dependency: $1"; }

kr_http_base() {
    local base="$1" authority host port
    [[ "$base" =~ ^https?://[^/]+ ]] || { kr_error 'Invalid httpBase: expected HTTP/HTTPS URL.'; return 1; }
    if ! printf '%s' "$base" | jq -Rse 'test("[\\x00-\\x20\\x7f\\\\?#]") | not' >/dev/null; then
        kr_error 'Invalid httpBase: no whitespace, credentials, query or fragment allowed.'; return 1
    fi
    authority=${base#*://}; authority=${authority%%/*}
    if [[ "$authority" =~ ^\[[0-9a-fA-F:]+\](:[0-9]+)?$ ]]; then
        host=${authority%%]*}]
    elif [[ "$authority" =~ ^[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; then
        host=${authority%%:*}
    else
        kr_error 'Invalid httpBase authority.'; return 1
    fi
    port=${authority#"$host"}
    if [ -n "$port" ]; then
        port=${port#:}
        [ ${#port} -le 5 ] || { kr_error 'Invalid HTTP port.'; return 1; }
        port=$((10#$port))
        [[ "$port" -ge 1 && "$port" -le 65535 ]] || { kr_error 'Invalid HTTP port.'; return 1; }
    fi
    case "${base#*://}" in *'://'* ) kr_error 'Invalid nested URL.'; return 1;; esac
    while [ "${base%/}" != "$base" ]; do base=${base%/}; done
    printf '%s\n' "$base"
}

kr_load_config() {
    kr_require jq || return 1
    local config="${1:-$KR_CONFIG_PATH}" root
    [ -f "$config" ] && [ ! -L "$config" ] || { kr_error "Configuration missing or linked: $config"; return 1; }
    jq -e 'type == "object" and (.mode == "local" or .mode == "http")
        and ((.localRoot == null) or (.localRoot | type == "string"))
        and ((.httpBase == null) or (.httpBase | type == "string"))
        and ((has("timeoutSeconds") | not) or
          (.timeoutSeconds | type == "number" and . >= 1 and . <= 300 and floor == .))' "$config" >/dev/null || {
        kr_error 'Invalid source configuration.'; return 1;
    }
    KR_MODE=$(jq -r '.mode' "$config") || return 1
    root=$(jq -r '.localRoot // "." | if . == "" then "." else . end' "$config") || return 1
    case "$root" in /*) ;; *) root="$KR_PROJECT_ROOT/$root";; esac
    KR_LOCAL_ROOT="$root"
    KR_HTTP_BASE=$(jq -r '.httpBase // ""' "$config") || return 1
    KR_TIMEOUT=$(jq -r '.timeoutSeconds // 20' "$config") || return 1
    if [ "$KR_MODE" = local ]; then
        [ -d "$root" ] && [ ! -L "$root" ] || { kr_error "Local directory missing or linked: $root"; return 1; }
        # Canonicalize system aliases such as macOS /tmp, then reject links inside this root.
        KR_LOCAL_ROOT=$(cd -P "$root" && pwd) || return 1
    else
        KR_HTTP_BASE=$(kr_http_base "$KR_HTTP_BASE") || return 1
        kr_require curl || return 1
    fi
}

kr_validate_resource() {
    local relative="$1" part remaining
    [ -n "$relative" ] || { kr_error 'Empty resource path.'; return 1; }
    printf '%s' "$relative" | jq -Rse 'test("[<>:\"|?*#\\\\\\x00-\\x1f\\x7f]") | not' >/dev/null || {
        kr_error "Invalid resource path: $relative"; return 1;
    }
    case "$relative" in /*|*/|*'//'*) kr_error "Invalid relative resource path: $relative"; return 1;; esac
    remaining="$relative"
    while :; do
        part=${remaining%%/*}
        case "$part" in ''|.|..|*' '|*.) kr_error "Invalid resource path segment: $part"; return 1;; esac
        [ "$remaining" != "$part" ] || break
        remaining=${remaining#*/}
    done
}

kr_resource_location() {
    local relative="$1" candidate part remaining encoded
    kr_validate_resource "$relative" || return 1
    if [ "$KR_MODE" = http ]; then
        encoded=$(printf '%s' "$relative" | jq -Rrs 'split("/") | map(@uri) | join("/")') || return 1
        printf '%s/%s\n' "$KR_HTTP_BASE" "$encoded"
        return
    fi
    candidate="$KR_LOCAL_ROOT"; remaining="$relative"
    while :; do
        part=${remaining%%/*}; candidate="$candidate/$part"
        [ ! -L "$candidate" ] || { kr_error "Linked resource rejected: $candidate"; return 1; }
        [ -e "$candidate" ] || { kr_error "Local resource not found: $relative"; return 1; }
        [ "$remaining" != "$part" ] || break
        [ -d "$candidate" ] || { kr_error "Not a resource directory: $candidate"; return 1; }
        remaining=${remaining#*/}
    done
    [ -f "$candidate" ] || { kr_error "Resource is not a file: $candidate"; return 1; }
    printf '%s\n' "$candidate"
}

# destination is a caller-owned staging file; no partial HTTP bytes reach stdout.
kr_fetch_resource() {
    local relative="$1" destination="$2" location status
    location=$(kr_resource_location "$relative") || return 1
    if [ "$KR_MODE" = local ]; then
        cat "$location" > "$destination" || return 1
    else
        status=$(curl --silent --show-error --globoff --proto '=http,https' \
            --connect-timeout "$KR_TIMEOUT" --max-time "$KR_TIMEOUT" \
            --output "$destination" --write-out '%{http_code}' "$location") || {
            kr_error "HTTP resource read failed: $relative"; return 1;
        }
        case "$status" in 2[0-9][0-9]) ;; *) kr_error "HTTP $status: $relative (redirects are not followed)"; return 1;; esac
    fi
}

kr_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else kr_error 'Missing shasum or sha256sum.'; fi
}

kr_open_page() {
    local location
    location=$(kr_resource_location index.html) || return 1
    case "$(uname -s)" in
        Darwin) kr_require open && open "$location";;
        Linux) kr_require xdg-open && xdg-open "$location";;
        *) kr_error 'Unsupported operating system.';;
    esac
}
