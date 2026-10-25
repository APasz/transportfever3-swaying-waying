#!/usr/bin/env bash
set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lua_runner=$(command -v lua)
formatter=$(command -v stylua)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

printf 'return bit32.bxor(1, 2)\n' | "$formatter" --config-path "$repository/.stylua.toml" - > "$fixture/output"
for expression in '1 ~ 2' '1 & 2' '1 >> 2' '1 // 2'; do
    if printf 'return %s\n' "$expression" | "$formatter" --config-path "$repository/.stylua.toml" - > "$fixture/output" 2>&1; then
        echo "Validation parser accepted syntax unavailable in Lua 5.2: $expression" >&2
        exit 1
    fi
    grep -q 'error parsing' "$fixture/output"
done

mkdir -p "$fixture"/{scripts,src,content/swaying_waying,tests,bin}
cp "$repository/scripts/validate.sh" "$fixture/scripts/validate.sh"
cp "$repository/.stylua.toml" "$fixture/.stylua.toml"
touch "$fixture/tests/example_check.lua"
touch "$fixture/scripts/sync_settings.py" "$fixture/scripts/export_settings.lua" "$fixture/scripts/check_game_models.lua"
cat > "$fixture/bin/tl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == --werror ]]; then
    echo check >> trace
    exit "${FAIL_CHECK:-0}"
fi
echo "generate:$4" >> trace
if [[ "${FAIL_SOURCE:-}" == "$4" ]]; then
    exit 1
fi
cp "$4" "$3"
STUB
cat > "$fixture/bin/stylua" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$fixture/bin/lua" <<'STUB'
#!/usr/bin/env bash
echo tests >> trace
echo "isolation:${SWAYING_WAYING_TEST_ISOLATION:-unset}" >> trace
STUB
cat > "$fixture/bin/git" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$fixture/bin/"*
touch "$fixture/tests/example_check.sh"
export PATH="$fixture/bin:$PATH"
export TL="$fixture/bin/tl"
cd "$fixture"
printf 'current\n' > src/example.tl
printf 'current\n' > content/example.lua

scripts/validate.sh > output 2>&1
grep -q '^tests$' trace
grep -q '^isolation:0$' trace

: > trace
scripts/validate.sh --isolation > output 2>&1
grep -q '^isolation:1$' trace
grep -q 'Isolation build:' output

: > trace
SWAYING_WAYING_TEST_ISOLATION=1 scripts/validate.sh > output 2>&1
grep -q '^isolation:0$' trace
! grep -q '^isolation:1$' trace

for argument in --unknown --check --isolation; do
    : > trace
    if scripts/validate.sh "$argument" "$argument" > output 2>&1; then
        echo 'Validation accepted invalid or repeated arguments' >&2
        exit 1
    fi
    [[ ! -s trace ]]
    grep -q '^Usage:' output
done
: > trace
if scripts/validate.sh --check --generate > output 2>&1; then
    echo 'Validation accepted conflicting modes' >&2
    exit 1
fi
[[ ! -s trace ]]

printf 'stale\n' > content/example.lua
: > trace
if scripts/validate.sh > output 2>&1; then
    echo 'Validation accepted stale generated code' >&2
    exit 1
fi
! grep -q '^tests$' trace
grep -q 'Stale generated file' output

: > trace
if FAIL_CHECK=1 scripts/validate.sh --generate > output 2>&1; then
    echo 'Validation accepted a failed type check' >&2
    exit 1
fi
! grep -q -E '^generate:|^tests$' trace

printf 'later\n' > src/z_failure.tl
: > trace
if FAIL_SOURCE=src/z_failure.tl scripts/validate.sh --generate > output 2>&1; then
    echo 'Validation accepted a failed generator' >&2
    exit 1
fi
! grep -q '^tests$' trace
grep -q '^stale$' content/example.lua
[[ ! -e content/z_failure.lua ]]

scripts/validate.sh --isolation --generate > output 2>&1
cmp -s src/example.tl content/example.lua
cmp -s src/z_failure.tl content/z_failure.lua
grep -q '^isolation:1$' trace
scripts/validate.sh > output 2>&1
printf 'orphan\n' > content/orphan.lua
if scripts/validate.sh > output 2>&1; then
    echo 'Validation accepted generated Lua without a source' >&2
    exit 1
