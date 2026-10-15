#!/bin/bash
# Native macOS/Linux installer; only user configuration files are modified.
set -e
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/resource-loader.sh"
source "$KR_PROJECT_ROOT/scripts/platform-paths.sh"

kr_install_resources() {
    local name
    printf '%s\n' ja-netfilter/ja-netfilter.jar
    for name in dns env native power url; do printf 'ja-netfilter/config/%s.conf\n' "$name"; done
    for name in dns env native power url hideme privacy; do printf 'ja-netfilter/plugins/%s.jar\n' "$name"; done
    for name in "${KR_PRODUCTS[@]}"; do printf 'licenses/%s.key\n' "$name"; done
}

kr_plan_target() {
    local config="$1" product="$2" home="$3" bin='' prop value variable template='' vm_file existing
    local properties=()
    config=$(kr_expand_path "$config" "$PWD") || return 1
    if [ -n "$home" ]; then bin=$(kr_ide_bin "$home") || { kr_error "IDE bin not found: $home"; return 1; }; fi
    variable=$(printf '%s_PROPERTIES' "$product" | tr '[:lower:]' '[:upper:]')
    value=${!variable}
    # Merge keys in precedence order; an unrelated custom property must not hide a bundled path.
    if [ -n "$bin" ] && [ -f "$bin/idea.properties" ]; then properties+=("$bin/idea.properties"); fi
    if [ -f "$config/idea.properties" ]; then properties+=("$config/idea.properties"); fi
    if [ -n "$value" ]; then
        prop=$(kr_properties_file "$value") || { kr_error "Invalid $variable: $value"; return 1; }
        properties+=("$prop")
    fi
    for prop in "${properties[@]}"; do
        value=$(kr_property "$prop" idea.config.path) || return 1
        if [ -n "$value" ]; then config=$(kr_expand_path "$value" "${prop%/*}") || return 1; fi
    done
    for existing in "${KR_TARGET_CONFIGS[@]}"; do
        [ "$existing" != "$config" ] || { kr_error "Multiple versions resolve to the same config: $config"; return 1; }
    done
    if [ "$KR_PLATFORM" = Darwin ]; then vm_file="$config/$product.vmoptions"
    else vm_file="$config/${product}64.vmoptions"; fi
    if [ ! -f "$vm_file" ] && [ -f "$config/$product.vmoptions" ]; then vm_file="$config/$product.vmoptions"; fi
    if [ -f "$vm_file" ]; then template="$vm_file"
    elif [ -n "$bin" ]; then
        for existing in "$bin/${vm_file##*/}" "$bin/$product.vmoptions" "$bin/${product}64.vmoptions"; do
            if [ -f "$existing" ]; then template="$existing"; break; fi
        done
    fi
    if [ -z "$template" ]; then
        printf '跳过 / Skipped: %s (没有现有 VM options 或安装模板；可指定 --ide-home)\n' "$config" >&2
        KR_SKIPPED=$((KR_SKIPPED + 1)); return 0
    fi
    [ -s "$template" ] || { kr_error "Empty VM options template: $template"; return 1; }
    kr_safe_write_path "$config" || return 1
    kr_safe_write_path "$vm_file" || return 1
    kr_safe_write_path "$config/$product.key" || return 1
    if [ -e "$config/disabled_plugins.txt" ]; then kr_safe_write_path "$config/disabled_plugins.txt" || return 1; fi
    KR_TARGET_CONFIGS+=("$config"); KR_TARGET_PRODUCTS+=("$product")
    KR_TARGET_VMS+=("$vm_file"); KR_TARGET_TEMPLATES+=("$template")
}

