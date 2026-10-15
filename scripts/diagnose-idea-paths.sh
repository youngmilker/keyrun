#!/bin/bash
set -e
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/resource-loader.sh"
source "$KR_PROJECT_ROOT/scripts/platform-paths.sh"

kr_diagnose_main() {
    local explicit='' file home bin product variable value path key failed=0 index=0 candidate existing duplicate
    local candidates=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --properties-path) [ $# -ge 2 ] || return 1; explicit="$2"; shift 2;;
            *) kr_error "Unknown diagnostic option: $1"; return 1;;
        esac
    done
    kr_require jq || return 1
    kr_platform_paths || return 1
    if [ -n "$explicit" ]; then
        file=$(kr_properties_file "$explicit") || { kr_error "idea.properties not found: $explicit"; return 1; }
        candidates+=("$file")
    else
        kr_discover_installations || return 1
        for file in "$KR_CONFIG_ROOT"/*/idea.properties; do [ ! -f "$file" ] || candidates+=("$file"); done
        for home in "${KR_INSTALLATIONS[@]}"; do
            bin=$(kr_ide_bin "$home") || continue
            [ ! -f "$bin/idea.properties" ] || candidates+=("$bin/idea.properties")
        done
        for product in "${KR_PRODUCTS[@]}"; do
            variable=$(printf '%s_PROPERTIES' "$product" | tr '[:lower:]' '[:upper:]')
            value=${!variable}
            if [ -n "$value" ]; then
                file=$(kr_properties_file "$value") || { printf '无法读取 %s: %s\n' "$variable" "$value" >&2; failed=$((failed + 1)); continue; }
                candidates+=("$file")
            fi
        done
    fi
    local unique=()
    for candidate in "${candidates[@]}"; do
        duplicate=false
        for existing in "${unique[@]}"; do [ "$existing" != "$candidate" ] || duplicate=true; done
        if ! "$duplicate"; then unique+=("$candidate"); fi
    done
    [ ${#unique[@]} -gt 0 ] || { kr_error '未找到 idea.properties；请用 --properties-path 指定文件或安装目录。'; return 1; }
    for file in "${unique[@]}"; do
        index=$((index + 1)); printf '\n[%s/%s] %s\n' "$index" "${#unique[@]}" "$file"
        for key in idea.config.path idea.system.path idea.plugins.path idea.log.path; do
            value=$(kr_property "$file" "$key") || { failed=$((failed + 1)); continue; }
            if [ -z "$value" ]; then printf '%s: 未设置，使用 IDE 默认目录。\n' "$key"; continue; fi
            path=$(kr_expand_path "$value" "${file%/*}") || { failed=$((failed + 1)); continue; }
            if [ -e "$path" ]; then printf '%s: %s (存在)\n' "$key" "$path"
            else printf '%s: %s (不存在)\n' "$key" "$path"; fi
        done
        local config_path system_path
        config_path=$(kr_property "$file" idea.config.path) || return 1
        system_path=$(kr_property "$file" idea.system.path) || return 1
        if [ -n "$config_path" ] && [ -n "$system_path" ]; then
            config_path=$(kr_expand_path "$config_path" "${file%/*}") || continue
            system_path=$(kr_expand_path "$system_path" "${file%/*}") || continue
            [ "$config_path" != "$system_path" ] || printf '警告：配置目录和缓存目录相同。\n' >&2
        fi
    done
    printf '\n诊断完成：%s 个文件，%s 个读取/解析错误。\n' "${#unique[@]}" "$failed"
    [ "$failed" -eq 0 ]
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then kr_diagnose_main "$@"; fi
