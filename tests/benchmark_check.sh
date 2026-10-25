#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

cat > "$fixture/offset_motion.lua" <<'LUA'
local motion = dofile("content/swaying_waying/motion.lua")
local animationTimes = motion.animationTimes
motion.animationTimes = function(...)
    local roll, heave, pitch = animationTimes(...)
    return roll + 1, heave - 1, pitch
end
return motion
LUA

if lua scripts/benchmark_motion.lua 1 "$fixture/offset_motion.lua" > "$fixture/output" 2>&1; then
    echo 'Benchmark accepted equal and opposite roll/heave errors' >&2
    exit 1
fi
if ! grep -q 'Wave benchmark roll poses disagree' "$fixture/output"; then
    cat "$fixture/output" >&2
    exit 1
fi
printf 'Benchmark validation checks passed\n'
