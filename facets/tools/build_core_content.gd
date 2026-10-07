extends SceneTree
## Regenerates the core content Resources under addons/facets/content/core/.
## The generated .tres files are the authoring source afterwards; rerun this
## only to reset them. Usage:
##   godot --headless --path . --script tools/build_core_content.gd

const ROOT := "res://addons/facets/content/core"

const SKILLS := {
	"athletics": ["Athletics", "Climbing, running, jumping, swimming and enduring physical exertion."],
	"fighting": ["Fighting", "Close combat with hands or melee weapons, and close defense."],
	"marksmanship": ["Marksmanship", "Ranged weapons and thrown objects."],
	"stealth": ["Stealth", "Moving unseen and unheard, hiding and shadowing."],
	"sleight": ["Sleight", "Fine manipulation: pickpocketing, palming, lockwork and quiet hands."],
	"investigation": ["Investigation", "Searching, analysing evidence, research and deduction."],
	"survival": ["Survival", "Tracking, navigation, foraging and reading terrain."],
	"technology": ["Technology", "Operating, bypassing and repairing devices and systems."],
	"craft": ["Craft", "Building, repairing and improvising physical things."],
	"medicine": ["Medicine", "First aid, treatment, diagnosis and stabilization."],
	"influence": ["Influence", "Persuasion, negotiation, intimidation and reading motives."],
	"performance": ["Performance", "Acting, music, deception through presentation and holding attention."],
}


func _initialize() -> void:
	var failures := 0
	for sub in ["skills", "talents", "conditions", "archetypes"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join(sub)))
	var pack := FacetsRulesPack.new()
	pack.pack_id = "facets.core"
	pack.version = FacetsRules.RULESET_VERSION
	pack.compatibility = "FACETS rules draft v0.1; Godot 4.6.3 baseline."
	for skill_id in FacetsRules.CORE_SKILLS:
		var skill := FacetsSkillResource.new()
		skill.id = skill_id
		skill.display_name = SKILLS[skill_id][0]
		skill.description = SKILLS[skill_id][1]
		failures += _save(skill, "skills/%s.tres" % skill_id)
		pack.skills.append(skill)
	for condition in _conditions():
		failures += _save(condition, "conditions/%s.tres" % condition.id.trim_prefix("core."))
		pack.conditions.append(condition)
	for talent in _talents():
		failures += _save(talent, "talents/%s.tres" % talent.id.trim_prefix("core."))
		pack.talents.append(talent)
	for archetype in _archetypes():
		failures += _save(archetype, "archetypes/%s.tres" % archetype.id.trim_prefix("core.archetype."))
		pack.archetypes.append(archetype)
	var policy := FacetsAdmissionPolicy.standard()
	failures += _save(policy, "standard_admission.tres")
	pack.admission_policy = policy
	failures += _save(pack, "core_pack.tres")
	var registry := FacetsRegistry.create()
	var reply := registry.register_pack(pack)
	if not reply.ok:
		printerr("core pack invalid: ", reply)
		failures += 1
	for archetype_id in registry.archetype_ids():
		var build := FacetsBuild.from_dict(registry.get_archetype(archetype_id)["build"])
		var errors := FacetsValidator.validate_creation(build, registry)
		if not errors.is_empty():
			printerr("archetype %s invalid: %s" % [archetype_id, errors])
			failures += 1
	print("build_core_content: %s" % ("ok" if failures == 0 else "%d failures" % failures))
	quit(1 if failures > 0 else 0)


func _save(resource: Resource, relative: String) -> int:
	var path := ROOT.path_join(relative)
	var status := ResourceSaver.save(resource, path)
	if status != OK:
		printerr("could not save %s: %s" % [path, error_string(status)])
		return 1
	resource.take_over_path(path)
	return 0


func _conditions() -> Array[FacetsConditionResource]:
	var result: Array[FacetsConditionResource] = []
	result.append(_condition("core.overwhelmed", "Overwhelmed", "Strain has reached capacity. -1 to checks; no pushing and no combat reactions. Removed when strain falls below capacity.", ["checks"], [], -1, ["no_push", "no_reactions", "limited_turn"], "strain_below_capacity"))
	result.append(_condition("core.injured", "Injured", "Harm 3 or more. -1 to physical checks.", ["checks", "physical"], ["force", "agility"], -1, [], "harm_below_3"))
	result.append(_condition("core.incapacitated", "Incapacitated", "Harm 6 or more. Unable to act or react.", ["checks", "combat"], [], 0, ["cannot_act", "no_reactions", "no_move"], "harm_below_6"))
	result.append(_condition("core.shaken", "Shaken", "Rattled by fear. -1 to Empathy and Tenacity checks.", ["checks"], ["empathy", "tenacity"], -1, [], "breather"))
	result.append(_condition("core.restrained", "Restrained", "Held or bound. Cannot move; -2 to physical checks.", ["checks", "physical"], ["force", "agility"], -2, ["no_move"], "manual"))
	return result


func _condition(id: String, display_name: String, description: String, tags: Array[String], facets: Array[String], penalty: int, restrictions: Array[String], removal: String) -> FacetsConditionResource:
	var condition := FacetsConditionResource.new()
	condition.id = id
	condition.display_name = display_name
	condition.description = description
	condition.applicability_tags = tags
	condition.applies_to_facets = facets
	condition.penalty = penalty
	condition.restrictions = restrictions
	condition.removal_operation = removal
	return condition


