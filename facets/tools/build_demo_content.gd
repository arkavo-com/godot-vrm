extends SceneTree
## Regenerates the Night Market demo Resources under
## examples/night_market/content/. Afterwards the .tres files are the
## authoring source (edit them in the inspector). Usage:
##   godot --headless --path . --script tools/build_demo_content.gd

const ROOT := "res://examples/night_market/content"


func _initialize() -> void:
	var failures := 0
	for sub in ["characters", "actions"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join(sub)))
	for character in _characters():
		failures += _save(character, "characters/%s.tres" % character.id.get_slice(".", 1))
	var pack := FacetsRulesPack.new()
	pack.pack_id = "examples.night_market"
	pack.version = "0.1.0"
	pack.dependencies = {"facets.core": "0.1.0"}
	pack.compatibility = "Night Market Delivery demo for FACETS 0.1.0."
	for action in _actions():
		failures += _save(action, "actions/%s.tres" % action.id.get_slice(".", 1))
		pack.actions.append(action)
	failures += _save(pack, "night_market_pack.tres")
	var registry := FacetsRegistry.core()
	var reply := registry.register_pack(pack)
	if not reply.ok:
		printerr("demo pack invalid: ", reply)
		failures += 1
	for character in _characters():
		if character.controller == "player":
			var errors := FacetsValidator.validate_character(character, registry)
			if not errors.is_empty():
				printerr("%s invalid: %s" % [character.id, errors])
				failures += 1
	print("build_demo_content: %s" % ("ok" if failures == 0 else "%d failures" % failures))
	quit(1 if failures > 0 else 0)


func _save(resource: Resource, relative: String) -> int:
	var path := ROOT.path_join(relative)
	var status := ResourceSaver.save(resource, path)
	if status != OK:
		printerr("could not save %s: %s" % [path, error_string(status)])
		return 1
	resource.take_over_path(path)
	return 0


static func op(op_id: String, params: Dictionary, label: String = "") -> FacetsOperationRef:
	return FacetsOperationRef.make(op_id, params, label)


static func ops(items: Array) -> Array[FacetsOperationRef]:
	var result: Array[FacetsOperationRef] = []
	for item in items:
		result.append(item)
	return result


func _character(id: String, display_name: String, controller: String, identity: Dictionary, facets: Dictionary, skills: Dictionary, talents: Array[String], items: Dictionary) -> FacetsCharacterResource:
	var character := FacetsCharacterResource.new()
	character.id = id
	character.display_name = display_name
	character.controller = controller
	character.identity = FacetsIdentityResource.from_dict(identity)
	character.facet_set = FacetsFacetSet.from_dict(facets)
	character.skills = skills
	character.talents = talents
	character.items = items
	return character


func _bond(other_id: String, trust: int, affinity: int) -> FacetsBondResource:
	var bond := FacetsBondResource.new()
	bond.other_id = other_id
	bond.trust = trust
	bond.affinity = affinity
	return bond


func _trigger(id: String, display_name: String, description: String, label: String, effects: Array[FacetsOperationRef]) -> FacetsIdentityTriggerResource:
	var trigger := FacetsIdentityTriggerResource.new()
	trigger.id = id
	trigger.display_name = display_name
	trigger.description = description
	trigger.disadvantage_label = label
	trigger.disadvantage_effects = effects
	return trigger


