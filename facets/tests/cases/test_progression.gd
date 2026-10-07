extends FacetsTestCase
## T25: milestones, purchase costs, facet chapter limit, prerequisites and
## actual-cost respec.

const W := preload("res://tests/framework/test_world.gd")


func _growth(session: FacetsSession, actor_id: String, chapters: int) -> void:
	for index in chapters:
		assert_ok(session.award_milestone(actor_id, "m.chapter.%d" % index, "chapter", "evt.chapter.%d" % index))


func test_t25_milestone_sizes_and_dedupe() -> void:
	var session := W.session()
	assert_ok(session.award_milestone("mara", "m.small", "small", "evt.a"))
	assert_eq(session.actor_state("mara").growth, 1)
	assert_ok(session.award_milestone("mara", "m.chapter", "chapter", "evt.b"))
	assert_eq(session.actor_state("mara").growth, 4)
	assert_error(session.award_milestone("mara", "m.small", "small", "evt.c"), FacetsError.ALREADY_USED, "milestone key reused")
	assert_error(session.award_milestone("mara", "m.other", "chapter", "evt.a"), FacetsError.ALREADY_USED, "same underlying event")
	assert_error(session.award_milestone("mara", "m.x", "huge", "evt.x"), FacetsError.INVALID_FIELD)
	assert_error(session.award_milestone("mara", "m.y", "small", "evt.y", FacetsPrincipal.player("p", ["mara"])), FacetsError.NOT_AUTHORIZED)
	assert_eq(session.actor_state("mara").growth, 4)


func test_t25_skill_cost_cap_and_training() -> void:
	var session := W.session()
	_growth(session, "mara", 5)
	assert_error(session.purchase("mara", {"kind": "skill", "id": "stealth"}, "cp.1"), FacetsError.NOT_AUTHORIZED, "needs a safe checkpoint")
	assert_ok(session.grant_opportunity("cp.1", "checkpoint"))
	assert_error(session.purchase("mara", {"kind": "skill", "id": "stealth"}, "cp.1"), FacetsError.PREREQUISITE, "needs practice or instruction")
	assert_ok(session.grant_training("mara", "stealth"))
	var bought: FacetsResolutionEvent = assert_ok(session.purchase("mara", {"kind": "skill", "id": "stealth"}, "cp.1"))
	assert_eq(int(bought.record["purchase"]["cost"]), 6, "2 x new rank 3")
	assert_eq(session.actor_state("mara").build.skill("stealth"), 3)
	assert_eq(session.actor_state("mara").growth, 9)
	assert_ok(session.purchase("mara", {"kind": "skill", "id": "stealth"}, "cp.1"))
	assert_eq(session.actor_state("mara").growth, 1, "rank 4 costs 8")
	_growth_more(session, "mara", 3)
	assert_error(session.purchase("mara", {"kind": "skill", "id": "stealth"}, "cp.1"), FacetsError.OUT_OF_RANGE, "skills cap at 4")
	var ledger := session.actor_state("mara").ledger
	assert_eq(ledger.size(), 2)
	assert_eq(int(ledger[0]["cost"]), 6)
	assert_eq(int(ledger[1]["cost"]), 8)


func _growth_more(session: FacetsSession, actor_id: String, chapters: int) -> void:
	for index in chapters:
		assert_ok(session.award_milestone(actor_id, "m.more.%d" % index, "chapter", "evt.more.%d" % index))


func test_t25_talent_cost_prerequisites_and_limit() -> void:
	var session := W.session()
	_growth(session, "iris", 10)
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	assert_error(session.purchase("iris", {"kind": "talent", "id": "core.quiet_hands"}, "cp"), FacetsError.PREREQUISITE, "needs Sleight 1")
	assert_error(session.purchase("iris", {"kind": "talent", "id": "core.steady_voice"}, "cp"), FacetsError.DUPLICATE)
	var bought: FacetsResolutionEvent = assert_ok(session.purchase("iris", {"kind": "talent", "id": "core.trail_reader"}, "cp"))
	assert_eq(int(bought.record["purchase"]["cost"]), 5)
	assert_ok(session.purchase("iris", {"kind": "talent", "id": "core.second_look"}, "cp"))
	assert_error(session.purchase("iris", {"kind": "talent", "id": "core.field_engineer"}, "cp"), FacetsError.PREREQUISITE, "needs Technology 1")
	assert_eq(session.actor_state("iris").build.talents.size(), 4)
	assert_eq(session.actor_state("iris").growth, 20)


func test_t25_six_talent_limit() -> void:
	var registry := W.registry()
	for index in 6:
		assert_ok(registry.add_talent({"id": "test.extra_%d" % index, "version": 1, "display_name": "Extra %d" % index, "hook_id": "trail_reader", "parameters": {"skills": [], "uses_per_scene": 0}, "prerequisites": {}, "usage_scope": "passive", "uses": 0, "repeatable": false, "package": "core"}))
	var session: FacetsSession = FacetsSession.create(registry, W.world(), {}).value
	_growth(session, "iris", 12)
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	for index in 4:
		assert_ok(session.purchase("iris", {"kind": "talent", "id": "test.extra_%d" % index}, "cp"))
	assert_eq(session.actor_state("iris").build.talents.size(), 6)
	assert_error(session.purchase("iris", {"kind": "talent", "id": "test.extra_4"}, "cp"), FacetsError.BUDGET, "at most six equipped")


