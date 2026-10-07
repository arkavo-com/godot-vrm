extends FacetsTestCase
## C01-C04: optional zone combat and the two combat talents.

const W := preload("res://tests/framework/test_world.gd")
const WEAPONS := "res://addons/facets_combat/content/weapons/%s.tres"

var registry: FacetsRegistry


func before_each() -> void:
	registry = FacetsRegistry.core()
	assert_ok(FacetsCombat.register(registry), "combat pack registers")


func _weapon(name: String) -> Dictionary:
	return (load(WEAPONS % name) as FacetsWeaponResource).to_dict()


func _actor(actor_id: String) -> FacetsActorState:
	var builds := {
		"bex": {"facets": {"force": 2, "agility": 4, "cunning": 3, "empathy": 2, "tenacity": 3, "sense": 3}, "skills": {"fighting": 2, "marksmanship": 2, "athletics": 1}, "talents": []},
		"cal": {"facets": {"force": 4, "agility": 3, "cunning": 2, "empathy": 2, "tenacity": 3, "sense": 4}, "skills": {"fighting": 2, "marksmanship": 2, "athletics": 2}, "talents": []},
		"ana": {"facets": {"force": 4, "agility": 3, "cunning": 2, "empathy": 3, "tenacity": 4, "sense": 2}, "skills": {"fighting": 2, "athletics": 2, "medicine": 2}, "talents": ["combat.bodyguard", "combat.last_reserve"]},
		"dan": {"facets": {"force": 3, "agility": 2, "cunning": 2, "empathy": 3, "tenacity": 3, "sense": 3}, "skills": {"fighting": 1, "athletics": 1, "medicine": 2}, "talents": []},
	}
	var state := W.actor(actor_id, actor_id.capitalize(), builds[actor_id])
	if actor_id == "ana" or actor_id == "dan":
		state.items = {"item.med_kit": 1}
	return state


func _zones() -> FacetsZoneMap:
	return FacetsZoneMap.from_dict({
		"a": {"adjacent": ["b"], "visible": ["c"]},
		"b": {"adjacent": ["a", "c"], "cover": true},
		"c": {"adjacent": ["b"], "visible": ["a"]},
		"d": {"adjacent": [], "blocked": ["a"]},
	})


## [param setup]: actor_id -> {zone, weapon name, armor, ammo, harm, strain, overwhelmed}
func _encounter(setup: Dictionary, dice: Array, options: Dictionary = {}) -> FacetsEncounter:
	var actors: Array = []
	var config := {}
	for actor_id in setup:
		var spec: Dictionary = setup[actor_id]
		var state := _actor(actor_id)
		var txn := FacetsTxn.begin(_holder(state))
		if spec.has("harm"):
			txn.add_harm(actor_id, int(spec["harm"]))
			txn.sync_harm_conditions(actor_id)
		if bool(spec.get("overwhelmed", false)):
			txn.add_strain(actor_id, state.strain_capacity())
		if spec.has("unwilling"):
			state.flags["unwilling"] = true
		if spec.has("items"):
			state.items = spec["items"]
		actors.append(state)
		config[actor_id] = {"zone": spec["zone"], "weapon": _weapon(spec.get("weapon", "knife")), "armor": int(spec.get("armor", 0)), "ammo": spec.get("ammo", {})}
	var reply := FacetsEncounter.create(registry, _zones(), actors, config, FacetsDiceSource.fixed(dice), options)
	return assert_ok(reply, "encounter")


func _holder(state: FacetsActorState) -> FacetsWorldSnapshot:
	var world := FacetsWorldSnapshot.new()
	world.add_actor(state)
	return world


func _finish_round(encounter: FacetsEncounter) -> void:
	var start_round := encounter.round
	var guard := 0
	while encounter.round == start_round and guard < 10:
		guard += 1
		encounter.end_turn(encounter.current_actor())


# --- C01 ----------------------------------------------------------------------------

func test_c01_initiative_ties_by_actor_id() -> void:
	var encounter := _encounter({"dan": {"zone": "a"}, "ana": {"zone": "a"}, "cal": {"zone": "a"}, "bex": {"zone": "a"}}, [])
	assert_eq(encounter.order, ["bex", "cal", "ana", "dan"], "Agility+Sense desc, ties by ID")
	assert_eq(encounter.current_actor(), "bex")
	assert_error(encounter.move("cal", "b"), FacetsError.NOT_AUTHORIZED, "not cal's turn")


