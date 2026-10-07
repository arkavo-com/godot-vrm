extends FacetsTestCase
## T01-T10 at the pure-function level: creation, arithmetic, probability,
## modifiers, opposed targets, push/Resolve bands and Overwhelmed.

var registry: FacetsRegistry


func before_each() -> void:
	registry = FacetsRegistry.core()


func _check(facet: int, skill: int, target: int, costly: bool) -> FacetsCheckInput:
	return FacetsCheckInput.make(facet, skill, target, costly)


# --- T01 creation --------------------------------------------------------------

func test_t01_creation_fixture_cases() -> void:
	var data: Dictionary = fixture("rules/creation_cases.json")
	for case in data["cases"]:
		var build := FacetsBuild.from_dict(case["build"])
		var errors := FacetsValidator.validate_creation(build, registry)
		assert_eq(errors.is_empty(), bool(case["valid"]), "%s validity (%s)" % [case["name"], str(errors)])
		for code in case["expected_errors"]:
			assert_has_error(errors, code, case["name"])


func test_t01_standard_totals_and_caps() -> void:
	var build := FacetsBuild.baseline()
	assert_eq(build.facet_total(), 12, "baseline facets")
	var errors := FacetsValidator.validate_creation(build, registry)
	assert_has_error(errors, FacetsError.BUDGET, "baseline underspends")
	for facet_id in ["agility", "sense", "cunning"]:
		build.facets[facet_id] = 4
	assert_eq(build.facet_total(), 18)
	assert_false(FacetsValidator.validate_creation(build, registry).any(func(e: FacetsError) -> bool: return e.field_path.contains("facets")), "18 with caps respected")


func test_t01_core_pack_contents() -> void:
	assert_eq(registry.skill_ids().size(), 12, "twelve core skills")
	for skill_id in FacetsRules.CORE_SKILLS:
		assert_true(registry.has_skill(skill_id), "skill %s" % skill_id)
	var noncombat := ["core.second_look", "core.quiet_hands", "core.field_engineer", "core.steady_voice", "core.bargain_maker", "core.trail_reader"]
	for talent_id in noncombat:
		assert_true(registry.has_talent(talent_id), "talent %s" % talent_id)
	assert_true(registry.has_condition(FacetsRules.CONDITION_OVERWHELMED))
	for archetype_id in registry.archetype_ids():
		var build := FacetsBuild.from_dict(registry.get_archetype(archetype_id)["build"])
		assert_eq(FacetsValidator.validate_creation(build, registry).size(), 0, "archetype %s legal" % archetype_id)
	assert_eq(registry.archetype_ids().size(), 5, "five presets")


func test_t01_genre_skill_shares_budget() -> void:
	assert_ok(registry.add_skill({"id": "genre.netrunning", "display_name": "Netrunning", "genre": true}))
	var build := FacetsBuild.from_dict({
		"facets": {"force": 2, "agility": 4, "cunning": 3, "empathy": 3, "tenacity": 2, "sense": 4},
		"skills": {"stealth": 2, "investigation": 2, "influence": 2, "technology": 2, "athletics": 1, "sleight": 1, "survival": 1, "genre.netrunning": 2},
		"talents": ["core.second_look", "core.field_engineer"],
	})
	assert_has_error(FacetsValidator.validate_creation(build, registry), FacetsError.BUDGET, "13 points including genre skill")
	build.skills["genre.netrunning"] = 1
	assert_eq(FacetsValidator.validate_creation(build, registry).size(), 0, "12 points including genre skill")


# --- T02 probability -------------------------------------------------------------

func test_t02_calibration_rows_match_reference() -> void:
	var data: Dictionary = fixture("rules/probability_calibration.json")
	var rows: Array = data["rows"]
	assert_true(rows.size() > 400, "calibration rows present")
	for row in rows:
		var check := _check(row["facet"], row["skill"], row["target"], row["allows_costly_success"])
		var odds := FacetsProbability.enumerate_sum(check, int(row["modifier_sum"]), bool(row["push"]), bool(row["resolve"]))
		var total := 0
		for band in FacetsRules.ODDS_BANDS:
			total += odds.count(band)
		if not assert_eq(total, 36, "36 outcomes"):
			return
		if not assert_eq(odds.counts, row["expected"], "row %s" % FacetsJson.canonical(row)):
			return


