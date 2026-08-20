#!/usr/bin/env bash
# Run one Godot test script and decide honestly whether it passed.
#
# Exit code alone is not enough. A script whose dependency fails to compile
# aborts _init() before quit(), leaving the SceneTree running forever; and a
# script can print SCRIPT ERROR and still reach quit(0). This wrapper treats
# a timeout and any engine-level error line as failures.
#
# Deliberately `set -uo pipefail` without `-e`: this script's whole job is to
# inspect a non-zero exit code, and `-e` would abort before it could.
set -uo pipefail

GODOT="${GODOT_BIN:-/home/japurane/.local/bin/godot}"
script="${1:?usage: run_godot_test.sh <script-path> [timeout-seconds]}"
limit="${2:-180}"
log=$(mktemp)
importlog=$(mktemp)
trap 'rm -f "$log" "$importlog"' EXIT

# Import before running anything. Godot registers `class_name` declarations in
# .godot/global_script_class_cache.cfg and resolves asset paths through
# .godot/imported/, both gitignored. Skip this on a fresh clone and every
# suite fails with "Could not find type X" plus a wall of missing-resource
# errors — the code is fine, the engine simply has not indexed it yet. That
# false red would be exactly as useless as the false green this script exists
# to kill. Import is incremental, so it is cheap once the cache is warm.
if ! timeout --signal=KILL "$limit" \
     "$GODOT" --headless --import --path . >"$importlog" 2>&1; then
  echo "FAIL $script: project import failed" >&2
  tail -20 "$importlog" >&2
  exit 1
fi

timeout --signal=KILL "$limit" \
  "$GODOT" --headless --path . --script "$script" >"$log" 2>&1
rc=$?

if [ "$rc" -eq 137 ]; then
  echo "FAIL $script: no exit within ${limit}s (script likely errored before quit())" >&2
  tail -20 "$log" >&2
  exit 1
fi

if grep -qE 'SCRIPT ERROR|Parse Error|ERROR: Failed loading|ERROR: Attempt to open script' "$log"; then
  echo "FAIL $script: engine reported an error" >&2
  grep -E 'SCRIPT ERROR|Parse Error|ERROR:' "$log" | head -10 >&2
  exit 1
fi

if [ "$rc" -ne 0 ]; then
  echo "FAIL $script: exit code $rc" >&2
  tail -20 "$log" >&2
  exit 1
fi

echo "PASS $script"
