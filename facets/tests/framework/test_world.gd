class_name FacetsTestWorld
extends RefCounted
## Shared fixture content for session-level tests: Mara Vale (source build),
## Iris Kade (Empathy/Tenacity), an NPC guard and a set of test actions.

const MARA := {
	"facets": {"force": 2, "agility": 4, "cunning": 3, "empathy": 3, "tenacity": 2, "sense": 4},
	"skills": {"stealth": 2, "investigation": 2, "influence": 2, "technology": 2, "athletics": 1, "sleight": 1, "survival": 1, "medicine": 1},
	"talents": ["core.second_look", "core.field_engineer"],
	"capabilities": [],
}
const IRIS := {
	"facets": {"force": 2, "agility": 2, "cunning": 3, "empathy": 4, "tenacity": 4, "sense": 3},
	"skills": {"influence": 2, "medicine": 2, "performance": 2, "survival": 2, "investigation": 1, "athletics": 1, "fighting": 1, "craft": 1},
	"talents": ["core.steady_voice", "core.bargain_maker"],
	"capabilities": [],
}
const GUARD := {
	"facets": {"force": 3, "agility": 3, "cunning": 2, "empathy": 2, "tenacity": 4, "sense": 4},
	"skills": {"fighting": 2, "influence": 2, "investigation": 2, "athletics": 2, "marksmanship": 2, "survival": 2},
	"talents": ["core.trail_reader", "core.second_look"],
	"capabilities": [],
}


static func eff(op: String, params: Dictionary, label: String = "") -> Dictionary:
	return {"op": op, "params": params, "label": label}


static func actions() -> Array:
	return [
		{
			"id": "test.bypass", "version": 1, "display_name": "Bypass the controller", "objective_id": "obj.door",
			"approaches": [{"id": "tech", "facet": "cunning", "skill": "technology"}, {"id": "brute", "facet": "force", "skill": "athletics"}],
			"requirements": [eff("require.accessible_controller", {"object_id": "controller"}, "The controller must be reachable and unlocked.")],
			"required_tools": ["tool.signal_kit"], "consumable_substitutes": ["item.scrap_wire"],
			"difficulty": {"kind": "fixed", "target": 13},
			"allows_costly_success": true,
			"costly_options": [{"id": "trace", "label": "Leave a trace in the grid", "effects": [eff("world.mark_trace", {"trace_id": "fact.grid_trace"}, "Trace marked")]}],
			"success_effects": [eff("object.set_flag", {"object_id": "door", "key": "open", "value": true}, "Door opens")],
			"failure_effects": [eff("world.counter_add", {"counter_id": "patrol", "amount": 1}, "Patrol advances"), eff("object.set_flag", {"object_id": "controller", "key": "locked", "value": true}, "Controller locks")],
			"strong_benefits": [
				{"id": "silent", "label": "Silent entry", "effects": [eff("actor.flag", {"key": "silent_entry", "value": true})]},
				{"id": "log", "label": "Copy the access log", "effects": [eff("fact.reveal", {"fact_id": "fact.access_log"})]},
			],
			"default_benefit_id": "silent",
			"stakes": {"success": "The door opens.", "failure": "The patrol advances and the controller locks."},
			"retry_policy": "lock_until_change",
		},
		{
			"id": "test.search", "version": 1, "display_name": "Search the stall", "objective_id": "obj.lead",
			"approaches": [{"id": "look", "facet": "sense", "skill": "investigation"}, {"id": "track", "facet": "sense", "skill": "survival"}],
			"difficulty": {"kind": "fixed", "target": 15},
			"success_effects": [eff("fact.reveal", {"fact_id": "fact.lead"}, "You find the lead")],
			"failure_effects": [],
			"alternate_evidence_sources": ["evidence.bag_seal", "evidence.cctv"],
			"revealable_facts": ["fact.trail", "fact.secret_trail"],
			"retry_policy": "lock_until_change",
		},
		{
			"id": "test.sneak", "version": 1, "display_name": "Sneak past", "objective_id": "obj.sneak",
			"approaches": [{"id": "quiet", "facet": "agility", "skill": "stealth"}],
			"difficulty": {"kind": "fixed", "target": 9},
			"success_effects": [eff("actor.zone", {"zone_id": "hall"}, "You slip inside")],
			"strong_benefits": [{"id": "unseen", "label": "Completely unseen", "effects": [eff("actor.flag", {"key": "unseen", "value": true})]}],
			"retry_policy": "repeatable",
		},
		{
			"id": "test.persuade", "version": 1, "display_name": "Persuade the guard", "objective_id": "obj.gate",
			"approaches": [{"id": "plead", "facet": "empathy", "skill": "influence"}],
			"difficulty": {"kind": "opposed", "defender_id": "npc.guard", "defense_facet": "tenacity", "defense_skill": "influence"},
			"relationship": {"other_id": "npc.guard", "dimension": "trust"},
			"allows_costly_success": true,
			"costly_options": [{"id": "favor", "label": "Owe the guard a favor", "effects": [eff("bond.add_obligation", {"other_id": "npc.guard", "obligation": "favor"}, "You owe a favor")]}],
			"success_effects": [eff("npc.grant", {"npc_id": "npc.guard", "topic": "gate"}, "The guard opens the gate")],
			"failure_effects": [eff("actor.strain", {"amount": 1}, "Rebuffed")],
			"strong_benefits": [
				{"id": "route", "label": "Guard shares the patrol route", "effects": [eff("fact.reveal", {"fact_id": "fact.patrol_route"})]},
				{"id": "vouch", "label": "Guard vouches for you", "effects": [eff("bond.adjust", {"other_id": "npc.guard", "dimension": "trust", "amount": 1})], "requires_consent": true},
			],
			"lesser_concessions": [{"id": "pass", "label": "A one-time side pass", "effects": [eff("actor.item_add", {"item_id": "item.side_pass", "amount": 1})]}],
			"retry_policy": "lock_until_change",
		},
		{
			"id": "test.vault", "version": 1, "display_name": "Talk the guard into opening the vault", "objective_id": "obj.vault",
			"approaches": [{"id": "plead", "facet": "empathy", "skill": "influence"}],
			"difficulty": {"kind": "fixed", "target": 11},
			"allows_costly_success": true,
			"costly_options": [{"id": "owe", "label": "Owe him", "effects": [eff("bond.add_obligation", {"other_id": "npc.guard", "obligation": "vault"})]}],
			"success_effects": [eff("npc.grant", {"npc_id": "npc.guard", "topic": "vault"}, "Guard opens the vault")],
			"failure_effects": [],
			"strong_benefits": [{"id": "info", "label": "He explains why not", "effects": [eff("fact.reveal", {"fact_id": "fact.vault_reason"})]}],
			"retry_policy": "repeatable",
		},
		{
			"id": "test.scare", "version": 1, "display_name": "Face the crowd", "objective_id": "obj.crowd", "fear": true,
			"approaches": [{"id": "brave", "facet": "tenacity", "skill": "performance"}],
			"difficulty": {"kind": "fixed", "target": 19},
			"failure_effects": [eff("actor.strain", {"amount": 2}, "Fear takes hold")],
			"allow_resolve": false,
			"retry_policy": "repeatable",
		},
		{
			"id": "test.routine", "version": 1, "display_name": "Hand over the package", "objective_id": "obj.deliver",
			"approaches": [{"id": "give", "facet": "empathy", "skill": "influence"}],
			"difficulty": {"kind": "routine", "target": 11},
			"success_effects": [eff("object.set_flag", {"object_id": "package", "key": "delivered", "value": true}, "Delivered")],
			"retry_policy": "repeatable",
		},
		{
			"id": "test.broken", "version": 1, "display_name": "Spend a missing token", "objective_id": "obj.broken",
			"approaches": [{"id": "try", "facet": "cunning", "skill": "sleight"}],
			"difficulty": {"kind": "fixed", "target": 2},
			"success_effects": [eff("actor.item_add", {"item_id": "item.never_had", "amount": -1}, "Spend token")],
			"retry_policy": "repeatable",
		},
	]