func test_t02_spec_pitch_correction_fixture() -> void:
	var data: Dictionary = fixture("rules/probability_calibration.json")
	var spec: Dictionary = data["spec_fixture"]
	var with_costly := FacetsProbability.enumerate(_check(5, 3, 14, true), FacetsAdjustments.new())
	assert_eq(with_costly.counts, spec["with_costly"])
	assert_eq(with_costly.fraction(FacetsRules.BAND_FAILURE), "3/36")
	assert_eq(with_costly.fraction(FacetsRules.BAND_COSTLY_OFFER), "7/36")
	assert_eq(with_costly.fraction(FacetsRules.BAND_SUCCESS), "20/36")
	assert_eq(with_costly.fraction(FacetsRules.BAND_STRONG), "6/36")
	for band in spec["percent_with_costly"]:
		assert_eq(with_costly.percent_text(band), spec["percent_with_costly"][band], band)
	var without := FacetsProbability.enumerate(_check(5, 3, 14, false), FacetsAdjustments.new())
	assert_eq(without.counts, spec["without_costly"])
	assert_eq(without.percent_text(FacetsRules.BAND_FAILURE), "27.78%")


func test_t02_every_pair_enumerated_once() -> void:
	for total in range(2, 13):
		var ways := 0
		for die_1 in range(1, 7):
			for die_2 in range(1, 7):
				if die_1 + die_2 == total:
					ways += 1
		assert_eq(FacetsProbability.ways_to_roll(total), ways, "ways to roll %d" % total)


func test_t02_routine_odds_have_no_strong_band() -> void:
	var odds := FacetsProbability.routine_odds()
	assert_eq(odds.count(FacetsRules.BAND_SUCCESS), 36)
	assert_eq(odds.count(FacetsRules.BAND_STRONG), 0, "routine success grants no strong benefit")


# --- T03 bands -------------------------------------------------------------------

func test_t03_margin_bands() -> void:
	var expectations := {-3: "failure", -2: "costly_offer", -1: "costly_offer", 0: "success", 3: "success", 4: "strong_success"}
	for margin in expectations:
		assert_eq(FacetsRules.band_for_margin(margin, true), expectations[margin], "margin %d" % margin)
	for margin in [-2, -1]:
		assert_eq(FacetsRules.band_for_margin(margin, false), "failure", "costly band fails when unsupported (%d)" % margin)


func test_t03_resolution_fixture_cases() -> void:
	var data: Dictionary = fixture("rules/resolution_cases.json")
	for case in data["cases"]:
		var check := FacetsCheckInput.from_dict(case["check"])
		var dice := Vector2i(int(case["dice"][0]), int(case["dice"][1]))
		var evaluation := FacetsResolver.evaluate_with_sum(check, dice, int(case["modifier_sum"]), bool(case["push"]), bool(case["resolve"]))
		assert_eq(evaluation.total, int(case["expected"]["total"]), "%s total" % case["name"])
		assert_eq(evaluation.margin, int(case["expected"]["margin"]), "%s margin" % case["name"])
		assert_eq(evaluation.band, case["expected"]["band"], "%s band" % case["name"])


func test_t03_spec_api_example() -> void:
	var check := FacetsCheckInput.new()
	check.facet = 3
	check.skill = 2
	check.target = 13
	check.allows_costly_success = true
	var evaluation := FacetsResolver.evaluate(check, Vector2i(3, 3), FacetsAdjustments.new())
	assert_eq(evaluation.total, 11)
	assert_eq(evaluation.margin, -2)
	assert_true(evaluation.is_provisional(), "costly-success offer is provisional")


# --- T04 no criticals ------------------------------------------------------------

func test_t04_no_natural_criticals() -> void:
	var low := FacetsResolver.evaluate(_check(5, 4, 9, true), Vector2i(1, 1), FacetsAdjustments.new())
	assert_eq(low.margin, 2, "1+1+5+4 vs 9")
	assert_eq(low.band, FacetsRules.BAND_SUCCESS, "double one still succeeds on arithmetic")
	var high := FacetsResolver.evaluate(_check(2, 0, 19, true), Vector2i(6, 6), FacetsAdjustments.new())
	assert_eq(high.band, FacetsRules.BAND_FAILURE, "double six still fails on arithmetic")


