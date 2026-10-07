@tool
class_name FacetsOpContext
extends RefCounted
## Inputs available to an allowlisted operation while it is evaluated.

## Staged world; effects are applied to it as they compile.
var world: FacetsWorldSnapshot
var registry: FacetsRegistry
var actor_id: String = ""
var target_ids: Array[String] = []
var helper_ids: Array[String] = []
var tool_ids: Array[String] = []
var event_id: String = ""
## Flags such as {"fear": true, "expires": "scene_end"}.
var tags: Dictionary = {}


static func make(p_world: FacetsWorldSnapshot, p_registry: FacetsRegistry, p_actor_id: String) -> FacetsOpContext:
	var context := FacetsOpContext.new()
	context.world = p_world
	context.registry = p_registry
	context.actor_id = p_actor_id
	return context


func actor() -> FacetsActorState:
	return world.actor(actor_id)


## Resolves an effect's "target" parameter to concrete actor IDs.
## "self" (default) is the acting actor, "helpers" the accepted helpers,
## "target" the first request target, anything else a literal actor ID.
func resolve_targets(target: String) -> Array[String]:
	var result: Array[String] = []
	match target:
		"", "self":
			result.append(actor_id)
		"helpers":
			result.append_array(helper_ids)
		"target":
			if not target_ids.is_empty():
				result.append(target_ids[0])
		_:
			result.append(target)
	return result
