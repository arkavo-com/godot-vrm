#!/usr/bin/env sh
# Installs addons/facets (core only) into a blank project and verifies:
#   1. the project imports and core rules run with the editor plugin disabled;
#   2. enabling the plugin in a headless editor loads without script errors.
# Usage: GODOT=/path/to/godot tools/verify_clean_install.sh
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/addons"
cp -R addons/facets "$WORK/addons/facets"
cat > "$WORK/project.godot" <<'CFG'
config_version=5

[application]

config/name="FACETS clean install"
config/features=PackedStringArray("4.7")
CFG
cat > "$WORK/smoke.gd" <<'GD'
extends SceneTree
func _initialize() -> void:
	var registry := FacetsRegistry.core()
	var world := FacetsWorldSnapshot.new()
	var actor := FacetsActorState.new()
	actor.actor_id = "hero"
	actor.display_name = "Hero"
	actor.build = FacetsBuild.from_dict(registry.get_archetype("core.archetype.courier")["build"])
	world.add_actor(actor)
	assert(registry.add_action({"id": "smoke.climb", "version": 1, "approaches": [{"id": "a", "facet": "agility", "skill": "athletics"}], "difficulty": {"kind": "fixed", "target": 11}, "retry_policy": "repeatable"}).ok)
	var session: FacetsSession = FacetsSession.create(registry, world, {"dice": FacetsDiceSource.fixed([[3, 3]])}).value
	var preview: FacetsCheckPreview = session.preview(FacetsActionRequest.make("hero", "smoke.climb", "a")).value
	var event: FacetsResolutionEvent = session.commit(preview.token, {}, "r1").value
	var ok := registry.skill_ids().size() == 12 and registry.talent_ids().size() == 6 and event != null and event.dice == [3, 3] and not Engine.is_editor_hint()
	print("CLEAN INSTALL CORE: %s (band %s)" % ["ok" if ok else "FAIL", event.base.get("band", "?")])
	quit(0 if ok else 1)
GD
"$GODOT" --headless --path "$WORK" --editor --import > "$WORK/import.log" 2>&1 || { cat "$WORK/import.log"; exit 1; }
"$GODOT" --headless --path "$WORK" --script smoke.gd > "$WORK/smoke.log" 2>&1 || { cat "$WORK/smoke.log"; exit 1; }
grep "CLEAN INSTALL CORE: ok" "$WORK/smoke.log"
if grep -E "SCRIPT ERROR|Parse Error" "$WORK/smoke.log"; then exit 1; fi
sed -i.bak 's#^config/features=.*#&\n\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/facets/plugin.cfg")#' "$WORK/project.godot"
grep -q 'res://addons/facets/plugin.cfg' "$WORK/project.godot" || { echo "could not enable the plugin" >&2; exit 1; }
"$GODOT" --headless --editor --path "$WORK" --quit-after 300 > "$WORK/editor.log" 2>&1 || true
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "$WORK/editor.log"; then
	echo "CLEAN INSTALL EDITOR: FAIL"
	exit 1
fi
echo "CLEAN INSTALL EDITOR: ok (plugin enabled, no script errors)"