func test_t04_checked_evaluation_rejects_bad_dice() -> void:
	assert_error(FacetsResolver.evaluate_checked(_check(3, 2, 13, true), Vector2i(0, 7), FacetsAdjustments.new()), FacetsError.OUT_OF_RANGE)


# --- T05 modifier aggregation ------------------------------------------------------

func test_t05_clamp_after_aggregation() -> void:
	var mods: Array[FacetsModifier] = [
		FacetsModifier.make("scene.rain", "weather.rain", FacetsModifier.SCOPE_SITUATIONAL, -2),
		FacetsModifier.make("scene.dark", "light.darkness", FacetsModifier.SCOPE_SITUATIONAL, -2),
		FacetsModifier.make("item.scope", "equipment.scope", FacetsModifier.SCOPE_EQUIPMENT, 1),
	]
	assert_eq(FacetsModifiers.validate(mods).size(), 0)
	var aggregate := FacetsModifiers.aggregate(mods)
	assert_eq(aggregate["raw"], -3)
	assert_eq(aggregate["applied"], -3)
	mods.append(FacetsModifier.make("scene.noise", "sound.noise", FacetsModifier.SCOPE_SITUATIONAL, -2))
	assert_eq(FacetsModifiers.aggregate(mods)["applied"], -3, "sum -5 clamps to -3")
	var big: Array[FacetsModifier] = [
		FacetsModifier.make("a", "f.a", FacetsModifier.SCOPE_SITUATIONAL, 2),
		FacetsModifier.make("b", "f.b", FacetsModifier.SCOPE_SITUATIONAL, 3),
	]
	assert_eq(FacetsModifiers.aggregate(big)["applied"], 3, "sum +5 clamps to +3")


func test_t05_duplicate_factor_rejected_across_sides() -> void:
	var attacker: Array[FacetsModifier] = [FacetsModifier.make("scene.fog", "visibility.fog", FacetsModifier.SCOPE_SITUATIONAL, -1)]
	var defense: Array[FacetsModifier] = [FacetsModifier.make("zone.fog", "visibility.fog", FacetsModifier.SCOPE_COVER, 1)]
	assert_has_error(FacetsModifiers.validate(attacker, defense), FacetsError.DUPLICATE_FACTOR)
	var twice: Array[FacetsModifier] = [
		FacetsModifier.make("a", "light.darkness", FacetsModifier.SCOPE_SITUATIONAL, -1),
		FacetsModifier.make("b", "light.darkness", FacetsModifier.SCOPE_SITUATIONAL, -1),
	]
	assert_has_error(FacetsModifiers.validate(twice), FacetsError.DUPLICATE_FACTOR)


func test_t05_modifiers_need_provenance() -> void:
	var bare: Array[FacetsModifier] = [FacetsModifier.make("", "", "made_up", 1)]
	var errors := FacetsModifiers.validate(bare)
	assert_true(errors.size() >= 3, "source, factor and scope errors")


# --- T06 assistance, relationship, conditions -------------------------------------

func test_t06_single_assistance() -> void:
	var two: Array[FacetsModifier] = [
		FacetsModifier.make("helper.a", "assist.a", FacetsModifier.SCOPE_ASSISTANCE, 1),
		FacetsModifier.make("helper.b", "assist.b", FacetsModifier.SCOPE_ASSISTANCE, 1),
	]
	assert_has_error(FacetsModifiers.validate(two), FacetsError.MODIFIER_LIMIT)
	var plus_two: Array[FacetsModifier] = [FacetsModifier.make("helper.a", "assist.a", FacetsModifier.SCOPE_ASSISTANCE, 2)]
	assert_has_error(FacetsModifiers.validate(plus_two), FacetsError.MODIFIER_LIMIT)


func test_t06_single_relationship_plus_minus_one() -> void:
	var two: Array[FacetsModifier] = [
		FacetsModifier.make("bond.guard", "relationship.trust", FacetsModifier.SCOPE_RELATIONSHIP, 1),
		FacetsModifier.make("bond.guard", "relationship.affinity", FacetsModifier.SCOPE_RELATIONSHIP, 1),
	]
	assert_has_error(FacetsModifiers.validate(two), FacetsError.MODIFIER_LIMIT, "trust and affinity never sum")
	var big: Array[FacetsModifier] = [FacetsModifier.make("bond.guard", "relationship.guard", FacetsModifier.SCOPE_RELATIONSHIP, 2)]
	assert_has_error(FacetsModifiers.validate(big), FacetsError.MODIFIER_LIMIT)