func test_c01_one_move_and_action_as_second_move() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}}, [])
	assert_ok(encounter.move("bex", "b"))
	var second: Dictionary = assert_ok(encounter.move("bex", "c"))
	assert_true(bool(second["uses_action"]), "second move spends the action")
	assert_error(encounter.move("bex", "b"), FacetsError.ALREADY_USED, "no third move")
	assert_error(encounter.attack("bex", "cal", "slash"), FacetsError.ALREADY_USED, "action already spent")
	assert_ok(encounter.end_turn("bex"))
	assert_error(encounter.move("cal", "c"), FacetsError.INELIGIBLE, "not adjacent")


func test_c01_heavy_weapon_turn_budget() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a", "weapon": "sledgehammer"}, "dan": {"zone": "b"}}, [[1, 1]])
	encounter.end_turn("bex")
	assert_ok(encounter.move("cal", "b"))
	assert_error(encounter.attack("cal", "dan", "swing"), FacetsError.INELIGIBLE, "heavy: no attack after moving")
	_finish_round(encounter)
	encounter.end_turn("bex")
	assert_eq(encounter.current_actor(), "cal")
	assert_ok(encounter.attack("cal", "dan", "swing"))
	assert_error(encounter.move("cal", "a"), FacetsError.INELIGIBLE, "heavy: no move after attacking")


func test_c01_reaction_once_per_round_and_refresh() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}, "ana": {"zone": "a", "armor": 1}, "dan": {"zone": "a"}}, [[6, 6], [6, 6]])
	assert_true(encounter.can_react("ana"), "reaction available in the first round")
	var hit: Dictionary = assert_ok(encounter.attack("bex", "cal", "slash", {"interceptor_id": "ana"}))
	assert_eq(hit["intercepted_by"], "ana")
	assert_false(encounter.can_react("ana"), "reaction spent")
	encounter.end_turn("bex")
	assert_error(encounter.attack("cal", "bex", "slash", {"interceptor_id": "ana"}), FacetsError.INELIGIBLE, "one reaction per round")
	_finish_round(encounter)
	assert_eq(encounter.round, 2)
	assert_true(encounter.can_react("ana"), "refreshed next round")
	assert_ok(encounter.attack("bex", "cal", "slash", {"interceptor_id": "ana"}))


# --- C02 ----------------------------------------------------------------------------

func test_c02_range_line_of_sight_and_ammo() -> void:
	assert_error(_encounter({"bex": {"zone": "a"}, "cal": {"zone": "b"}}, [[3, 3]]).attack("bex", "cal", "slash"), FacetsError.INELIGIBLE, "close needs same zone")
	assert_ok(_encounter({"bex": {"zone": "a", "weapon": "pistol", "ammo": {"ammo.9mm": 3}}, "cal": {"zone": "b"}}, [[3, 3]]).attack("bex", "cal", "snap"), "ranged hits adjacent")
	assert_error(_encounter({"bex": {"zone": "a", "weapon": "pistol", "ammo": {"ammo.9mm": 3}}, "cal": {"zone": "c"}}, [[3, 3]]).attack("bex", "cal", "snap"), FacetsError.INELIGIBLE, "ordinary range stops at adjacent")
	assert_ok(_encounter({"bex": {"zone": "a", "weapon": "rifle", "ammo": {"ammo.rifle": 1}}, "cal": {"zone": "c"}}, [[3, 3]]).attack("bex", "cal", "aim"), "long range reaches distant visible")
	assert_error(_encounter({"bex": {"zone": "a", "weapon": "rifle", "ammo": {"ammo.rifle": 1}}, "cal": {"zone": "d"}}, [[3, 3]]).attack("bex", "cal", "aim"), FacetsError.INELIGIBLE, "needs line of sight")
	assert_error(_encounter({"bex": {"zone": "a", "weapon": "pistol"}, "cal": {"zone": "b"}}, [[3, 3]]).attack("bex", "cal", "snap"), FacetsError.INELIGIBLE, "needs compatible ammunition")
	assert_error(_encounter({"bex": {"zone": "a", "weapon": "pistol", "ammo": {"ammo.rifle": 5}}, "cal": {"zone": "b"}}, [[3, 3]]).attack("bex", "cal", "snap"), FacetsError.INELIGIBLE, "incompatible ammunition")