static func registry() -> FacetsRegistry:
	var result := FacetsRegistry.core()
	for action in actions():
		var reply := result.add_action(action)
		assert(reply.ok, "test action invalid: %s" % str(reply))
	return result


static func actor(actor_id: String, display_name: String, build: Dictionary, controller: String = "player") -> FacetsActorState:
	var state := FacetsActorState.new()
	state.actor_id = actor_id
	state.display_name = display_name
	state.controller = controller
	state.build = FacetsBuild.from_dict(build)
	state.base_build = state.build.to_dict()
	return state


static func world() -> FacetsWorldSnapshot:
	var snapshot := FacetsWorldSnapshot.new()
	snapshot.scene_id = "scene.market"
	snapshot.chapter_id = "chapter.1"
	var mara := actor("mara", "Mara Vale", MARA)
	mara.items = {"tool.signal_kit": 1, "item.scrap_wire": 2}
	mara.identity = {"name": "Mara Vale", "hindrance": "Pursues disappearance leads despite urgent deliveries"}
	mara.identity_triggers = [{
		"id": "mara.lead", "display_name": "Chase the lead", "description": "Investigate the stranded passenger instead of delivering on time.",
		"disadvantage_label": "Miss the delivery window",
		"disadvantage_effects": [eff("fact.set", {"fact_id": "fact.window_missed", "value": true}, "Delivery window missed")],
	}]
	snapshot.add_actor(mara)
	var iris := actor("iris", "Iris Kade", IRIS)
	snapshot.add_actor(iris)
	var guard := actor("npc.guard", "Market Guard", GUARD, "npc")
	snapshot.add_actor(guard)
	snapshot.objects = {"controller": {"accessible": true, "locked": false}, "door": {"open": false}, "package": {"delivered": false}}
	snapshot.facts = {
		"fact.trail": {"value": true, "visibility": "private", "evidence_id": "evidence.footprints", "label": "Footprints lead to the canal"},
		"fact.secret_trail": {"value": true, "visibility": "private", "evidence_id": "", "label": "Unsupported rumor"},
		"fact.guard_secret": {"value": true, "visibility": "private", "owner_id": "npc.guard", "label": "The guard is paid by the fixer"},
		"fact.market_open": {"value": true, "visibility": "public", "label": "The market is open"},
	}
	snapshot.refusals = {"npc.guard": ["vault"]}
	snapshot.counters = {"patrol": 0}
	return snapshot


## Session with injected dice and an attached memory store.
static func session(dice: Array = [], store: FacetsSessionStore = null) -> FacetsSession:
	var options := {"dice": FacetsDiceSource.fixed(dice)}
	options["store"] = store if store != null else FacetsMemoryStore.new()
	var reply := FacetsSession.create(registry(), world(), options)
	assert(reply.ok, str(reply))
	return reply.value


static func bypass_request() -> FacetsActionRequest:
	return FacetsActionRequest.make("mara", "test.bypass", "tech").with_tools(["tool.signal_kit"])