func _characters() -> Array[FacetsCharacterResource]:
	var result: Array[FacetsCharacterResource] = []
	var mara := _character("demo.mara_vale", "Mara Vale", "player",
		{"name": "Mara Vale", "drive": "Find the missing people from the night market", "code": "Never abandon a passenger", "hindrance": "Pursues disappearance leads despite urgent deliveries", "tell": "Touches the seal on her courier bag"},
		{"force": 2, "agility": 4, "cunning": 3, "empathy": 3, "tenacity": 2, "sense": 4},
		{"stealth": 2, "investigation": 2, "influence": 2, "technology": 2, "athletics": 1, "sleight": 1, "survival": 1, "medicine": 1},
		["core.second_look", "core.field_engineer"], {"tool.signal_kit": 1, "item.scrap_wire": 1})
	mara.bonds = [_bond("demo.iris_kade", 1, 1), _bond("npc.rook", 0, 1)]
	mara.identity_triggers = [_trigger("mara.passenger_lead", "Chase the disappearance lead",
		"The stranded passenger saw something. Stop and listen, even though the delivery window is closing.",
		"Miss the delivery window",
		ops([op("fact.set", {"fact_id": "fact.window_missed", "value": true}, "Delivery window missed"), op("world.clock_advance", {"amount": 2}, "Two hours pass")]))]
	result.append(mara)
	var iris := _character("demo.iris_kade", "Iris Kade", "player",
		{"name": "Iris Kade", "drive": "Keep the market's people safe", "code": "Talk first, always", "hindrance": "Cannot walk away from someone in pain", "tell": "Hums when she is nervous"},
		{"force": 2, "agility": 2, "cunning": 3, "empathy": 4, "tenacity": 4, "sense": 3},
		{"influence": 2, "medicine": 2, "performance": 2, "survival": 2, "investigation": 1, "athletics": 1, "fighting": 1, "craft": 1},
		["core.steady_voice", "core.bargain_maker"], {"item.med_kit": 1})
	iris.bonds = [_bond("demo.mara_vale", 2, 1)]
	iris.identity_triggers = [_trigger("iris.someone_in_pain", "Stop for someone in pain",
		"Someone nearby is hurt. Stop and treat them, whatever it costs your schedule.",
		"Lose an hour treating strangers",
		ops([op("world.clock_advance", {"amount": 1}, "An hour passes")]))]
	result.append(iris)
	var rook := _character("npc.rook", "Rook", "npc",
		{"name": "Rook", "drive": "Keep his post and his pension", "code": "Never open the fixer's office", "hindrance": "Owes the fixer money", "tell": "Jingles his keys"},
		{"force": 3, "agility": 3, "cunning": 2, "empathy": 2, "tenacity": 4, "sense": 4},
		{"fighting": 2, "influence": 2, "investigation": 2, "athletics": 2, "marksmanship": 2, "survival": 2},
		["core.trail_reader", "core.second_look"], {})
	result.append(rook)
	var tamsin := _character("npc.tamsin", "Tamsin", "npc",
		{"name": "Tamsin", "drive": "Get home", "code": "Tell the truth", "hindrance": "Terrified of the canal crews", "tell": "Clutches a torn ticket"},
		{"force": 2, "agility": 3, "cunning": 2, "empathy": 4, "tenacity": 3, "sense": 4},
		{"performance": 2, "survival": 2, "influence": 2, "investigation": 2, "athletics": 2, "medicine": 2},
		["core.trail_reader", "core.steady_voice"], {})
	result.append(tamsin)
	return result


func _approach(id: String, facet: String, skill: String, label: String) -> FacetsApproachResource:
	return FacetsApproachResource.make(id, facet, skill, label)


func _action(id: String, display_name: String, description: String, target: int) -> FacetsActionResource:
	var action := FacetsActionResource.new()
	action.id = id
	action.display_name = display_name
	action.description = description
	action.objective_id = id.replace("nm.", "nm.objective.")
	action.target = target
	return action


