class_name NightMarketDemo
extends RefCounted
## Night Market Delivery: scenario setup and game flow shared by the UI scene
## and the automated walkthrough tests. Everything goes through the public
## FACETS session API with an explicit player or host principal.

signal changed
signal logged(line: String)

const PACK_PATH := "res://examples/night_market/content/night_market_pack.tres"
const CHARACTER_PATHS := [
	"res://examples/night_market/content/characters/mara_vale.tres",
	"res://examples/night_market/content/characters/iris_kade.tres",
	"res://examples/night_market/content/characters/rook.tres",
	"res://examples/night_market/content/characters/tamsin.tres",
]
const MARA := "demo.mara_vale"
const IRIS := "demo.iris_kade"
const ROOK := "npc.rook"
const TAMSIN := "npc.tamsin"
const SCENE_GATE := "nm.gate"
const SCENE_CLINIC := "nm.clinic"
const CHAPTER := "nm.chapter1"
## Delivery window: the package must arrive while the clock is at most this.
const DEADLINE := 3
## Written on every transaction and resumed on launch.
const AUTOSAVE := "user://night_market/autosave.json"
## Manual save slot used by Save and Load.
const SAVE_SLOT := "user://night_market/save.json"

var registry: FacetsRegistry
var session: FacetsSession
var store: FacetsSessionStore
var player := FacetsPrincipal.player("player", [MARA, IRIS])
var host := FacetsPrincipal.host("night_market")
var log_lines: Array[String] = []
var _request_counter: int = 0


## Options: "store" (FacetsSessionStore written on every transaction;
## default the autosave file), "resume" (continue from that store when it
## holds a valid save), "seed" (int), "dice" (Array of [d1, d2] pairs for
## scripted runs).
static func create(options: Dictionary = {}) -> FacetsReply:
	var demo := NightMarketDemo.new()
	demo.registry = build_registry()
	var autosave: FacetsSessionStore = options.get("store") if options.get("store") is FacetsSessionStore else FacetsFileStore.at(AUTOSAVE)
	if bool(options.get("resume", false)) and autosave.has_save():
		var resumed := FacetsSession.restore(autosave, demo.registry)
		if resumed.ok:
			demo.session = resumed.value
			demo.store = autosave
			demo._log("Journey resumed from the autosave.%s" % (" A choice is still waiting." if demo.session.has_pending() else ""))
			return FacetsReply.success(demo)
	var with_store := options.duplicate()
	with_store["store"] = autosave
	var reply := demo.new_journey(with_store)
	if not reply.ok:
		return reply
	return FacetsReply.success(demo)


static func build_registry() -> FacetsRegistry:
	var registry := FacetsRegistry.core()
	var pack := load(PACK_PATH) as FacetsRulesPack
	var reply := registry.register_pack(pack)
	assert(reply.ok, "Night Market pack invalid: %s" % str(reply))
	return registry


