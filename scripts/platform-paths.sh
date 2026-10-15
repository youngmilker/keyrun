#!/bin/bash
# Shared discovery/diagnosis helpers; source after resource-loader.sh.
KR_PRODUCTS=(idea clion phpstorm goland pycharm webstorm rider datagrip rubymine appcode dataspell rustrover)

kr_platform_paths() {
    KR_PLATFORM=$(uname -s)
    KR_USER_HOME="${HOME:-}"
    case "$KR_USER_HOME" in /*) ;; *) kr_error 'HOME must be an absolute directory.'; return 1;; esac
    [ -d "$KR_USER_HOME" ] || { kr_error "HOME does not exist: $KR_USER_HOME"; return 1; }
    case "$KR_PLATFORM" in
        Darwin)
            KR_CONFIG_ROOT="$KR_USER_HOME/Library/Application Support/JetBrains"
            KR_CACHE_ROOT="$KR_USER_HOME/Library/Caches/JetBrains";;
        Linux)
            KR_CONFIG_ROOT="${XDG_CONFIG_HOME:-$KR_USER_HOME/.config}/JetBrains"
            KR_CACHE_ROOT="${XDG_CACHE_HOME:-$KR_USER_HOME/.cache}/JetBrains"
            case "$KR_CONFIG_ROOT:$KR_CACHE_ROOT" in /*:/*) ;; *) kr_error 'XDG paths must be absolute.'; return 1;; esac;;
        *) kr_error 'Only macOS and Linux are supported.'; return 1;;
    esac
}

kr_product_name() {
    local name product
    name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for product in "${KR_PRODUCTS[@]}"; do
        case "$name" in *"$product"*) printf '%s\n' "$product"; return;; esac
    done
    return 1
}

kr_normalize_path() {
    local value="$1" part remaining result='' stack=()
    case "$value" in /*) ;; *) kr_error "Expected absolute path: $value"; return 1;; esac
    remaining=${value#/}
    while :; do
        part=${remaining%%/*}
        case "$part" in
            ''|.) ;;
            ..) if [ ${#stack[@]} -gt 0 ]; then unset 'stack[${#stack[@]}-1]'; fi;;
            *) stack+=("$part");;
        esac
        [ "$remaining" != "$part" ] || break
        remaining=${remaining#*/}
    done
    for part in "${stack[@]}"; do result="$result/$part"; done
    printf '%s\n' "${result:-/}"
}

# Reads values, never evaluates shell or Java property contents.
kr_property() {
    [ -f "$1" ] || return 0
    awk -v key="$2" '
      { sub(/\r$/, ""); line=$0; sub(/^[ \t]+/, "", line) }
      line !~ /^[#!]/ && index(line, "=") {
        k=substr(line,1,index(line,"=")-1); sub(/[ \t]+$/, "", k)
        if (k==key) { value=substr(line,index(line,"=")+1); sub(/^[ \t]+/, "", value); sub(/[ \t]+$/, "", value); found=1 }
      }
      END { if (found) print value }' "$1"
}

