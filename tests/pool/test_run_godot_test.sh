#!/usr/bin/env bash
# Verifies the runner catches all three failure modes, not just exit codes.
set -uo pipefail
cd "$(dirname "$0")/../.."
R=./tools/tests/run_godot_test.sh
fails=0
check() { # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want rc=$2 got rc=$3"; fails=$((fails+1)); fi
}

# 1. A healthy test script passes.
$R tests/test_asteroid_collisions.gd 180 >/dev/null 2>&1
check "healthy suite passes" 0 $?

# 2. A script that errors then hangs must fail, not time out the whole CI job.
cat > tests/_fixture_hang.gd <<'GD'
extends SceneTree
func _init() -> void:
	var s := load("res://tests/_fixture_missing.gd")
	var obj = s.new()
	print("ALL TESTS PASSED")
	quit(0)
GD
$R tests/_fixture_hang.gd 20 >/dev/null 2>&1
check "erroring+hanging script fails" 1 $?
rm -f tests/_fixture_hang.gd tests/_fixture_hang.gd.uid

# 3. A script that prints a script error but still exits 0 must fail.
cat > tests/_fixture_silent.gd <<'GD'
extends SceneTree
func _init() -> void:
	# Errors at engine level but never dereferences, so it reaches quit(0).
	# This is the exact shape Finding 6 describes: green exit, broken run.
	var s = load("res://tests/_fixture_missing.gd")
	if s == null:
		pass
	print("ALL TESTS PASSED")
	quit(0)
GD
$R tests/_fixture_silent.gd 30 >/dev/null 2>&1
check "error printed but rc=0 fails" 1 $?
rm -f tests/_fixture_silent.gd tests/_fixture_silent.gd.uid

[ "$fails" -eq 0 ] || exit 1
