@tool
class_name FacetsProgression
extends RefCounted
## Growth spending at safe checkpoints and respec.
##
## Costs: skill rank 2 x new rank (cap 4, practice or instruction required);
## talent 5 (prerequisites, at most six equipped); facet 8 (cap 5, once per
## completed chapter). Every purchase is written to the actor's ledger with
## the cost actually paid, and respec refunds those recorded amounts.


## Prices a purchase {"kind": "skill"|"talent"|"facet", "id": String,
## "chapter_id": String (facets only)}. Returns {kind, id, from, to, cost, chapter_id}.
static func quote(registry: FacetsRegistry, world: FacetsWorldSnapshot, actor: FacetsActorState, item: Dictionary) -> FacetsReply:
	if actor == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
	var kind := str(item.get("kind", ""))
	var item_id := str(item.get("id", ""))
	var result := {"kind": kind, "id": item_id, "from": 0, "to": 0, "cost": 0, "chapter_id": ""}
	match kind:
		"skill":
			if not registry.has_skill(item_id):
				return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown skill.", "purchase.id")
			var current := actor.build.skill(item_id)
			if current + 1 > FacetsRules.SKILL_MAX:
				return FacetsReply.fail(FacetsError.OUT_OF_RANGE, "Skills cap at %d." % FacetsRules.SKILL_MAX, "purchase.id")
			if not actor.trained_skills.has(item_id):
				return FacetsReply.fail(FacetsError.PREREQUISITE, "Raising a skill needs practice or instruction.", "purchase.id")
			result["from"] = current
			result["to"] = current + 1
			result["cost"] = FacetsRules.SKILL_COST_PER_RANK * (current + 1)
		"talent":
			if not registry.has_talent(item_id):
				return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown talent.", "purchase.id")
			var definition := registry.get_talent(item_id)
			if actor.build.has_talent(item_id) and not bool(definition.get("repeatable", false)):
				return FacetsReply.fail(FacetsError.DUPLICATE, "Talent already known.", "purchase.id")
			if actor.build.talents.size() >= FacetsRules.MAX_EQUIPPED_TALENTS:
				return FacetsReply.fail(FacetsError.BUDGET, "At most %d talents may be equipped." % FacetsRules.MAX_EQUIPPED_TALENTS, "purchase.id")
			var prerequisite_errors := FacetsValidator.prerequisite_errors(definition, actor.build, "purchase.id")
			if not prerequisite_errors.is_empty():
				return FacetsReply.failures(prerequisite_errors)
			result["cost"] = FacetsRules.TALENT_COST
		"facet":
			if not FacetsRules.FACETS.has(item_id):
				return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown facet.", "purchase.id")
			var current := actor.build.facet(item_id)
			if current + 1 > FacetsRules.PROGRESSED_FACET_CAP:
				return FacetsReply.fail(FacetsError.OUT_OF_RANGE, "Facets cap at %d." % FacetsRules.PROGRESSED_FACET_CAP, "purchase.id")
			var chapter_id := str(item.get("chapter_id", ""))
			if chapter_id.is_empty() or not world.completed_chapters.has(chapter_id):
				return FacetsReply.fail(FacetsError.PREREQUISITE, "A facet increase needs a completed chapter.", "purchase.chapter_id")
			if actor.awards.has(facet_award_key(chapter_id)):
				return FacetsReply.fail(FacetsError.ALREADY_USED, "That chapter's facet increase was already taken.", "purchase.chapter_id")
			result["from"] = current
			result["to"] = current + 1
			result["cost"] = FacetsRules.FACET_COST
			result["chapter_id"] = chapter_id
		_:
			return FacetsReply.fail(FacetsError.INVALID_FIELD, "Purchase kind must be skill, talent or facet.", "purchase.kind")
	if actor.growth < int(result["cost"]):
		return FacetsReply.fail(FacetsError.INSUFFICIENT, "Needs %d Growth; %d available." % [result["cost"], actor.growth], "growth")
	return FacetsReply.success(result)


static func facet_award_key(chapter_id: String) -> String:
	return "facet_chapter:%s" % chapter_id