fi
grep -q 'Generated Lua has no Teal source' output
rm content/orphan.lua

mkdir -p shared
printf 'shared\n' > shared/source.tl
printf 'shared\n' > shared/runtime.lua
ln -s ../shared/source.tl src/shared.tl
ln -s ../shared/runtime.lua content/shared.lua
scripts/validate.sh --generate > output 2>&1
[[ -L src/shared.tl && -L content/shared.lua ]]
grep -q '^shared$' shared/runtime.lua

printf 'pending-owned-change\n' > src/example.tl
printf 'stale-shared\n' > shared/runtime.lua
: > trace
if scripts/validate.sh --generate > output 2>&1; then
    echo 'Validation regenerated a shared runtime through its link' >&2
    exit 1
fi
grep -q 'Stale shared Lua:' output
grep -q '^stale-shared$' shared/runtime.lua
grep -q '^current$' content/example.lua
! grep -q '^tests$' trace
cp shared/source.tl shared/runtime.lua

rm content/shared.lua
cp shared/runtime.lua content/shared.lua
if scripts/validate.sh --generate > output 2>&1; then
    echo 'Validation accepted an unpaired shared source link' >&2
    exit 1
fi
grep -q 'matching source and runtime links' output
rm content/shared.lua
ln -s ../shared/runtime.lua content/shared.lua
scripts/validate.sh --generate > output 2>&1
grep -q '^pending-owned-change$' content/example.lua

ln -s ../shared/missing.lua content/broken.lua
: > trace
if scripts/validate.sh > output 2>&1; then
    echo 'Validation accepted a broken source/runtime link' >&2
    exit 1
fi
grep -q 'Broken source/runtime link:' output
[[ ! -s trace ]]
rm content/broken.lua

ln -s ../shared/runtime.lua content/shared_orphan.lua
if scripts/validate.sh > output 2>&1; then
    echo 'Validation accepted a linked runtime without a source' >&2
    exit 1
fi
grep -q 'Generated Lua has no Teal source: content/shared_orphan.lua' output

motion_fixture="$fixture/motion"
mkdir -p "$motion_fixture"/{tests,content/swaying_waying}
cp "$repository/tests/motion_config.lua" "$motion_fixture/tests/motion_config.lua"
cd "$motion_fixture"
printf 'return { roll = true, carriageLag = false }\n' > content/swaying_waying/motion_config.lua
SWAYING_WAYING_TEST_ISOLATION=0 "$lua_runner" - <<'LUA'
local config = dofile("tests/motion_config.lua")
assert(config.roll and config.carriageLag, "regressions exercise the optional carriage lag")
local runtime = dofile("content/swaying_waying/motion_config.lua")
assert(not runtime.carriageLag, "normal validation preserves the default-off developer toggle on disk")
LUA
printf 'return { roll = false, carriageLag = false }\n' > content/swaying_waying/motion_config.lua
if SWAYING_WAYING_TEST_ISOLATION=0 "$lua_runner" tests/motion_config.lua > output 2>&1; then
    echo 'Release validation accepted a disabled motion component' >&2
    exit 1
fi
grep -q 'Release motion component is disabled: roll' output
SWAYING_WAYING_TEST_ISOLATION=1 "$lua_runner" - <<'LUA'
local config = dofile("tests/motion_config.lua")
assert(config.roll and config.carriageLag, "isolation regressions enable every component")
local runtime = dofile("content/swaying_waying/motion_config.lua")
assert(not runtime.roll and not runtime.carriageLag, "isolation validation preserves the diagnostic build on disk")
LUA
printf 'return { roll = true, carriageLag = "false" }\n' > content/swaying_waying/motion_config.lua
if SWAYING_WAYING_TEST_ISOLATION=1 "$lua_runner" tests/motion_config.lua > output 2>&1; then
    echo 'Isolation validation accepted a malformed motion switch' >&2
    exit 1
fi
grep -q 'Expected a boolean motion switch: carriageLag' output
printf 'return { roll = true, carriageLag = true }\n' > content/swaying_waying/motion_config.lua
SWAYING_WAYING_TEST_ISOLATION=0 "$lua_runner" tests/motion_config.lua
printf 'Validation workflow checks passed\n'
