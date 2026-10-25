#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
usage() {
    echo 'Usage: scripts/validate.sh [--check|--generate] [--isolation]' >&2
    exit 2
}
mode=--check
mode_selected=false
isolation=0
for argument in "$@"; do
    case "$argument" in
        --check|--generate)
            [[ "$mode_selected" == false ]] || usage
            mode=$argument
            mode_selected=true
            ;;
        --isolation)
            [[ "$isolation" == 0 ]] || usage
            isolation=1
            ;;
        *) usage ;;
    esac
done
teal=${TL:-tl}
if [[ -z "${TL:-}" ]] && ! command -v "$teal" >/dev/null 2>&1; then
    teal="$HOME/.luarocks/bin/tl"
fi
for tool in "$teal" stylua lua python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required development tool not found: $tool" >&2
        exit 1
    fi
done

mapfile -d '' broken_links < <(find -L src content -type l -print0)
if [[ ${#broken_links[@]} -gt 0 ]]; then
    printf 'Broken source/runtime link: %s\n' "${broken_links[@]}" >&2
    exit 1
fi
mapfile -d '' sources < <(find -L src -type f -name '*.tl' -print0 | sort -z)
if [[ ${#sources[@]} -eq 0 ]]; then
    echo 'No Teal sources found under src/.' >&2
    exit 1
fi
"$teal" --werror all check "${sources[@]}"
staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
for source in "${sources[@]}"; do
    relative=${source#src/}
    relative=${relative%.tl}.lua
    generated="$staging/$relative"
    mkdir -p -- "$(dirname -- "$generated")"
    "$teal" gen -o "$generated" "$source" >/dev/null
    stylua --config-path .stylua.toml --verify "$generated"
    if [[ -L "$source" || -L "content/$relative" ]]; then
        if [[ ! -L "$source" || ! -L "content/$relative" ]]; then
            echo "Shared code requires matching source and runtime links: $relative" >&2
            exit 1
        fi
        if ! cmp -s -- "$generated" "content/$relative"; then
            echo "Stale shared Lua: content/$relative (regenerate it in its owning module)" >&2
            exit 1
        fi
    fi
done

stale=false
for source in "${sources[@]}"; do
    relative=${source#src/}
    relative=${relative%.tl}.lua
    if [[ -L "$source" ]]; then
        continue
    elif [[ "$mode" == --generate ]]; then
        mkdir -p -- "$(dirname -- "content/$relative")"
        cp -- "$staging/$relative" "content/$relative"
    elif ! cmp -s -- "$staging/$relative" "content/$relative"; then
        echo "Stale generated file: content/$relative" >&2
        stale=true
    fi
done
if [[ "$stale" == true ]]; then
    echo 'Run scripts/validate.sh --generate and include the generated Lua changes.' >&2
    exit 1
fi
while IFS= read -r -d '' runtime; do
    relative=${runtime#content/}
    source="src/${relative%.lua}.tl"
    if [[ ! -f "$source" ]]; then
        echo "Generated Lua has no Teal source: $runtime" >&2
        exit 1
    fi
done < <(find -L content -type f -name '*.lua' -print0)
python3 scripts/sync_settings.py "$mode"
stylua --config-path .stylua.toml --check tests scripts/export_settings.lua scripts/check_game_models.lua scripts/benchmark_motion.lua
if [[ "$isolation" == 1 ]]; then
    echo 'Isolation build: generated switches retain your edits; regression tests use all motion components.'
fi
for test in tests/*_check.lua; do
    SWAYING_WAYING_TEST_ISOLATION="$isolation" lua "$test"
done
for test in tests/*_check.sh; do
    bash "$test"
done
git diff --check
