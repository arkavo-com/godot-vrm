@tool
class_name FacetsWorldSnapshot
extends RefCounted
## Authoritative world state owned by a session: revision, actors, objects,
## facts, zones, scene/chapter IDs and host-authorized opportunities.

var revision: int = 0
var scene_id: String = ""
var chapter_id: String = ""
var clock: int = 0
## actor_id -> FacetsActorState
var actors: Dictionary = {}
## object_id -> Dictionary of flags
var objects: Dictionary = {}
## fact_id -> {value, visibility: public|private, owner_id, evidence_id, label}
var facts: Dictionary = {}
## zone_id -> {adjacent: [], visible: []}
var zones: Dictionary = {}
var counters: Dictionary = {}
## opportunity_id -> {kind: breather|secure_rest|checkpoint, scene_id, used_by: []}
var opportunities: Dictionary = {}
## lock_key -> {actor_id, objective_id, approach_id, fingerprint, event_id}
var retry_locks: Dictionary = {}
## objective_id -> host-authorized meaningful-change epoch
var objective_epochs: Dictionary = {}
## npc_id -> [topics] the NPC refuses regardless of dice
var refusals: Dictionary = {}
## "npc_id:topic" -> true
var grants: Dictionary = {}
## Effects reverted at scene end: [{scope, path, value}]
var expiring: Array = []
var completed_chapters: Array[String] = []
## World-level award keys (e.g. milestone underlying events).
var awards: Dictionary = {}


func actor(actor_id: String) -> FacetsActorState:
	return actors.get(actor_id) as FacetsActorState


func has_actor(actor_id: String) -> bool:
	return actors.has(actor_id)


func add_actor(state: FacetsActorState) -> void:
	actors[state.actor_id] = state


func object_flag(object_id: String, key: String, default: Variant = null) -> Variant:
	var item: Variant = objects.get(object_id, {})
	if item is Dictionary:
		return item.get(key, default)
	return default


func fact_value(fact_id: String, default: Variant = null) -> Variant:
	var fact: Variant = facts.get(fact_id, {})
	if fact is Dictionary:
		return fact.get("value", default)
	return default


func to_dict() -> Dictionary:
	var actor_dicts := {}
	for actor_id in actors:
		actor_dicts[actor_id] = (actors[actor_id] as FacetsActorState).to_dict()
	return {
		"revision": revision,
		"scene_id": scene_id,
		"chapter_id": chapter_id,
		"clock": clock,
		"actors": actor_dicts,
		"objects": objects.duplicate(true),
		"facts": facts.duplicate(true),
		"zones": zones.duplicate(true),
		"counters": counters.duplicate(true),
		"opportunities": opportunities.duplicate(true),
		"retry_locks": retry_locks.duplicate(true),
		"objective_epochs": objective_epochs.duplicate(true),
		"refusals": refusals.duplicate(true),
		"grants": grants.duplicate(true),
		"expiring": expiring.duplicate(true),
		"completed_chapters": completed_chapters.duplicate(),
		"awards": awards.duplicate(true),
	}


static func from_dict(source: Dictionary) -> FacetsWorldSnapshot:
	var data: Dictionary = FacetsJson.normalize(source)
	var world := FacetsWorldSnapshot.new()
	world.revision = int(data.get("revision", 0))
	world.scene_id = str(data.get("scene_id", ""))
	world.chapter_id = str(data.get("chapter_id", ""))
	world.clock = int(data.get("clock", 0))
	var actor_data: Dictionary = data.get("actors", {})
	for actor_id in actor_data:
		world.actors[str(actor_id)] = FacetsActorState.from_dict(actor_data[actor_id])
	world.objects = data.get("objects", {}).duplicate(true)
	world.facts = data.get("facts", {}).duplicate(true)
	world.zones = data.get("zones", {}).duplicate(true)
	world.counters = data.get("counters", {}).duplicate(true)
	world.opportunities = data.get("opportunities", {}).duplicate(true)
	world.retry_locks = data.get("retry_locks", {}).duplicate(true)
	world.objective_epochs = data.get("objective_epochs", {}).duplicate(true)
	world.refusals = data.get("refusals", {}).duplicate(true)
	world.grants = data.get("grants", {}).duplicate(true)
	world.expiring = data.get("expiring", []).duplicate(true)
	for chapter in data.get("completed_chapters", []):
		world.completed_chapters.append(str(chapter))
	world.awards = data.get("awards", {}).duplicate(true)
	return world


func copy() -> FacetsWorldSnapshot:
	return from_dict(to_dict())


func digest() -> String:
	return FacetsJson.digest(to_dict())