static func apply_purchase(txn: FacetsTxn, actor_id: String, priced: Dictionary, sequence: int) -> void:
	var cost := int(priced["cost"])
	txn.add_growth(actor_id, -cost)
	match str(priced["kind"]):
		"skill":
			txn.set_path(["actors", actor_id, "build", "skills", priced["id"]], int(priced["to"]))
		"talent":
			txn.append(["actors", actor_id, "build", "talents"], str(priced["id"]))
		"facet":
			txn.set_path(["actors", actor_id, "build", "facets", priced["id"]], int(priced["to"]))
			txn.record_award(actor_id, facet_award_key(str(priced["chapter_id"])), 1)
	var entry: Dictionary = priced.duplicate(true)
	entry["sequence"] = sequence
	txn.append(["actors", actor_id, "ledger"], entry)


## Plans a refund of ledger entries (all when [param entry_indices] is empty).
## Later purchases of the same skill or facet are refunded with an earlier
## one; purchased talents whose prerequisites no longer hold are refunded
## too. Returns {refund, build, ledger, refunded, invalidated_talents}.
static func plan_respec(registry: FacetsRegistry, actor: FacetsActorState, entry_indices: Array) -> FacetsReply:
	if actor == null:
		return FacetsReply.fail(FacetsError.UNKNOWN_ID, "Unknown character.", "actor_id")
	var ledger: Array = actor.ledger
	var selected := {}
	if entry_indices.is_empty():
		for index in ledger.size():
			selected[index] = true
	else:
		for value in entry_indices:
			var index := int(value)
			if index < 0 or index >= ledger.size():
				return FacetsReply.fail(FacetsError.OUT_OF_RANGE, "No purchase at ledger index %d." % index, "entries")
			selected[index] = true
	# Refunding a rank also refunds later ranks of the same skill or facet.
	for index in ledger.size():
		if not selected.has(index):
			continue
		var entry: Dictionary = ledger[index]
		if str(entry["kind"]) == "talent":
			continue
		for later in range(index + 1, ledger.size()):
			if str(ledger[later]["kind"]) == str(entry["kind"]) and str(ledger[later]["id"]) == str(entry["id"]):
				selected[later] = true
	var invalidated: Array[String] = []
	var build := _rebuild(actor, ledger, selected)
	# Invalidate purchased talents whose prerequisites no longer hold.
	var changed := true
	while changed:
		changed = false
		for index in ledger.size():
			if selected.has(index) or str(ledger[index]["kind"]) != "talent":
				continue
			var definition := registry.get_talent(str(ledger[index]["id"]))
			if not FacetsValidator.prerequisites_met(definition, build):
				selected[index] = true
				invalidated.append(str(ledger[index]["id"]))
				build = _rebuild(actor, ledger, selected)
				changed = true
	var refund := 0
	var refunded: Array = []
	var remaining: Array = []
	for index in ledger.size():
		if selected.has(index):
			refund += int(ledger[index]["cost"])
			refunded.append(ledger[index])
		else:
			remaining.append(ledger[index])
	var errors := FacetsValidator.validate_progressed(build, registry, "build")
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	return FacetsReply.success({"refund": refund, "build": build.to_dict(), "ledger": remaining, "refunded": refunded, "invalidated_talents": invalidated})


static func _rebuild(actor: FacetsActorState, ledger: Array, selected: Dictionary) -> FacetsBuild:
	var build := FacetsBuild.from_dict(actor.base_build if not actor.base_build.is_empty() else actor.build.to_dict())
	for index in ledger.size():
		if selected.has(index):
			continue
		var entry: Dictionary = ledger[index]
		match str(entry["kind"]):
			"skill":
				build.skills[str(entry["id"])] = build.skill(str(entry["id"])) + 1
			"facet":
				build.facets[str(entry["id"])] = build.facet(str(entry["id"])) + 1
			"talent":
				build.talents.append(str(entry["id"]))
	return build


static func apply_respec(txn: FacetsTxn, actor_id: String, plan: Dictionary) -> void:
	var build: Dictionary = plan["build"]
	txn.set_path(["actors", actor_id, "build", "facets"], build["facets"])
	txn.set_path(["actors", actor_id, "build", "skills"], build["skills"])
	txn.set_path(["actors", actor_id, "build", "talents"], build["talents"])
	txn.add_growth(actor_id, int(plan["refund"]))
	txn.set_path(["actors", actor_id, "ledger"], plan["ledger"])
	for entry in plan["refunded"]:
		if str(entry["kind"]) == "facet":
			txn.set_path(["actors", actor_id, "awards", facet_award_key(str(entry["chapter_id"]))], null)
