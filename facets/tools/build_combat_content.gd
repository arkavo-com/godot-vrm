extends SceneTree
## Regenerates the optional combat package content (two talents and sample
## weapons) under addons/facets_combat/content/. Usage:
##   godot --headless --path . --script tools/build_combat_content.gd

const ROOT := "res://addons/facets_combat/content"


func _initialize() -> void:
	var failures := 0
	for sub in ["talents", "weapons"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join(sub)))
	var pack := FacetsRulesPack.new()
	pack.pack_id = "facets.combat"
	pack.version = "0.1.0"
	pack.dependencies = {"facets.core": "0.1.0"}
	pack.compatibility = "Optional zone combat for FACETS 0.1.0."
	var bodyguard := _talent("combat.bodyguard", "Bodyguard", "Use your reaction to take a hit meant for an ally in your zone along a clear path. Your armor applies. Once per round; interceptions never chain.", "bodyguard", {"uses_per_round": 1}, {}, {"fighting": 1}, "per_round")
	var reserve := _talent("combat.last_reserve", "Last Reserve", "While Overwhelmed, take one normal turn (move and action) once per scene. It does not restore your reaction or let you act while Incapacitated.", "last_reserve", {"uses_per_scene": 1}, {"tenacity": 3}, {}, "per_scene")
	for talent in [bodyguard, reserve]:
		failures += _save(talent, "talents/%s.tres" % talent.id.get_slice(".", 1))
		pack.talents.append(talent)
	failures += _save(pack, "combat_pack.tres")
	var weapons := [
		_weapon("weapon.knife", "Knife", "close", "light", "", [["slash", "agility", "fighting"], ["stab", "force", "fighting"]]),
		_weapon("weapon.baton", "Baton", "close", "standard", "", [["strike", "force", "fighting"], ["jab", "agility", "fighting"]]),
		_weapon("weapon.sledgehammer", "Sledgehammer", "close", "heavy", "", [["swing", "force", "fighting"]]),
		_weapon("weapon.pistol", "Pistol", "ranged", "standard", "ammo.9mm", [["aim", "sense", "marksmanship"], ["snap", "agility", "marksmanship"]]),
		_weapon("weapon.rifle", "Long rifle", "long", "heavy", "ammo.rifle", [["aim", "sense", "marksmanship"]]),
	]
	for weapon in weapons:
		failures += _save(weapon, "weapons/%s.tres" % weapon.id.get_slice(".", 1))
	var registry := FacetsRegistry.core()
	var reply := FacetsCombat.register(registry)
	if not reply.ok:
		printerr("combat pack invalid: ", reply)
		failures += 1
	print("build_combat_content: %s" % ("ok" if failures == 0 else "%d failures" % failures))
	quit(1 if failures > 0 else 0)


func _save(resource: Resource, relative: String) -> int:
	var path := ROOT.path_join(relative)
	var status := ResourceSaver.save(resource, path)
	if status != OK:
		printerr("could not save %s: %s" % [path, error_string(status)])
		return 1
	resource.take_over_path(path)
	return 0


func _talent(id: String, display_name: String, description: String, hook_id: String, parameters: Dictionary, facets: Dictionary, skills: Dictionary, scope: String) -> FacetsTalentResource:
	var talent := FacetsTalentResource.new()
	talent.id = id
	talent.display_name = display_name
	talent.description = description
	talent.hook_id = hook_id
	talent.parameters = parameters
	talent.prerequisite_facets = facets
	talent.prerequisite_skills = skills
	talent.usage_scope = scope
	talent.uses = 1
	talent.package = "combat"
	return talent


func _weapon(id: String, display_name: String, range_band: String, harm_class: String, ammo: String, approaches: Array) -> FacetsWeaponResource:
	var weapon := FacetsWeaponResource.new()
	weapon.id = id
	weapon.display_name = display_name
	weapon.range_band = range_band
	weapon.harm_class = harm_class
	weapon.ammo_type = ammo
	for spec in approaches:
		weapon.approaches.append(FacetsApproachResource.make(spec[0], spec[1], spec[2]))
	return weapon