func test_t25_facet_once_per_completed_chapter() -> void:
	var session := W.session()
	_growth(session, "iris", 8)
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	assert_error(session.purchase("iris", {"kind": "facet", "id": "agility", "chapter_id": "chapter.1"}, "cp"), FacetsError.PREREQUISITE, "chapter not completed")
	assert_ok(session.complete_chapter("chapter.1"))
	var bought: FacetsResolutionEvent = assert_ok(session.purchase("iris", {"kind": "facet", "id": "agility", "chapter_id": "chapter.1"}, "cp"))
	assert_eq(int(bought.record["purchase"]["cost"]), 8)
	assert_eq(session.actor_state("iris").build.facet("agility"), 3)
	assert_error(session.purchase("iris", {"kind": "facet", "id": "sense", "chapter_id": "chapter.1"}, "cp"), FacetsError.ALREADY_USED, "once per chapter")
	assert_ok(session.complete_chapter("chapter.2"))
	assert_ok(session.apply_host_effects("iris", [], "noop"))
	_growth_more(session, "iris", 3)
	assert_ok(session.purchase("iris", {"kind": "facet", "id": "empathy", "chapter_id": "chapter.2"}, "cp"))
	assert_eq(session.actor_state("iris").build.facet("empathy"), 5)
	assert_ok(session.complete_chapter("chapter.3"))
	_growth_extra(session, "iris")
	assert_error(session.purchase("iris", {"kind": "facet", "id": "empathy", "chapter_id": "chapter.3"}, "cp"), FacetsError.OUT_OF_RANGE, "facets cap at 5")


func _growth_extra(session: FacetsSession, actor_id: String) -> void:
	for index in 3:
		assert_ok(session.award_milestone(actor_id, "m.extra.%d" % index, "chapter", "evt.extra.%d" % index))


func test_t25_respec_refunds_actual_cost_and_invalidates_dependents() -> void:
	var session := W.session()
	_growth(session, "iris", 3)
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	assert_ok(session.grant_training("iris", "sleight"))
	assert_ok(session.purchase("iris", {"kind": "skill", "id": "sleight"}, "cp"))
	assert_ok(session.purchase("iris", {"kind": "talent", "id": "core.quiet_hands"}, "cp"))
	var iris := session.actor_state("iris")
	assert_eq(iris.growth, 2, "9 - 2 - 5")
	assert_true(iris.build.has_talent("core.quiet_hands"))
	var event: FacetsResolutionEvent = assert_ok(session.respec("iris", "cp", [0]))
	iris = session.actor_state("iris")
	assert_eq(iris.build.skill("sleight"), 0)
	assert_false(iris.build.has_talent("core.quiet_hands"), "dependent talent invalidated")
	assert_eq(iris.growth, 9, "both purchases refunded")
	assert_eq(event.record["respec"]["invalidated_talents"], ["core.quiet_hands"])
	assert_eq(iris.ledger.size(), 0)
	assert_eq(iris.build.talents, ["core.steady_voice", "core.bargain_maker"], "starting talents untouched")


func test_t25_respec_uses_recorded_cost_not_current_price() -> void:
	var registry := W.registry()
	var world := W.world()
	var veteran := W.actor("vet", "Veteran", W.IRIS)
	veteran.base_build = veteran.build.to_dict()
	veteran.build.talents.append("core.trail_reader")
	veteran.ledger = [{"kind": "talent", "id": "core.trail_reader", "from": 0, "to": 0, "cost": 4, "chapter_id": "", "sequence": 1, "note": "legacy price"}]
	world.add_actor(veteran)
	var session: FacetsSession = FacetsSession.create(registry, world, {}).value
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	var event: FacetsResolutionEvent = assert_ok(session.respec("vet", "cp"))
	assert_eq(int(event.record["respec"]["refund"]), 4, "refund equals the recorded paid cost")
	assert_eq(session.actor_state("vet").growth, 4)
	assert_error(session.respec("vet", "cp", [3]), FacetsError.OUT_OF_RANGE)


func test_t25_identity_editing_is_separate_from_respec() -> void:
	var session := W.session()
	_growth(session, "mara", 1)
	assert_ok(session.grant_opportunity("cp", "checkpoint"))
	var before: Dictionary = session.actor_state("mara").identity
	assert_ok(session.respec("mara", "cp"))
	assert_eq(session.actor_state("mara").identity, before)


func test_t25_reset_journey_preserves_profile() -> void:
	var session := W.session()
	assert_ok(session.apply_host_effects("mara", [W.eff("actor.strain", {"amount": 3})], "strain"))
	_growth(session, "mara", 1)
	var world := session.snapshot()
	world.actor("mara").profile = {"accomplishments": ["Delivered through the riot"]}
	var reseeded: FacetsSession = FacetsSession.create(session.registry, world, {}).value
	assert_ok(reseeded.reset_journey("mara"))
	var mara := reseeded.actor_state("mara")
	assert_eq(mara.strain, 0)
	assert_eq(mara.growth, 0)
	assert_eq(mara.resolve, 1)
	assert_eq(mara.profile["accomplishments"], ["Delivered through the riot"], "profile survives reset")
	assert_eq(mara.build.to_dict(), FacetsBuild.from_dict(W.MARA).to_dict(), "build untouched")