kr_expand_path() {
    local value="$1" relative_to="$2"
    [ -n "$value" ] || return 0
    value=${value//'${user.home}'/$KR_USER_HOME}
    case "$value" in '~/'*) value="$KR_USER_HOME/${value#\~/}";; esac
    # Common Java-properties escaped paths. Unsupported variables fail explicitly.
    value=${value//\\ / }; value=${value//\\:/:}; value=${value//\\\\/\\}
    case "$value" in *'${'*|*'$('*|*'`'*|*$'\n'*|*$'\r'*) kr_error "Unsupported path expression: $value"; return 1;; esac
    case "$value" in /*) ;; *) value="$relative_to/$value";; esac
    kr_normalize_path "$value"
}

kr_ide_bin() {
    local home="$1"
    if [ -d "$home/Contents/bin" ]; then printf '%s\n' "$home/Contents/bin"
    elif [ -d "$home/bin" ]; then printf '%s\n' "$home/bin"
    else return 1; fi
}

kr_product_info() {
    local home="$1" file
    for file in "$home/product-info.json" "$home/Resources/product-info.json" "$home/Contents/Resources/product-info.json"; do
        if [ -f "$file" ]; then printf '%s\n' "$file"; return; fi
    done
    return 1
}

kr_add_installation() {
    local home="$1" bin existing existing_bin
    bin=$(kr_ide_bin "$home") || return 0
    bin=$(cd -P "$bin" && pwd) || return 1
    for existing in "${KR_INSTALLATIONS[@]}"; do
        existing_bin=$(kr_ide_bin "$existing") || continue
        existing_bin=$(cd -P "$existing_bin" && pwd) || continue
        [ "$bin" != "$existing_bin" ] || return 0
    done
    KR_INSTALLATIONS+=("$home")
}

kr_discover_installations() {
    KR_INSTALLATIONS=()
    local entry home root info existing duplicate
    for entry in "$KR_CACHE_ROOT"/*/.home; do
        [ -f "$entry" ] || continue
        home=$(cat "$entry") || return 1
        home=${home%$'\r'}
        kr_add_installation "$home" || return 1
    done
    if [ "$KR_PLATFORM" = Darwin ]; then
        for entry in "${KEYRUN_APPLICATIONS_DIR:-/Applications}"/*.app "$KR_USER_HOME/Applications"/*.app; do
            kr_add_installation "$entry" || return 1
        done
        root="$KR_USER_HOME/Library/Application Support/JetBrains/Toolbox/apps"
    else
        for entry in "${KEYRUN_OPT_DIR:-/opt}"/* "${KEYRUN_OPT_DIR:-/opt}"/*/* "$KR_USER_HOME/.local/share/JetBrains"/*; do
            if [ -f "$entry/product-info.json" ]; then kr_add_installation "$entry" || return 1; fi
        done
        root="${XDG_DATA_HOME:-$KR_USER_HOME/.local/share}/JetBrains/Toolbox/apps"
    fi
    # Bounded glob scan for old and new Toolbox layouts; no full disk traversal.
    for entry in "$root"/* "$root"/*/* "$root"/*/*/* "$root"/*/*/*/*.app; do
        info=$(kr_product_info "$entry") || continue
        kr_add_installation "$entry" || return 1
    done
    return 0
}

kr_installation_for_config() {
    local config_name="$1" file home info data
    file="$KR_CACHE_ROOT/$config_name/.home"
    if [ -f "$file" ]; then
        home=$(cat "$file") || return 1; home=${home%$'\r'}
        if kr_ide_bin "$home" >/dev/null; then printf '%s\n' "$home"; return; fi
    fi
    for home in "${KR_INSTALLATIONS[@]}"; do
        info=$(kr_product_info "$home") || continue
        data=$(jq -er '.dataDirectoryName | select(type == "string" and length > 0)' "$info" 2>/dev/null) || continue
        if [ "$data" = "$config_name" ]; then printf '%s\n' "$home"; return; fi
    done
    return 1
}

kr_properties_file() {
    local value="$1" candidate
    for candidate in "$value" "$value/idea.properties" "$value/bin/idea.properties" "$value/Contents/bin/idea.properties"; do
        if [ -f "$candidate" ] && [ "${candidate##*/}" = idea.properties ]; then printf '%s\n' "$candidate"; return; fi
    done
    return 1
}

kr_safe_write_path() {
    local path parent
    path=$(kr_normalize_path "$1") || return 1
    case "$path" in /|"$KR_USER_HOME"|"$KR_CONFIG_ROOT"|"$KR_CACHE_ROOT") kr_error "Refusing broad write target: $path"; return 1;; esac
    parent="$path"
    while [ "$parent" != / ]; do
        [ ! -L "$parent" ] || { kr_error "Linked write path rejected: $parent"; return 1; }
        parent=${parent%/*}; parent=${parent:-/}
    done
    if [ -e "$path" ] && [ ! -w "$path" ]; then kr_error "Target is not writable: $path"; return 1; fi
}
