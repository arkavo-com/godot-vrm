@tool
class_name FacetsSaveValidator
extends RefCounted
## Type and range checks for loaded saves and event records, applied in
## GDScript before any of the data is trusted. Complements the JSON Schemas.


static func validate_save(data: Dictionary) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	for key in ["checkpoint", "journal", "pending", "events", "requests", "rng"]:
		if not data.has(key):
			errors.append(FacetsError.make(FacetsError.MISSING_FIELD, "Save is missing %s." % key, key))
	if not errors.is_empty():
		return errors
	var checkpoint: Variant = data["checkpoint"]
	if not checkpoint is Dictionary or not checkpoint.get("state") is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "Checkpoint state is missing.", "checkpoint"))
	else:
		errors.append_array(validate_world(checkpoint["state"], "checkpoint.state"))
	var journal: Variant = data["journal"]
	if not journal is Array:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "Journal must be a list.", "journal"))
	else:
		for index in journal.size():
			var entry: Variant = journal[index]
			if not entry is Dictionary or not entry.get("ops") is Array or not entry.get("sequence") is int:
				errors.append(FacetsError.make(FacetsError.REPLAY_CORRUPT, "Journal entry %d is incomplete." % index, "journal[%d]" % index))
	var pending: Variant = data["pending"]
	if not pending is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "pending must be an object.", "pending"))
	elif not pending.is_empty():
		errors.append_array(validate_record(pending, "pending"))
		if str(pending.get("status", "")) != "pending" or not pending.get("decision") is Dictionary or pending["decision"].is_empty():
			errors.append(FacetsError.make(FacetsError.MALFORMED, "A pending record needs an open decision.", "pending.decision"))
	var events: Variant = data["events"]
	if not events is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "events must be an object.", "events"))
	else:
		for event_id in events:
			errors.append_array(validate_record(events[event_id], "events.%s" % event_id))
	var requests: Variant = data["requests"]
	if not requests is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "requests must be an object.", "requests"))
	else:
		for request_id in requests:
			var item: Variant = requests[request_id]
			if not item is Dictionary or not item.get("digest") is String or not item.get("response") is Dictionary:
				errors.append(FacetsError.make(FacetsError.MALFORMED, "Request record is incomplete.", "requests.%s" % request_id))
	var rng: Variant = data["rng"]
	if not rng is Dictionary or not ["rng", "fixed"].has(str(rng.get("kind", ""))):
		errors.append(FacetsError.make(FacetsError.MALFORMED, "Random stream metadata is missing.", "rng"))
	else:
		for key in ["seed", "state"]:
			if rng.has(key) and (not rng[key] is String or not str(rng[key]).is_valid_int()):
				errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "rng.%s must be a decimal string." % key, "rng.%s" % key))
		for pair in rng.get("queue", []):
			if not _dice_ok(pair) or pair.is_empty():
				errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Queued dice must be two values 1..6.", "rng.queue"))
	return errors


static func validate_world(world: Dictionary, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	var actors: Variant = world.get("actors", {})
	if not actors is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "actors must be an object.", path + ".actors"))
		return errors
	for actor_id in actors:
		var actor: Variant = actors[actor_id]
		var actor_path := "%s.actors.%s" % [path, actor_id]
		if not actor is Dictionary:
			errors.append(FacetsError.make(FacetsError.MALFORMED, "Actor must be an object.", actor_path))
			continue
		for key in ["strain", "growth", "harm"]:
			if not actor.get(key, 0) is int or int(actor.get(key, 0)) < 0:
				errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "%s must be a non-negative integer." % key, "%s.%s" % [actor_path, key]))
		var resolve: Variant = actor.get("resolve", FacetsRules.START_RESOLVE)
		if not resolve is int or resolve < FacetsRules.RESOLVE_MIN or resolve > FacetsRules.RESOLVE_MAX:
			errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Resolve must be 0..3.", actor_path + ".resolve"))
		var bonds: Variant = actor.get("bonds", {})
		if bonds is Dictionary:
			for other_id in bonds:
				for dimension in ["trust", "affinity"]:
					var value: Variant = bonds[other_id].get(dimension, 0) if bonds[other_id] is Dictionary else null
					if not value is int or value < FacetsRules.BOND_MIN or value > FacetsRules.BOND_MAX:
						errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Bond %s must be -2..+2." % dimension, "%s.bonds.%s.%s" % [actor_path, other_id, dimension]))
	return errors


static func validate_record(record: Variant, path: String) -> Array[FacetsError]:
	var errors: Array[FacetsError] = []
	if not record is Dictionary:
		errors.append(FacetsError.make(FacetsError.MALFORMED, "Event record must be an object.", path))
		return errors
	if not str(record.get("event_id", "")).begins_with("evt-"):
		errors.append(FacetsError.make(FacetsError.MALFORMED, "Event record needs an event_id.", path + ".event_id"))
	if not ["pending", "final"].has(str(record.get("status", ""))):
		errors.append(FacetsError.make(FacetsError.INVALID_FIELD, "Unknown event status.", path + ".status"))
	if record.has("dice") and not _dice_ok(record["dice"]):
		errors.append(FacetsError.make(FacetsError.OUT_OF_RANGE, "Dice must be empty or two values 1..6.", path + ".dice"))
	if str(record.get("kind", "")) == "check":
		for key in ["action", "check", "base", "request"]:
			if not record.get(key) is Dictionary:
				errors.append(FacetsError.make(FacetsError.MALFORMED, "Check record is missing %s." % key, "%s.%s" % [path, key]))
		if str(record.get("status", "")) == "final" and not FacetsRules.band_rank(str(record.get("final_band", ""))) >= 0:
			errors.append(FacetsError.make(FacetsError.MALFORMED, "Final check needs a final band.", path + ".final_band"))
	for key in ["commit_ops", "finalize_ops", "ops"]:
		if record.has(key):
			for op in record[key]:
				if not op is Dictionary or not FacetsReducer.OPS.has(str(op.get("op", ""))):
					errors.append(FacetsError.make(FacetsError.UNKNOWN_OPERATION, "Unknown state operation in %s." % key, "%s.%s" % [path, key]))
					break
	return errors


static func _dice_ok(value: Variant) -> bool:
	if not value is Array:
		return false
	if value.is_empty():
		return true
	if value.size() != 2:
		return false
	for die in value:
		if not die is int or die < 1 or die > 6:
			return false
	return true