kr_build_install_plan() {
    local config="$1" selected="$2" explicit_home="$3" dir product home info name found
    KR_TARGET_CONFIGS=(); KR_TARGET_PRODUCTS=(); KR_TARGET_VMS=(); KR_TARGET_TEMPLATES=(); KR_SKIPPED=0
    if [ -n "$config" ]; then
        [ -n "$selected" ] || { kr_error '--config-dir requires --product.'; return 1; }
        found=false
        for product in "${KR_PRODUCTS[@]}"; do [ "$product" != "$selected" ] || found=true; done
        "$found" || { kr_error "Unsupported product: $selected"; return 1; }
        kr_plan_target "$config" "$selected" "$explicit_home" || return 1
    else
        [ -z "$selected$explicit_home" ] || { kr_error '--product/--ide-home require --config-dir.'; return 1; }
        kr_discover_installations || return 1
        for dir in "$KR_CONFIG_ROOT"/*; do
            [ -d "$dir" ] || continue
            product=$(kr_product_name "${dir##*/}") || continue
            home=$(kr_installation_for_config "${dir##*/}") || home=''
            kr_plan_target "$dir" "$product" "$home" || return 1
        done
        for home in "${KR_INSTALLATIONS[@]}"; do
            info=$(kr_product_info "$home") || continue
            name=$(jq -er '.dataDirectoryName | select(type == "string" and length > 0)' "$info" 2>/dev/null) || continue
            case "$name" in *'/'*|*'\'*|.|..|*$'\n'*) kr_error "Invalid dataDirectoryName: $info"; return 1;; esac
            [ ! -d "$KR_CONFIG_ROOT/$name" ] || continue
            product=$(kr_product_name "$name") || continue
            kr_plan_target "$KR_CONFIG_ROOT/$name" "$product" "$home" || return 1
        done
    fi
    [ ${#KR_TARGET_CONFIGS[@]} -gt 0 ] || { kr_error 'No IDE target found. Open the IDE once or specify --config-dir, --product and --ide-home.'; return 1; }
}

kr_render_vmoptions() {
    awk '{ sub(/\r$/, "") }
      !($0 ~ /^[ \t]*-javaagent:/ && $0 ~ /(ja-netfilter\.jar|\/\.jb_run\/)/) { print }' "$1" > "$2" || return 1
    printf -- '-javaagent:%s\n' "$3" >> "$2"
}

kr_profile_rewrite() {
    awk -v names="$3" '
      BEGIN { n=split(names,a,"|"); for(i=1;i<=n;i++) keys[a[i]]=1 }
      {
        line=$0; sub(/\r$/, "", line); sub(/^[ \t]+/, "", line)
        if (line ~ /^#/) { print $0; next }
        sub(/^export[ \t]+/, "", line)
        key=line; sub(/=.*/, "", key)
        if (key in keys) {
          if (line ~ /;|&&|\|\|/) { bad=1; print $0 }
          next
        }
        for(k in keys) if(index(line,k)>0) bad=1
        print $0
      }
      END { if(bad) exit 2 }' "$1" > "$2" || {
        kr_error "Complex VM_OPTIONS definition needs manual review: $1"; return 1;
    }
}

kr_backup_file() {
    local path="$1" existing
    for existing in "${KR_BACKED_UP[@]}"; do [ "$existing" != "$path" ] || return 0; done
    kr_safe_write_path "$path" || return 1
    if [ -e "$path" ]; then
        [ -f "$path" ] || { kr_error "Target is not a file: $path"; return 1; }
        mkdir -p "$KR_BACKUP/files${path%/*}" || return 1
        cp -p "$path" "$KR_BACKUP/files$path" || return 1
        jq -cn --arg path "$path" '{path:$path,existed:true}' >> "$KR_BACKUP/manifest.jsonl" || return 1
    else jq -cn --arg path "$path" '{path:$path,existed:false}' >> "$KR_BACKUP/manifest.jsonl" || return 1; fi
    KR_BACKED_UP+=("$path")
}

kr_atomic_copy() {
    local source_file="$1" destination="$2" pending
    kr_safe_write_path "$destination" || return 1
    kr_backup_file "$destination" || return 1
    mkdir -p "${destination%/*}" || return 1
    pending=$(mktemp "${destination%/*}/.keyrun.XXXXXX") || return 1
    KR_PENDING_FILES+=("$pending")
    if [ -f "$destination" ]; then cp -p "$destination" "$pending" || return 1; fi
    cat "$source_file" > "$pending" || return 1
    KR_TOUCHED+=("$destination")
    mv -f "$pending" "$destination" || return 1
}

kr_install_cleanup() {
    local status=$? path i
    trap - EXIT
    if [ "$status" -ne 0 ] && [ "${KR_COMMITTED:-false}" != true ]; then
        for ((i=${#KR_TOUCHED[@]}-1; i>=0; i--)); do
            path=${KR_TOUCHED[$i]}
            if [ -f "$KR_BACKUP/files$path" ]; then cp -p "$KR_BACKUP/files$path" "$path" || printf '恢复失败 / Restore failed: %s\n' "$path" >&2
            else rm -f "$path" || printf '恢复失败 / Restore failed: %s\n' "$path" >&2; fi
        done
        for ((i=0; i<${#KR_LAUNCH_NAMES[@]}; i++)); do
            launchctl setenv "${KR_LAUNCH_NAMES[$i]}" "${KR_LAUNCH_VALUES[$i]}" || true
        done
        [ -z "${KR_BACKUP:-}" ] || printf '安装失败，已尝试恢复已修改文件。备份 / Backup: %s\n' "$KR_BACKUP" >&2
    fi
    for path in "${KR_PENDING_FILES[@]}"; do [ ! -f "$path" ] || rm -f "$path"; done
    if [ "${KR_HAS_LOCK:-false}" = true ]; then rmdir "$KR_WORK/.install-lock" || true; fi
    [ -z "${KR_STAGE:-}" ] || rm -rf "$KR_STAGE"
    exit "$status"
}

kr_install_main() {
    umask 077
    local dry_run=false yes=false open_page=false config='' product='' home='' resource destination i names='' file variable value answer
    KR_BACKED_UP=(); KR_TOUCHED=(); KR_PENDING_FILES=(); KR_LAUNCH_NAMES=(); KR_LAUNCH_VALUES=(); KR_COMMITTED=false; KR_HAS_LOCK=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=true; shift;;
            --yes) yes=true; shift;;
            --open-page) open_page=true; shift;;
            --config-dir|--product|--ide-home)
                [ $# -ge 2 ] && [ -n "$2" ] || { kr_error "Missing value: $1"; return 1; }
                case "$1" in --config-dir) config="$2";; --product) product="$2";; --ide-home) home="$2";; esac
                shift 2;;
            *) kr_error "Unknown install option: $1"; return 1;;
        esac
    done
    kr_load_config || return 1
    kr_platform_paths || return 1
    kr_build_install_plan "$config" "$product" "$home" || return 1
    KR_WORK="$KR_USER_HOME/.jb_run"
    kr_safe_write_path "$KR_WORK" || return 1
    printf '平台 / Platform: %s\n资源来源 / Source: %s\n工作目录 / Work: %s\n' "$KR_PLATFORM" "$KR_MODE" "$KR_WORK"
    for ((i=0; i<${#KR_TARGET_CONFIGS[@]}; i++)); do
        printf '[%s] %s\n  VM options: %s\n  模板 / Template: %s\n' "${KR_TARGET_PRODUCTS[$i]}" "${KR_TARGET_CONFIGS[$i]}" "${KR_TARGET_VMS[$i]}" "${KR_TARGET_TEMPLATES[$i]}"
        variable=$(printf '%s_VM_OPTIONS' "${KR_TARGET_PRODUCTS[$i]}" | tr '[:lower:]' '[:upper:]')
        case "|$names|" in *"|$variable|"*) ;; *) names="${names:+$names|}$variable";; esac
    done
    KR_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/keyrun-install.XXXXXX") || return 1
    trap kr_install_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    KR_PROFILE_INPUTS=(); KR_PROFILE_OUTPUTS=()
    for file in "$KR_USER_HOME/.profile" "$KR_USER_HOME/.bash_profile" "$KR_USER_HOME/.bashrc" "$KR_USER_HOME/.zprofile" "$KR_USER_HOME/.zshrc" "$KR_USER_HOME/.zshenv"; do
        [ -f "$file" ] || continue
        destination="$KR_STAGE/profile-${#KR_PROFILE_INPUTS[@]}"
        kr_profile_rewrite "$file" "$destination" "$names" || return 1
        if ! cmp -s "$file" "$destination"; then
            kr_safe_write_path "$file" || return 1
            KR_PROFILE_INPUTS+=("$file"); KR_PROFILE_OUTPUTS+=("$destination")
            printf '清理冲突环境变量 / Clear VM_OPTIONS: %s\n' "$file"
        fi
    done
    if "$dry_run"; then printf '预览完成：%s 个目标，%s 个跳过；未下载资源或修改 IDE。\n' "${#KR_TARGET_CONFIGS[@]}" "$KR_SKIPPED"; return; fi
    [ "$(id -u)" -ne 0 ] || { kr_error '请以当前桌面用户运行，勿使用 sudo/root。'; return 1; }
    if ! "$yes"; then
        printf '请关闭所有 JetBrains IDE。确认安装并备份配置？[y/N] ' > /dev/tty || { kr_error 'Non-interactive run requires --yes.'; return 1; }
        IFS= read -r answer < /dev/tty || return 1
        case "$answer" in y|Y|yes|YES) ;; *) kr_error 'Cancelled.'; return 1;; esac
    fi
    while IFS= read -r resource; do
        mkdir -p "$KR_STAGE/resources/${resource%/*}" || return 1
        kr_fetch_resource "$resource" "$KR_STAGE/resources/$resource" || return 1
        [ -s "$KR_STAGE/resources/$resource" ] || { kr_error "Empty install resource: $resource"; return 1; }
    done < <(kr_install_resources)
    printf '资源预检完成：25 个文件。\n'
    for ((i=0; i<${#KR_TARGET_CONFIGS[@]}; i++)); do
        kr_render_vmoptions "${KR_TARGET_TEMPLATES[$i]}" "$KR_STAGE/vm-$i" "$KR_WORK/ja-netfilter.jar" || return 1
        file="${KR_TARGET_CONFIGS[$i]}/disabled_plugins.txt"
        if [ -f "$file" ]; then awk '{sub(/\r$/, "")} $0 != "com.intellij.modules.ultimate" {print}' "$file" > "$KR_STAGE/plugins-$i" || return 1; fi
    done
    kr_safe_write_path "$KR_WORK/backups" || return 1
    mkdir -p "$KR_WORK" || return 1
    mkdir "$KR_WORK/.install-lock" 2>/dev/null || { kr_error "Another install or retained lock exists: $KR_WORK/.install-lock"; return 1; }
    KR_HAS_LOCK=true
    mkdir -p "$KR_WORK/backups" || return 1
    KR_BACKUP=$(mktemp -d "$KR_WORK/backups/run-$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
    while IFS= read -r resource; do
        case "$resource" in licenses/*) continue;; ja-netfilter/*) destination="$KR_WORK/${resource#ja-netfilter/}";; esac
        kr_atomic_copy "$KR_STAGE/resources/$resource" "$destination" || return 1
    done < <(kr_install_resources)
    for ((i=0; i<${#KR_TARGET_CONFIGS[@]}; i++)); do
        kr_atomic_copy "$KR_STAGE/vm-$i" "${KR_TARGET_VMS[$i]}" || return 1
        kr_atomic_copy "$KR_STAGE/resources/licenses/${KR_TARGET_PRODUCTS[$i]}.key" "${KR_TARGET_CONFIGS[$i]}/${KR_TARGET_PRODUCTS[$i]}.key" || return 1
        if [ -f "$KR_STAGE/plugins-$i" ]; then kr_atomic_copy "$KR_STAGE/plugins-$i" "${KR_TARGET_CONFIGS[$i]}/disabled_plugins.txt" || return 1; fi
    done
    for ((i=0; i<${#KR_PROFILE_INPUTS[@]}; i++)); do
        kr_atomic_copy "${KR_PROFILE_OUTPUTS[$i]}" "${KR_PROFILE_INPUTS[$i]}" || return 1
    done
    if [ "$KR_PLATFORM" = Darwin ]; then
        kr_require launchctl || return 1
        local launch_names=()
        IFS='|' read -r -a launch_names <<< "$names"
        for variable in "${launch_names[@]}"; do
            value=$(launchctl getenv "$variable") || value=''
            if [ -n "$value" ]; then
                KR_LAUNCH_NAMES+=("$variable"); KR_LAUNCH_VALUES+=("$value")
                launchctl unsetenv "$variable" || return 1
            fi
        done
    fi
    KR_COMMITTED=true
    printf '文件写入完成：%s 个目标，%s 个跳过。\n备份 / Backup: %s\n重新打开 IDE 检查结果；当前终端中的环境变量需在新终端中确认。\n' "${#KR_TARGET_CONFIGS[@]}" "$KR_SKIPPED" "$KR_BACKUP"
    if "$open_page"; then kr_open_page || printf '文件处理完成，但打开网页失败。\n' >&2; fi
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then kr_install_main "$@"; fi
