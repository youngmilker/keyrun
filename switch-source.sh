#!/bin/bash
set -e
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resource-loader.sh"
source "$KR_PROJECT_ROOT/scripts/build-server-bootstrap.sh"

main() {
    local mode='' base='' root='' timeout='' set_base=false set_root=false set_timeout=false open_page=false temp
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode|--http-base|--local-root|--timeout-seconds)
                [ $# -ge 2 ] && [ -n "$2" ] || { kr_error "Missing value: $1"; return 1; }
                case "$1" in
                    --mode) mode="$2";;
                    --http-base) base="$2"; set_base=true;;
                    --local-root) root="$2"; set_root=true;;
                    --timeout-seconds) timeout="$2"; set_timeout=true;;
                esac
                shift 2;;
            --open-page) open_page=true; shift;;
            *) kr_error "Unknown source option: $1"; return 1;;
        esac
    done
    case "$mode" in local|http) ;; *) kr_error '--mode must be local or http.'; return 1;; esac
    kr_require jq
    [ -f "$KR_CONFIG_PATH" ] && [ ! -L "$KR_CONFIG_PATH" ] || { kr_error 'Missing or linked source configuration.'; return 1; }
    if "$set_base"; then base=$(kr_http_base "$base") || return 1; fi
    if "$set_timeout"; then
        [[ "$timeout" =~ ^[1-9][0-9]{0,2}$ && "$timeout" -le 300 ]] || { kr_error 'timeoutSeconds must be 1–300.'; return 1; }
    else timeout=20; fi
    temp=$(mktemp -d "$KR_PROJECT_ROOT/.keyrun-switch.XXXXXX")
    KR_SWITCH_TEMP="$temp"
    trap 'rm -rf "$KR_SWITCH_TEMP"' EXIT
    cp -p "$KR_CONFIG_PATH" "$temp/config.json"
    jq --arg mode "$mode" --arg base "$base" --arg root "$root" --argjson timeout "$timeout" \
        --argjson setBase "$set_base" --argjson setRoot "$set_root" --argjson setTimeout "$set_timeout" \
        'if type != "object" then error("Config must be an object") else . end
          | .mode=$mode | .localRoot //= "."
          | if $setBase then .httpBase=$base else . end
          | if $setRoot then .localRoot=$root else . end
          | if $setTimeout then .timeoutSeconds=$timeout else . end' "$KR_CONFIG_PATH" > "$temp/config.json"
    kr_load_config "$temp/config.json"
    if [ "$mode" = http ]; then
        kr_build_unix_bootstrap "$KR_HTTP_BASE" "$KR_TIMEOUT" "$temp/sh"
        [ ! -L "$KR_PROJECT_ROOT/sh" ] || { kr_error 'Linked bootstrap output rejected.'; return 1; }
        mv -f "$temp/sh" "$KR_PROJECT_ROOT/sh"
    fi
    mv -f "$temp/config.json" "$KR_CONFIG_PATH"
    printf 'Mode: %s\nLocal root: %s\nHTTP base: %s\n' "$KR_MODE" "$KR_LOCAL_ROOT" "$KR_HTTP_BASE"
    if [ "$mode" = http ]; then printf 'Windows 发布者还需运行 switch-source.ps1，更新匹配的 Windows ps1 引导。\n'; fi
    if "$open_page"; then kr_open_page; fi
}
main "$@"
