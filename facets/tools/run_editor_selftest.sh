#!/usr/bin/env sh
# Runs the FACETS editor self-test in a headless editor.
# Usage: GODOT=/path/to/godot tools/run_editor_selftest.sh
# Temporarily enables the development-only self-test plugin in
# project.godot and restores the original file afterwards.
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
cp project.godot project.godot.selftest-backup
cleanup() {
	mv project.godot.selftest-backup project.godot
}
trap cleanup EXIT
sed -i.tmp 's#^enabled=PackedStringArray("res://addons/facets/plugin.cfg")#enabled=PackedStringArray("res://addons/facets/plugin.cfg", "res://addons/facets_editor_selftest/plugin.cfg")#' project.godot
rm -f project.godot.tmp
grep -q facets_editor_selftest project.godot || { echo "could not enable self-test plugin" >&2; exit 1; }
status=0
timeout 300 "$GODOT" --headless --editor --path . -- --facets-editor-selftest > build-selftest.log 2>&1 || status=$?
grep -E "FACETS editor self-test|  ok |  FAIL|SCRIPT ERROR" build-selftest.log || true
if ! grep -q "FACETS editor self-test: .* 0 failures" build-selftest.log; then
	echo "Editor self-test failed (exit $status); see build-selftest.log" >&2
	exit 1
fi
rm -f build-selftest.log