## Fresh scenario state. [param profiles] carries profile records
## (accomplishments) across journey resets.
static func initial_world(profiles: Dictionary = {}) -> FacetsWorldSnapshot:
	var world := FacetsWorldSnapshot.new()
	world.scene_id = SCENE_GATE
	world.chapter_id = CHAPTER
	for path in CHARACTER_PATHS:
		var definition := load(path) as FacetsCharacterResource
		var state := FacetsActorState.from_character(definition)
		state.zone_id = "street"
		if profiles.has(state.actor_id):
			state.profile = profiles[state.actor_id].duplicate(true)
		world.add_actor(state)
	world.objects = {
		"market_gate": {"open": false},
		"service_door": {"open": false},
		"controller": {"accessible": true, "locked": false},
		"roof_hatch": {"reachable": true},
		"package": {"delivered": false, "late": false},
		"passenger": {"helped": false},
	}
	world.facts = {
		"fact.market_curfew": {"value": true, "visibility": "public", "label": "The night market locks down at curfew."},
		"fact.rook_paid": {"value": true, "visibility": "private", "owner_id": ROOK, "label": "Rook takes money from the fixer."},
		"fact.passenger_lead": {"value": true, "visibility": "private", "evidence_id": "evidence.bag_seal", "label": "Tamsin saw a courier dragged toward the canal."},
		"fact.patrol_route": {"value": true, "visibility": "private", "label": "The patrol loops past the fish stalls every twenty minutes."},
		"fact.access_log": {"value": true, "visibility": "private", "label": "The access log shows the fixer's crew entered at dusk."},
		"fact.rooftop_view": {"value": true, "visibility": "private", "label": "Couriers are moved along the canal walkway."},
		"fact.canal_lead": {"value": true, "visibility": "private", "label": "The canal crew uses the old pump house as a drop point."},
		"fact.canal_footprints": {"value": true, "visibility": "private", "evidence_id": "evidence.mud", "label": "Fresh boot prints lead under the pump house door."},
	}
	world.zones = {"street": {"adjacent": ["hall", "roof"]}, "roof": {"adjacent": ["street", "hall"]}, "hall": {"adjacent": ["street"]}, "canal": {"adjacent": ["street"]}}
	world.counters = {"patrol": 0}
	world.refusals = {ROOK: ["fixer_office"]}
	return world


## Starts a new journey under the standard policy. Profile records from the
## current session survive; everything else is fresh.
func new_journey(options: Dictionary = {}) -> FacetsReply:
	var profiles := {}
	if session != null:
		var world := session.snapshot()
		for actor_id in world.actors:
			profiles[actor_id] = world.actor(actor_id).profile.duplicate(true)
	var target_store: Variant = options.get("store", store)
	if target_store == null:
		target_store = FacetsFileStore.at(AUTOSAVE)
	var dice: FacetsDiceSource
	if options.has("dice"):
		dice = FacetsDiceSource.fixed(options["dice"])
	else:
		dice = FacetsDiceSource.seeded(int(options.get("seed", Time.get_ticks_usec())))
	var reply := FacetsSession.create(registry, initial_world(profiles), {"store": target_store, "dice": dice, "session_id": "night_market"})
	if not reply.ok:
		return reply
	session = reply.value
	store = target_store
	log_lines.clear()
	_log("Night Market Delivery begins. Curfew is coming; the package must arrive before the clock passes %d." % DEADLINE)
	changed.emit()
	return FacetsReply.success(session)


func _request_id(prefix: String) -> String:
	_request_counter += 1
	return "%s-%d-%d-%d" % [prefix, session.last_sequence(), Time.get_ticks_usec(), _request_counter]


func _log(line: String) -> void:
	log_lines.append(line)
	logged.emit(line)


func actor(actor_id: String) -> FacetsActorState:
	return session.actor_state(actor_id)


func scene_id() -> String:
	return session.snapshot().scene_id


func pending() -> FacetsResolutionEvent:
	return session.pending_event()


## Catalog entries for the current scene (available or not, with reasons).
func actions_for(actor_id: String) -> Array:
	var result: Array = []
	var current := scene_id()
	for entry in session.catalog(actor_id, player):
		var action := registry.get_action(entry["action_id"])
		var in_scene := false
		for ref in action.get("requirements", []):
			if ref["op"] == "require.scene" and ref["params"]["scene_id"] == current:
				in_scene = true
		if in_scene:
			entry["name"] = action.get("display_name", entry["action_id"])
			result.append(entry)
	return result


func preview(actor_id: String, action_id: String, approach_id: String, helper_id: String = "", talent_ids: Array = [], evidence_id: String = "") -> FacetsReply:
	var request := session.suggest_request(actor_id, action_id, approach_id)
	if not helper_id.is_empty():
		request.with_helpers([helper_id])
	if not talent_ids.is_empty():
		request.with_talents(talent_ids, evidence_id)
	return session.preview(request, player)


