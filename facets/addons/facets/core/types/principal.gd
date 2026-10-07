@tool
class_name FacetsPrincipal
extends RefCounted
## Out-of-band authority for a command. Supplied by the host, never by a
## model or by request fields.

const KIND_HOST := "host"
const KIND_PLAYER := "player"
const KIND_AI := "ai"

var kind: String = KIND_PLAYER
var principal_id: String = ""
var actor_ids: Array[String] = []


static func host(p_id: String = "host") -> FacetsPrincipal:
	var principal := FacetsPrincipal.new()
	principal.kind = KIND_HOST
	principal.principal_id = p_id
	return principal


static func player(p_id: String, p_actor_ids: Array[String]) -> FacetsPrincipal:
	var principal := FacetsPrincipal.new()
	principal.kind = KIND_PLAYER
	principal.principal_id = p_id
	principal.actor_ids = p_actor_ids.duplicate()
	return principal


static func ai(p_id: String, p_actor_ids: Array[String]) -> FacetsPrincipal:
	var principal := player(p_id, p_actor_ids)
	principal.kind = KIND_AI
	return principal


func is_host() -> bool:
	return kind == KIND_HOST


func can_act_for(actor_id: String) -> bool:
	return is_host() or actor_ids.has(actor_id)