func test_c02_cover_defend_and_cap() -> void:
	var encounter := _encounter({"bex": {"zone": "a", "weapon": "pistol", "ammo": {"ammo.9mm": 3}}, "cal": {"zone": "b"}, "dan": {"zone": "c"}}, [[4, 4], [4, 4]])
	var shot: Dictionary = assert_ok(encounter.attack("bex", "cal", "snap"))
	assert_eq(int(shot["defense"]), 14, "7 + agility 3 + athletics 2 + cover 2")
	assert_eq(int(shot["defense_modifier"]), 2, "cover counted once")
	encounter.end_turn("bex")
	assert_ok(encounter.defend("cal"))
	_finish_round(encounter)
	var capped: Dictionary = assert_ok(encounter.attack("bex", "cal", "snap"))
	assert_eq(int(capped["defense_modifier"]), 3, "cover +2 and defend +2 capped at +3")
	assert_eq(int(capped["defense"]), 15)
	encounter.end_turn("bex")
	assert_false(bool(encounter.state("cal")["defending"]), "defend expires at the defender's next turn")
	var close := _encounter({"bex": {"zone": "b"}, "cal": {"zone": "b"}}, [[3, 3]])
	var melee: Dictionary = assert_ok(close.attack("bex", "cal", "slash"))
	assert_eq(int(melee["defense"]), 12, "close defense 7 + agility + fighting; cover does not apply")


func test_c02_harm_armor_and_no_costly_strike() -> void:
	var light := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a", "armor": 1}}, [[6, 5], [3, 3]])
	var strong: Dictionary = assert_ok(light.attack("bex", "cal", "slash"))
	assert_eq(strong["band"], "strong_success")
	assert_eq(int(strong["harm"]), 2, "light 1 + strong 1")
	assert_eq(int(strong["applied"]), 1, "armor 1 subtracts")
	_finish_round(light)
	var plain: Dictionary = assert_ok(light.attack("bex", "cal", "slash"))
	assert_eq(plain["band"], "success")
	assert_eq(int(plain["applied"]), 0, "armor reduces to a minimum of zero")
	var heavy := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a", "weapon": "sledgehammer"}, "ana": {"zone": "a", "armor": 2}}, [[4, 4]])
	heavy.end_turn("bex")
	var smash: Dictionary = assert_ok(heavy.attack("cal", "ana", "swing"))
	assert_eq(int(smash["harm"]), 3, "heavy 3")
	assert_eq(int(smash["applied"]), 1)
	var miss := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}}, [[2, 3]])
	var near: Dictionary = assert_ok(miss.attack("bex", "cal", "slash"))
	assert_eq(int(near["total"]) - int(near["defense"]), -1)
	assert_eq(near["band"], "failure", "standard strikes have no costly success")
	assert_false(bool(near["hit"]))


# --- C03 ----------------------------------------------------------------------------

func test_c03_injury_and_incapacity() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a", "weapon": "baton"}, "dan": {"zone": "a"}}, [[4, 4], [3, 3], [4, 4]])
	encounter.end_turn("bex")
	var hit: Dictionary = assert_ok(encounter.attack("cal", "dan", "strike"))
	assert_eq(int(hit["applied"]), 3, "standard 2 + strong 1")
	assert_true(encounter.actor("dan").has_condition(FacetsRules.CONDITION_INJURED), "harm 3 gives Injured")
	encounter.end_turn("cal")
	assert_eq(encounter.current_actor(), "dan")
	var weak: Dictionary = assert_ok(encounter.attack("dan", "bex", "slash"))
	assert_eq(int(weak["total"]), 3 + 3 + 2 + 1 - 1, "Injured: -1 to physical checks")
	_finish_round(encounter)
	encounter.end_turn("bex")
	assert_ok(encounter.attack("cal", "dan", "strike"))
	assert_true(encounter.actor("dan").has_condition(FacetsRules.CONDITION_INCAPACITATED), "harm 6 gives Incapacitated")
	assert_false(encounter.can_act("dan"))
	encounter.end_turn("cal")
	assert_eq(encounter.current_actor(), "bex", "Incapacitated actor's turn is skipped")