func commit(check_preview: FacetsCheckPreview, push: bool) -> FacetsReply:
	var reply := session.commit(check_preview.token, {"push": push}, _request_id("commit"))
	if reply.ok:
		_after_event(reply.value)
	return reply


func choose(option_id: String) -> FacetsReply:
	var event := pending()
	if event == null:
		return FacetsReply.fail(FacetsError.NOT_PENDING, "Nothing is waiting for a choice.")
	var reply := session.choose(event.event_id, event.pending_decision.decision_id, option_id, _request_id("choose"))
	if reply.ok:
		_after_event(reply.value)
	return reply


func abandon() -> FacetsReply:
	var event := pending()
	if event == null:
		return FacetsReply.fail(FacetsError.NOT_PENDING, "Nothing is waiting for a choice.")
	var reply := session.abandon(event.event_id, _request_id("abandon"))
	if reply.ok:
		_after_event(reply.value)
	return reply


func _after_event(event: FacetsResolutionEvent) -> void:
	if event.is_pending():
		if event.kind == "check":
			_log("%s rolled %s: total %d vs %d (%s)." % [actor(event.actor_id).display_name, "+".join(event.dice.map(func(d: Variant) -> String: return str(d))), int(event.base["total"]), int(event.base["target"]), FacetsSession._band_label(str(event.base["band"]))])
		_log(event.pending_decision.prompt)
	else:
		_log(FacetsAiViews.fallback_narration(FacetsAiViews.narration_view(session, event, event.actor_id)))
		if event.kind == "identity" and bool(event.record.get("accepted", false)):
			session.apply_host_effects(MARA, [{"op": "fact.reveal", "params": {"fact_id": "fact.passenger_lead"}, "label": "Tamsin's lead"}], "Tamsin shares what she saw", host, _request_id("lead"))
			_log("Tamsin tells Mara what she saw. Resolve +%d." % int(event.record["amount"]))
		if event.kind == "check" and event.action_id == "nm.deliver_package" and event.final_band == FacetsRules.BAND_SUCCESS:
			_finish_delivery(event.actor_id)
	changed.emit()


## Mara's identity trigger: stop for the passenger's story at the cost of the
## delivery window. Offered by the scenario (host), answered by the player.
func offer_passenger_lead() -> FacetsReply:
	if scene_id() != SCENE_GATE:
		return FacetsReply.fail(FacetsError.NOT_APPLICABLE, "Tamsin is only at the market gate.")
	var reply := session.offer_identity_trigger(MARA, "mara.passenger_lead", host, _request_id("offer"))
	if reply.ok:
		_after_event(reply.value)
	return reply


func deliver(actor_id: String) -> FacetsReply:
	var check_preview := preview(actor_id, "nm.deliver_package", "hand_over")
	if not check_preview.ok:
		return check_preview
	return commit(check_preview.value, false)


func _finish_delivery(actor_id: String) -> void:
	var world := session.snapshot()
	var late: bool = world.clock > DEADLINE or world.fact_value("fact.window_missed") == true
	var effects: Array = [{"op": "actor.accomplishment", "params": {"text": "Delivered the sealed package through the Night Market"}, "label": "Accomplishment"}]
	if late:
		effects.append({"op": "object.set_flag", "params": {"object_id": "package", "key": "late", "value": true}, "label": "The package arrived late"})
	session.apply_host_effects(actor_id, effects, "Delivery outcome", host, _request_id("delivery"))
	var milestone := session.award_milestone(actor_id, "nm.delivery", "small", "nm.chapter1.package_delivered", host, _request_id("milestone"))
	_log("The package %s. %s" % ["arrived late" if late else "arrived on time", "Milestone: +1 Growth." if milestone.ok else ""])


func use_steady_voice(actor_id: String, ally_id: String) -> FacetsReply:
	var reply := session.use_steady_voice(actor_id, ally_id, player, _request_id("steady"))
	if reply.ok:
		_log("%s steadies %s (strain %d)." % [actor(actor_id).display_name, actor(ally_id).display_name, int(reply.value.record["resource_deltas"]["ally_strain"])])
		changed.emit()
	return reply