func _talents() -> Array[FacetsTalentResource]:
	var result: Array[FacetsTalentResource] = []
	result.append(_talent("core.second_look", "Second Look", "After a failed attempt, try again once per scene by examining an alternate authored evidence source and spending an extra interval. Never a free unchanged reroll.", "second_look",
		{"skills": ["investigation"], "uses_per_scene": 1, "interval": 1}, {}, {"investigation": 1}))
	result.append(_talent("core.quiet_hands", "Quiet Hands", "On a strong success with Stealth or Sleight, leaving no trace may replace the strong benefit.", "quiet_hands",
		{"skills": ["stealth", "sleight"], "benefit_id": "quiet_hands.no_trace", "label": "Quiet Hands: leave no trace of the attempt", "effects": [{"op": "actor.flag", "params": {"key": "left_no_trace", "value": true}, "label": "No trace left"}]}, {}, {"sleight": 1}))
	result.append(_talent("core.field_engineer", "Field Engineer", "Substitute an authored consumable for a required tool on a Technology or Craft action. The improvised repair expires at scene end.", "field_engineer",
		{"skills": ["technology", "craft"], "uses_per_scene": 1}, {}, {"technology": 1}))
	result.append(_talent("core.steady_voice", "Steady Voice", "Spend an action to remove 2 strain from a willing ally who can hear you after a fear setback. Once per scene.", "steady_voice",
		{"strain_removed": 2, "uses_per_scene": 1}, {"empathy": 3}, {}))
	result.append(_talent("core.bargain_maker", "Bargain Maker", "On a strong success with Influence, take a listed lesser concession in place of the strong benefit.", "bargain_maker",
		{"skills": ["influence"], "uses_per_scene": 1}, {}, {"influence": 1}))
	result.append(_talent("core.trail_reader", "Trail Reader", "On a success with Survival or Investigation, also learn one permitted fact the evidence supports. Once per scene.", "trail_reader",
		{"skills": ["survival", "investigation"], "uses_per_scene": 1}, {}, {"survival": 1}))
	return result


func _talent(id: String, display_name: String, description: String, hook_id: String, parameters: Dictionary, facets: Dictionary, skills: Dictionary) -> FacetsTalentResource:
	var talent := FacetsTalentResource.new()
	talent.id = id
	talent.display_name = display_name
	talent.description = description
	talent.hook_id = hook_id
	talent.parameters = parameters
	talent.prerequisite_facets = facets
	talent.prerequisite_skills = skills
	talent.usage_scope = "per_scene"
	talent.uses = int(parameters.get("uses_per_scene", 1))
	talent.package = "core"
	return talent


func _archetypes() -> Array[FacetsArchetypeResource]:
	var result: Array[FacetsArchetypeResource] = []
	result.append(_archetype("core.archetype.courier", "Courier", "Fast, quiet and hard to pin down.",
		{"force": 2, "agility": 4, "cunning": 3, "empathy": 2, "tenacity": 3, "sense": 4},
		{"athletics": 2, "stealth": 2, "survival": 2, "influence": 1, "investigation": 1, "technology": 1, "sleight": 1, "medicine": 1, "fighting": 1},
		["core.trail_reader", "core.quiet_hands"]))
	result.append(_archetype("core.archetype.investigator", "Investigator", "Patient, observant, relentless about evidence.",
		{"force": 2, "agility": 2, "cunning": 4, "empathy": 3, "tenacity": 3, "sense": 4},
		{"investigation": 2, "technology": 2, "influence": 2, "stealth": 1, "medicine": 1, "survival": 1, "sleight": 1, "athletics": 1, "performance": 1},
		["core.second_look", "core.trail_reader"]))
	result.append(_archetype("core.archetype.mediator", "Mediator", "Reads the room and keeps people talking.",
		{"force": 2, "agility": 2, "cunning": 3, "empathy": 4, "tenacity": 3, "sense": 4},
		{"influence": 2, "performance": 2, "investigation": 2, "medicine": 2, "survival": 1, "stealth": 1, "athletics": 1, "technology": 1},
		["core.bargain_maker", "core.steady_voice"]))
	result.append(_archetype("core.archetype.protector", "Protector", "Stands between danger and the people who matter.",
		{"force": 4, "agility": 3, "cunning": 2, "empathy": 3, "tenacity": 4, "sense": 2},
		{"fighting": 2, "athletics": 2, "medicine": 2, "survival": 2, "influence": 1, "marksmanship": 1, "investigation": 1, "craft": 1},
		["core.steady_voice", "core.trail_reader"]))
	result.append(_archetype("core.archetype.tinkerer", "Tinkerer", "Fixes, bypasses and improvises with whatever is at hand.",
		{"force": 2, "agility": 3, "cunning": 4, "empathy": 2, "tenacity": 3, "sense": 4},
		{"technology": 2, "craft": 2, "investigation": 2, "sleight": 2, "stealth": 1, "medicine": 1, "athletics": 1, "survival": 1},
		["core.field_engineer", "core.quiet_hands"]))
	return result


func _archetype(id: String, display_name: String, description: String, facets: Dictionary, skills: Dictionary, talents: Array[String]) -> FacetsArchetypeResource:
	var archetype := FacetsArchetypeResource.new()
	archetype.id = id
	archetype.display_name = display_name
	archetype.description = description
	archetype.facets = facets
	archetype.skills = skills
	archetype.talents = talents
	return archetype