func _actions() -> Array[FacetsActionResource]:
	var result: Array[FacetsActionResource] = []
	var gate_scene := op("require.scene", {"scene_id": "nm.gate"}, "At the market gate")
	var at_street := op("require.actor_zone", {"zone_id": "street"}, "Still outside the market hall")

	var ask := _action("nm.ask_guard", "Ask Rook to open the side gate", "Talk the guard into letting you through the side gate before curfew.", 11)
	ask.approaches = [_approach("plead", "empathy", "influence", "Appeal to Rook's decency")]
	ask.requirements = ops([gate_scene, at_street, op("require.object_flag", {"object_id": "market_gate", "key": "open", "value": false}, "The side gate is still closed"), op("require.fact", {"fact_id": "fact.rook_alerted", "value": true, "negate": true}, "Rook has not raised the alarm")])
	ask.relationship = {"other_id": "npc.rook", "dimension": "trust"}
	ask.allows_costly_success = true
	ask.costly_options = [FacetsCostOption.make("favor", "Promise Rook a favor later", ops([op("bond.add_obligation", {"other_id": "npc.rook", "obligation": "Owes Rook a favor"}, "You owe Rook a favor")]))]
	ask.success_effects = ops([op("object.set_flag", {"object_id": "market_gate", "key": "open", "value": true}, "Rook unlocks the side gate"), op("actor.zone", {"zone_id": "hall"}, "You slip into the market hall")])
	ask.failure_effects = ops([op("fact.set", {"fact_id": "fact.rook_alerted", "value": true, "label": "Rook raised the alarm"}, "Rook raises the alarm"), op("world.counter_add", {"counter_id": "patrol", "amount": 1}, "The patrol is called")])
	ask.strong_benefits = [
		FacetsBenefitOption.make("route", "Rook mentions the patrol route", ops([op("fact.reveal", {"fact_id": "fact.patrol_route"}, "You learn the patrol route")])),
		FacetsBenefitOption.make("vouch", "Rook will vouch for you later", ops([op("bond.adjust", {"other_id": "npc.rook", "dimension": "trust", "amount": 1}, "Rook trusts you more")])),
	]
	ask.default_benefit_id = "route"
	ask.lesser_concessions = [FacetsBenefitOption.make("pass", "A one-time side pass", ops([op("actor.item_add", {"item_id": "item.side_pass", "amount": 1}, "You get a side pass")]))]
	ask.success_stakes = "The side gate opens and you are inside."
	ask.failure_stakes = "Rook raises the alarm and the patrol is called."
	ask.clock_cost = 1
	ask.tags = ["social", "route"]
	result.append(ask)

	var bypass := _action("nm.bypass_controller", "Bypass the service door controller", "Splice into the service door's controller and open it.", 13)
	bypass.approaches = [_approach("tech", "cunning", "technology", "Work the controller")]
	bypass.requirements = ops([gate_scene, at_street, op("require.accessible_controller", {"object_id": "controller"}, "The controller is reachable and not locked down"), op("require.object_flag", {"object_id": "service_door", "key": "open", "value": false}, "The service door is still closed")])
	bypass.required_tools = ["tool.signal_kit"]
	bypass.consumable_substitutes = ["item.scrap_wire"]
	bypass.allows_costly_success = true
	bypass.costly_options = [FacetsCostOption.make("trace", "Leave a trace in the market grid", ops([op("world.mark_trace", {"trace_id": "fact.grid_trace", "label": "A trace in the market grid"}, "You leave a trace in the grid")]))]
	bypass.success_effects = ops([op("object.set_flag", {"object_id": "service_door", "key": "open", "value": true}, "The service door opens"), op("actor.zone", {"zone_id": "hall"}, "You step into the market hall")])
	bypass.failure_effects = ops([op("world.counter_add", {"counter_id": "patrol", "amount": 1}, "The patrol advances"), op("object.set_flag", {"object_id": "controller", "key": "locked", "value": true}, "The controller locks down")])
	bypass.strong_benefits = [
		FacetsBenefitOption.make("silent", "Silent entry", ops([op("actor.flag", {"key": "silent_entry", "value": true}, "Nobody noticed you")])),
		FacetsBenefitOption.make("log", "Copy the access log", ops([op("fact.reveal", {"fact_id": "fact.access_log"}, "You copy the access log")])),
	]
	bypass.default_benefit_id = "silent"
	bypass.success_stakes = "The service door opens."
	bypass.failure_stakes = "The patrol advances and the controller locks down."
	bypass.clock_cost = 1
	bypass.tags = ["technical", "route"]
	result.append(bypass)

	var roof := _action("nm.rooftop_entry", "Climb in through the roof hatch", "Scale the stalls and drop in through the roof hatch.", 13)
	roof.approaches = [_approach("climb", "agility", "athletics", "Climb and drop")]
	roof.requirements = ops([gate_scene, at_street, op("require.object_flag", {"object_id": "roof_hatch", "key": "reachable", "value": true}, "The roof hatch is reachable"), op("require.no_condition", {"condition_id": "core.injured"}, "Not injured")])
	roof.allows_costly_success = true
	roof.costly_options = [FacetsCostOption.make("strain", "Wrench your shoulder (2 strain)", ops([op("actor.strain", {"amount": 2}, "You wrench your shoulder")]))]
	roof.success_effects = ops([op("actor.zone", {"zone_id": "hall"}, "You drop into the market hall")])
	roof.failure_effects = ops([op("actor.strain", {"amount": 2}, "You fall hard"), op("world.counter_add", {"counter_id": "patrol", "amount": 1}, "The noise draws the patrol"), op("object.set_flag", {"object_id": "roof_hatch", "key": "reachable", "value": false}, "The stack of crates collapses")])
	roof.strong_benefits = [FacetsBenefitOption.make("view", "Spot the courier route from above", ops([op("fact.reveal", {"fact_id": "fact.rooftop_view"}, "You see where the couriers go")]))]
	roof.success_stakes = "You get inside unseen."
	roof.failure_stakes = "You fall (2 strain), the patrol hears, and the route collapses."
	roof.fear = true
	roof.clock_cost = 1
	roof.tags = ["physical", "route"]
	result.append(roof)

	var help := _action("nm.help_passenger", "Help the stranded passenger", "Tamsin is hurt and shaking. Patch her up and get her somewhere safe.", 11)
	help.approaches = [_approach("treat", "empathy", "medicine", "Treat and reassure")]
	help.requirements = ops([gate_scene, op("require.object_flag", {"object_id": "passenger", "key": "helped", "value": false}, "Tamsin still needs help")])
	help.allows_costly_success = true
	help.costly_options = [FacetsCostOption.make("time", "It takes an extra hour", ops([op("world.clock_advance", {"amount": 1}, "An hour passes")]))]
	help.success_effects = ops([op("object.set_flag", {"object_id": "passenger", "key": "helped", "value": true}, "Tamsin is safe")])
	help.failure_effects = ops([op("actor.strain", {"amount": 1}, "Her panic gets to you")])
	help.fear = true
	help.success_stakes = "Tamsin is safe and will make it to the clinic."
	help.failure_stakes = "Her panic gets to you (1 strain)."
	help.clock_cost = 1
	help.retry_policy = "lock_until_change"
	help.tags = ["social"]
	result.append(help)

	var deliver := _action("nm.deliver_package", "Deliver the sealed package", "Hand the package to the clinic's night doctor inside the hall.", 11)
	deliver.approaches = [_approach("hand_over", "empathy", "influence", "Hand it over")]
	deliver.requirements = ops([gate_scene, op("require.actor_zone", {"zone_id": "hall"}, "Inside the market hall"), op("require.object_flag", {"object_id": "package", "key": "delivered", "value": false}, "Not yet delivered")])
	deliver.difficulty_kind = "routine"
	deliver.success_effects = ops([op("object.set_flag", {"object_id": "package", "key": "delivered", "value": true}, "Package delivered")])
	deliver.success_stakes = "Routine: the delivery is made."
	deliver.retry_policy = "repeatable"
	result.append(deliver)

	var clinic := op("require.scene", {"scene_id": "nm.clinic"}, "At the clinic")
	var slip := _action("nm.slip_away", "Slip out past the fixer's watchers", "Leave the clinic without being followed.", 11)
	slip.approaches = [_approach("sneak", "agility", "stealth", "Blend into the crowd")]
	slip.requirements = ops([clinic])
	slip.modifiers = [{"source_id": "fact.grid_trace", "factor_id": "watch.grid_trace", "scope": "situational", "value": -1, "label": "The grid trace put watchers on you", "when": {"op": "require.fact", "params": {"fact_id": "fact.grid_trace", "value": true}}}]
	slip.allows_costly_success = true
	slip.costly_options = [FacetsCostOption.make("seen", "Someone glimpses your face", ops([op("fact.set", {"fact_id": "fact.face_seen", "value": true, "label": "Your face was seen"}, "Someone saw your face")]))]
	slip.success_effects = ops([op("actor.zone", {"zone_id": "canal"}, "You reach the canal path unseen")])
	slip.failure_effects = ops([op("actor.strain", {"amount": 1}, "You are followed for a while")])
	slip.fear = true
	slip.success_stakes = "You reach the canal path unseen."
	slip.failure_stakes = "You are followed (1 strain)."
	result.append(slip)

	var lead := _action("nm.follow_lead", "Follow the passenger's lead", "Tamsin saw a courier dragged toward the canal. Find where.", 13)
	lead.approaches = [_approach("search", "sense", "investigation", "Search for signs"), _approach("track", "sense", "survival", "Track the route")]
	lead.requirements = ops([clinic, op("require.knows_fact", {"fact_id": "fact.passenger_lead"}, "Know the passenger's lead")])
	lead.success_effects = ops([op("fact.reveal", {"fact_id": "fact.canal_lead"}, "You find the canal crew's drop point"), op("actor.accomplishment", {"text": "Found the canal drop point"}, "Accomplishment recorded")])
	lead.failure_effects = ops([op("world.clock_advance", {"amount": 1}, "The trail goes cold for an hour")])
	lead.alternate_evidence_sources = ["evidence.bag_seal", "evidence.cctv"]
	lead.revealable_facts = ["fact.canal_footprints"]
	lead.success_stakes = "You find where the courier was taken."
	lead.failure_stakes = "The trail goes cold for an hour."
	result.append(lead)

	var calm := _action("nm.calm_doctor", "Settle things with the night doctor", "Make amends with the clinic's doctor about the delivery.", 11)
	calm.approaches = [_approach("talk", "empathy", "influence", "Talk it through")]
	calm.requirements = ops([clinic, op("require.fact", {"fact_id": "fact.doctor_calm", "value": true, "negate": true}, "The doctor is not yet settled")])
	calm.modifiers = [{"source_id": "package.late", "factor_id": "delivery.late", "scope": "situational", "value": -1, "label": "The package arrived late", "when": {"op": "require.object_flag", "params": {"object_id": "package", "key": "late", "value": true}}}]
	calm.success_effects = ops([op("fact.set", {"fact_id": "fact.doctor_calm", "value": true, "label": "The doctor is on your side"}, "The doctor is on your side")])
	calm.failure_effects = ops([op("actor.strain", {"amount": 1}, "Harsh words")])
	calm.success_stakes = "The doctor will help you next time."
	calm.failure_stakes = "Harsh words (1 strain)."
	result.append(calm)
	return result