func test_t06_worst_condition_only_capped() -> void:
	var mods: Array[FacetsModifier] = [
		FacetsModifier.make("core.overwhelmed", "condition.overwhelmed", FacetsModifier.SCOPE_CONDITION, -1),
		FacetsModifier.make("core.injured", "condition.injured", FacetsModifier.SCOPE_CONDITION, -1),
		FacetsModifier.make("core.shaken", "condition.shaken", FacetsModifier.SCOPE_CONDITION, -1),
	]
	assert_eq(FacetsModifiers.aggregate(mods)["raw"], -1, "conditions do not stack")
	mods.append(FacetsModifier.make("x.cursed", "condition.cursed", FacetsModifier.SCOPE_CONDITION, -3))
	assert_eq(FacetsModifiers.aggregate(mods)["raw"], -2, "worst penalty capped at -2")


# --- T07 opposed ------------------------------------------------------------------

func test_t07_opposed_target_formula() -> void:
	assert_eq(FacetsRules.opposed_target(3, 2, 0), 12)
	assert_eq(FacetsRules.opposed_target(3, 2, 5), 15, "defense modifiers capped at +3")
	assert_eq(FacetsRules.opposed_target(3, 2, -9), 9, "defense modifiers capped at -3")


# --- T08 push ------------------------------------------------------------------------

func test_t08_push_is_outside_cap() -> void:
	var adjustments := FacetsAdjustments.make([FacetsModifier.make("a", "f.a", FacetsModifier.SCOPE_SITUATIONAL, 3), FacetsModifier.make("b", "f.b", FacetsModifier.SCOPE_SITUATIONAL, 2)], true)
	var evaluation := FacetsResolver.evaluate(_check(3, 2, 13, true), Vector2i(3, 3), adjustments)
	assert_eq(evaluation.modifier_applied, 3)
	assert_eq(evaluation.push_bonus, 1)
	assert_eq(evaluation.total, 15)


# --- T09 Resolve ---------------------------------------------------------------------

func test_t09_resolve_upgrade_bands() -> void:
	var check := _check(3, 2, 13, true)
	# failure -> offered cost
	assert_eq(FacetsResolver.evaluate_with_sum(check, Vector2i(2, 2), 0, false, false).band, "failure")
	assert_eq(FacetsResolver.evaluate_with_sum(check, Vector2i(2, 2), 0, false, true).band, "costly_offer")
	# costly band -> success
	assert_eq(FacetsResolver.evaluate_with_sum(check, Vector2i(3, 3), 0, false, true).band, "success")
	# success -> strong success
	assert_eq(FacetsResolver.evaluate_with_sum(check, Vector2i(5, 5), 0, false, false).band, "success")
	assert_eq(FacetsResolver.evaluate_with_sum(check, Vector2i(5, 5), 0, false, true).band, "strong_success")


# --- T10 Overwhelmed -----------------------------------------------------------------

func test_t10_overwhelmed_at_capacity_and_removed_below() -> void:
	var world := FacetsWorldSnapshot.new()
	var actor := FacetsActorState.new()
	actor.actor_id = "a"
	actor.build = FacetsBuild.from_dict({"facets": {"force": 2, "agility": 2, "cunning": 2, "empathy": 2, "tenacity": 2, "sense": 2}})
	world.add_actor(actor)
	var txn := FacetsTxn.begin(world)
	assert_eq(actor.strain_capacity(), 6)
	txn.add_strain("a", 5)
	assert_false(actor.is_overwhelmed(), "5/6 is not overwhelmed")
	txn.add_strain("a", 4)
	assert_eq(actor.strain, 6, "strain clamps at capacity; no wounds")
	assert_true(actor.is_overwhelmed(), "at capacity")
	assert_eq(actor.harm, 0, "further strain does not create harm")
	txn.add_strain("a", -2)
	assert_eq(actor.strain, 4)
	assert_false(actor.is_overwhelmed(), "removed below capacity")
	assert_false(txn.failed())