func test_c03_medicine_limits() -> void:
	var encounter := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 4}}, [[4, 4], [6, 5]])
	var healed: Dictionary = assert_ok(encounter.medicine("ana", "dan"))
	assert_eq(healed["band"], "success")
	assert_eq(int(healed["harm_removed"]), 1)
	assert_eq(encounter.actor("dan").harm, 3)
	_finish_round(encounter)
	assert_error(encounter.medicine("ana", "dan"), FacetsError.ALREADY_USED, "one benefit per patient per encounter")
	var strong := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 4}}, [[6, 5]])
	assert_eq(int((strong.medicine("ana", "dan").value as Dictionary)["harm_removed"]), 2, "strong removes 2")
	assert_false(strong.actor("dan").has_condition(FacetsRules.CONDITION_INJURED), "below 3 harm clears Injured")
	var near := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 4}}, [[3, 3]])
	var miss: Dictionary = assert_ok(near.medicine("ana", "dan"))
	assert_eq(int(miss["total"]), 10, "margin -1")
	assert_eq(miss["band"], "failure", "no costly success")
	assert_eq(near.actor("dan").harm, 4)
	assert_error(_encounter({"ana": {"zone": "a", "items": {}}, "dan": {"zone": "a", "harm": 2}}, [[6, 6]]).medicine("ana", "dan"), FacetsError.INELIGIBLE, "needs supplies")
	assert_error(_encounter({"ana": {"zone": "a"}, "dan": {"zone": "b", "harm": 2}}, [[6, 6]]).medicine("ana", "dan"), FacetsError.INELIGIBLE, "same zone")
	assert_error(_encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 2, "unwilling": true}}, [[6, 6]]).medicine("ana", "dan"), FacetsError.INELIGIBLE, "willing patient")


func test_c03_stabilization_and_recovery() -> void:
	var encounter := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 6}}, [[4, 4]])
	assert_false(encounter.can_act("dan"))
	var stabilized: Dictionary = assert_ok(encounter.medicine("ana", "dan"))
	assert_true(bool(stabilized["stabilized"]))
	assert_eq(encounter.actor("dan").harm, 5)
	assert_true(encounter.actor("dan").has_condition(FacetsRules.CONDITION_INCAPACITATED), "stabilized actor still cannot act this encounter")
	encounter.end_turn("ana")
	assert_eq(encounter.current_actor(), "ana", "dan skipped while stabilized")
	var outcomes: Dictionary = assert_ok(encounter.end_encounter())
	assert_false(encounter.actor("dan").has_condition(FacetsRules.CONDITION_INCAPACITATED), "acts again after the encounter with harm below 6")
	assert_false(bool(outcomes["dan"]["dead"]))
	# Journey state: harm persists into the session; full rest removes 2.
	var world := FacetsWorldSnapshot.new()
	world.scene_id = "fight"
	world.add_actor(_actor("dan"))
	var holder := _holder(world.actor("dan"))
	var session: FacetsSession = FacetsSession.create(registry, world, {}).value
	assert_ok(session.apply_host_effects("dan", [{"op": "actor.harm", "params": {"amount": 5}}], "fight"))
	assert_true(session.actor_state("dan").has_condition(FacetsRules.CONDITION_INJURED))
	assert_ok(session.grant_opportunity("rest", "secure_rest"))
	assert_ok(session.full_rest("dan", "rest"))
	assert_eq(session.actor_state("dan").harm, 3, "full rest removes 2 harm")
	assert_true(holder != null)


func test_c03_death_only_under_lethal_policy() -> void:
	var gentle := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 7}}, [])
	assert_false(bool((gentle.end_encounter().value as Dictionary)["dan"]["dead"]), "no death by default")
	assert_true(gentle.actor("dan").has_condition(FacetsRules.CONDITION_INCAPACITATED), "still incapacitated at 6+")
	var lethal := _encounter({"ana": {"zone": "a"}, "dan": {"zone": "a", "harm": 7}}, [], {"lethal": true})
	assert_true(bool((lethal.end_encounter().value as Dictionary)["dan"]["dead"]), "declared lethal policy")


func test_c03_journey_effects_round_trip() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a", "weapon": "baton"}}, [[6, 6]])
	assert_ok(encounter.attack("bex", "cal", "slash", {"push": true}))
	encounter.end_encounter()
	var effects := encounter.journey_effects("bex")
	assert_eq(effects.size(), 1, "push strain written back")
	assert_eq(effects[0]["op"], "actor.strain")
	assert_eq(encounter.journey_effects("cal")[0]["op"], "actor.harm")
	var world := FacetsWorldSnapshot.new()
	world.add_actor(_actor("cal"))
	var session: FacetsSession = FacetsSession.create(registry, world, {}).value
	assert_ok(session.apply_host_effects("cal", encounter.journey_effects("cal"), "fight"))
	assert_eq(session.actor_state("cal").harm, encounter.actor("cal").harm)


# --- C04 ----------------------------------------------------------------------------