func take_breather(actor_id: String) -> FacetsReply:
	var reply := session.take_breather(actor_id, "nm.breather.%s" % scene_id(), player, _request_id("breather"))
	if reply.ok:
		_log("%s takes a breather (strain %d)." % [actor(actor_id).display_name, int(reply.value.record["resource_deltas"]["strain"])])
		changed.emit()
	return reply


## Ends the market scene and starts the clinic scene, where earlier
## consequences persist. The host authorizes one breather between scenes.
func go_to_clinic() -> FacetsReply:
	if scene_id() == SCENE_CLINIC:
		return FacetsReply.fail(FacetsError.ALREADY_USED, "Already at the clinic.")
	var reply := session.start_scene(SCENE_CLINIC, CHAPTER, host, _request_id("scene"))
	if not reply.ok:
		return reply
	session.grant_opportunity("nm.breather.%s" % SCENE_CLINIC, "breather", host, _request_id("opportunity"))
	_log("Later, at the clinic.")
	for line in consequences():
		_log("- " + line)
	changed.emit()
	return reply


## Retained consequences visible in the clinic scene.
func consequences() -> Array[String]:
	var world := session.snapshot()
	var lines: Array[String] = []
	if world.fact_value("fact.grid_trace") == true:
		lines.append("Your trace in the market grid put the fixer's watchers on alert (-1 to slip away).")
	if world.object_flag("controller", "locked") == true:
		lines.append("The service door controller is locked down for good.")
	if int(world.counters.get("patrol", 0)) > 0:
		lines.append("Patrols have been stepped up (level %d)." % int(world.counters["patrol"]))
	if world.fact_value("fact.rook_alerted") == true:
		lines.append("Rook remembers you raised trouble at his gate.")
	if world.object_flag("package", "delivered") == true:
		lines.append("The package was delivered%s." % (" late; the doctor is cold toward you (-1)" if world.object_flag("package", "late") == true else " on time"))
	else:
		lines.append("The package was never delivered.")
	if world.actor(MARA).knows("fact.passenger_lead"):
		lines.append("Mara carries Tamsin's lead: a courier was dragged toward the canal.")
	if world.object_flag("passenger", "helped") == true:
		lines.append("Tamsin is safe at the clinic.")
	return lines


## Writes the manual save slot (or [param target]). The autosave keeps
## running separately.
func save_game(target: FacetsSessionStore = null) -> FacetsReply:
	var reply := session.save(target if target != null else FacetsFileStore.at(SAVE_SLOT))
	_log("Saved." if reply.ok else "Save failed: %s" % reply.error.message)
	return reply


## Restores the manual save slot (or [param source]); play continues with
## the autosave store attached.
func load_game(source: FacetsSessionStore = null, dice: FacetsDiceSource = null) -> FacetsReply:
	var from := source if source != null else FacetsFileStore.at(SAVE_SLOT)
	var options := {"store": store if store != null else from}
	if dice != null:
		options["dice"] = dice
	var reply := FacetsSession.restore(from, registry, options)
	if not reply.ok:
		_log("Load failed: %s" % reply.error.message)
		return reply
	session = reply.value
	var persisted := session.save(store) if store != null else FacetsReply.success(true)
	if not persisted.ok:
		_log("Loaded, but the autosave could not be updated: %s" % persisted.error.message)
	_log("Loaded.%s" % (" A choice is still waiting." if session.has_pending() else ""))
	changed.emit()
	return reply


## Demo-only fixed dice: visibly marked in the UI and never offered in
## release exports.
static func fixed_dice_allowed(debug_build: bool = OS.is_debug_build()) -> bool:
	return debug_build


func queue_fixed_dice(pair: Vector2i) -> bool:
	if not fixed_dice_allowed():
		return false
	session.dice_source().push_fixed(pair)
	_log("[DEMO FIXED DICE] next roll will be %d+%d." % [pair.x, pair.y])
	return true
