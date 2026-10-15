#!/bin/bash
set -e
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resource-loader.sh"

usage() {
    cat <<'EOF'
KeyRun macOS / Linux (Bash 3.2+, jq; HTTP also requires curl)
  bash keyrun.sh [--resource-path README.md] [--format text|json|bytes]
  bash keyrun.sh --diagnose-idea-paths [--properties-path PATH]
  bash keyrun.sh --install [--dry-run] [--yes] [--open-page]
      [--config-dir PATH --product idea] [--ide-home PATH]
  bash switch-source.sh --mode local|http [--http-base URL]
EOF
}
main() {
    local action=resource resource=README.md format=text open_page=false temp
    local tool_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h) usage; return;;
            --install|--diagnose-idea-paths)
                [ "$action" = resource ] || { kr_error 'Choose one action.'; return 1; }
                action=${1#--}; shift;;
            --resource-path|--format)
                [ $# -ge 2 ] || { kr_error "Missing value: $1"; return 1; }
                if [ "$1" = --resource-path ]; then resource="$2"; else format="$2"; fi; shift 2;;
            --open-page) open_page=true; shift;;
            --properties-path|--config-dir|--product|--ide-home)
                [ $# -ge 2 ] || { kr_error "Missing value: $1"; return 1; }
                tool_args+=("$1" "$2"); shift 2;;
            --dry-run|--yes) tool_args+=("$1"); shift;;
            *) kr_error "Unknown option: $1"; return 1;;
        esac
    done
    case "$(uname -s)" in Darwin|Linux) ;; *) kr_error 'Only macOS and Linux are supported.'; return 1;; esac
    case "$action" in
        install)
            if "$open_page"; then tool_args+=(--open-page); fi
            bash "$KR_PROJECT_ROOT/scripts/install.sh" "${tool_args[@]}";;
        diagnose-idea-paths)
            bash "$KR_PROJECT_ROOT/scripts/diagnose-idea-paths.sh" "${tool_args[@]}"
            if "$open_page"; then kr_load_config; kr_open_page; fi;;
        resource)
            [ ${#tool_args[@]} -eq 0 ] || { kr_error 'Installer/diagnostic options need their action.'; return 1; }
            case "$format" in text|json|bytes) ;; *) kr_error 'Expected text, json or bytes.'; return 1;; esac
            kr_load_config
            if "$open_page"; then kr_open_page; return; fi
            temp=$(mktemp -d "${TMPDIR:-/tmp}/keyrun-resource.XXXXXX")
            KR_READ_TEMP="$temp"
            trap 'rm -rf "$KR_READ_TEMP"' EXIT
            kr_fetch_resource "$resource" "$temp/resource"
            case "$format" in
                bytes) cat "$temp/resource";;
                text|json)
                    # iconv rejects invalid UTF-8; jq alone replaces some invalid sequences.
                    kr_require iconv
                    iconv -f UTF-8 -t UTF-8 "$temp/resource" > "$temp/text"
                    if [ "$(od -An -tx1 -N3 "$temp/text" | tr -d ' \n')" = efbbbf ]; then
                        dd if="$temp/text" of="$temp/no-bom" bs=1 skip=3 2>/dev/null
                    else cp "$temp/text" "$temp/no-bom"; fi
                    if [ "$format" = json ]; then jq -s 'if length == 1 then .[0] else error("Expected one JSON value") end' "$temp/no-bom"
                    else cat "$temp/no-bom"; fi;;
            esac;;
    esac
}
main "$@"