func test_c04_bodyguard_eligibility_and_armor() -> void:
	var encounter := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}, "ana": {"zone": "a", "armor": 2}, "dan": {"zone": "a"}}, [[6, 6], [1, 1]])
	assert_error(encounter.attack("bex", "cal", "slash", {"interceptor_id": "dan"}), FacetsError.NOT_APPLICABLE, "needs Bodyguard")
	assert_error(encounter.attack("bex", "cal", "slash", {"interceptor_id": "cal"}), FacetsError.UNKNOWN_ID, "target cannot intercept itself")
	assert_error(encounter.attack("bex", "cal", "slash", {"interceptor_id": "bex"}), FacetsError.UNKNOWN_ID)
	var hit: Dictionary = assert_ok(encounter.attack("bex", "cal", "slash", {"interceptor_id": "ana"}))
	assert_eq(hit["recipient_id"], "ana")
	assert_eq(int(hit["armor"]), 2, "interceptor's armor applies")
	assert_eq(int(hit["applied"]), 0)
	assert_eq(encounter.actor("cal").harm, 0, "single redirect; the target takes nothing")
	var away := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}, "ana": {"zone": "b"}}, [[6, 6]])
	assert_error(away.attack("bex", "cal", "slash", {"interceptor_id": "ana"}), FacetsError.INELIGIBLE, "same zone only")
	var spent := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}, "ana": {"zone": "a", "overwhelmed": true}}, [[6, 6]])
	assert_error(spent.attack("bex", "cal", "slash", {"interceptor_id": "ana"}), FacetsError.INELIGIBLE, "Overwhelmed: no reactions")
	var miss := _encounter({"bex": {"zone": "a"}, "cal": {"zone": "a"}, "ana": {"zone": "a"}}, [[1, 1]])
	var whiff: Dictionary = assert_ok(miss.attack("bex", "cal", "slash", {"interceptor_id": "ana"}))
	assert_false(bool(whiff["hit"]))
	assert_true(miss.can_react("ana"), "no interception happens on a miss")


func test_c04_last_reserve_limits() -> void:
	var encounter := _encounter({"ana": {"zone": "a", "overwhelmed": true, "weapon": "baton"}, "dan": {"zone": "b"}}, [[6, 6], [6, 6]])
	assert_eq(encounter.current_actor(), "ana")
	assert_true(encounter.actor("ana").is_overwhelmed())
	assert_ok(encounter.move("ana", "b"))
	assert_error(encounter.attack("ana", "dan", "strike"), FacetsError.INELIGIBLE, "Overwhelmed: move or act, not both")
	assert_error(encounter.use_last_reserve("ana"), FacetsError.NOT_APPLICABLE, "declared at the start of the turn")
	_finish_round(encounter)
	assert_ok(encounter.use_last_reserve("ana"))
	assert_false(encounter.can_react("ana"), "reaction not restored")
	assert_ok(encounter.move("ana", "a"))
	assert_ok(encounter.move("ana", "b"), "normal turn: action may become a second move")
	_finish_round(encounter)
	assert_error(encounter.use_last_reserve("ana"), FacetsError.USAGE_LIMIT, "once per scene")
	var plain := _encounter({"dan": {"zone": "a", "overwhelmed": true}, "bex": {"zone": "a"}}, [])
	plain.end_turn("bex")
	assert_error(plain.use_last_reserve("dan"), FacetsError.NOT_APPLICABLE, "needs the talent")
	var down := _encounter({"ana": {"zone": "a", "overwhelmed": true, "harm": 6}, "dan": {"zone": "a"}}, [])
	assert_eq(down.current_actor(), "dan", "Incapacitated actor never gets a turn")
	assert_error(down.use_last_reserve("ana"), FacetsError.NOT_AUTHORIZED, "cannot bypass Incapacitated")


func test_c04_all_eight_source_talents_registered() -> void:
	var expected := ["combat.bodyguard", "combat.last_reserve", "core.bargain_maker", "core.field_engineer", "core.quiet_hands", "core.second_look", "core.steady_voice", "core.trail_reader"]
	assert_eq(registry.talent_ids(), expected)
	var core_only := FacetsRegistry.core()
	assert_eq(core_only.talent_ids().size(), 6, "core alone ships the six noncombat talents")
	var protector := FacetsBuild.from_dict(registry.get_archetype("core.archetype.protector")["build"])
	protector.talents = ["core.steady_voice", "combat.bodyguard"]
	assert_eq(FacetsValidator.validate_creation(protector, registry).size(), 0, "combat talents are valid starting picks once installed")
