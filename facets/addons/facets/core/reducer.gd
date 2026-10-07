@tool
class_name FacetsReducer
extends RefCounted
## Applies low-level state operations to a world snapshot.
##
## Every state change in a session journal is recorded as one of these ops,
## so replay reapplies exactly what happened without consulting dice or
## content scripts:
##   {"op": "set",    "path": [...], "before": v, "after": v}   (null = absent key)
##   {"op": "append", "path": [...], "value": v}
##   {"op": "remove", "path": [...], "value": v}
##   {"op": "add_actor", "actor": {...}}                         (admit a new actor)
##   {"op": "note",   ...}                                        (no state change)
## Each op checks its precondition, so a corrupt or reordered journal stops
## with an actionable error instead of silently diverging.

const OPS: Array[String] = ["set", "append", "remove", "add_actor", "note"]


static func set_op(path: Array, before: Variant, after: Variant) -> Dictionary:
	return {"op": "set", "path": path.duplicate(), "before": FacetsJson.clone(before), "after": FacetsJson.clone(after)}


static func append_op(path: Array, value: Variant) -> Dictionary:
	return {"op": "append", "path": path.duplicate(), "value": FacetsJson.clone(value)}


static func remove_op(path: Array, value: Variant) -> Dictionary:
	return {"op": "remove", "path": path.duplicate(), "value": FacetsJson.clone(value)}


static func note_op(kind: String, data: Dictionary = {}) -> Dictionary:
	var op := {"op": "note", "kind": kind}
	for key in data:
		op[key] = FacetsJson.clone(data[key])
	return op


## Applies ops in order to [param world] in place. On the first failure the
## world may be partially modified: callers always apply to a staged copy.
static func apply_ops(world: FacetsWorldSnapshot, ops: Array) -> FacetsReply:
	for index in ops.size():
		var error := apply_op(world, ops[index])
		if error != null:
			error.field_path = "ops[%d]" % index
			return FacetsReply.failure(error)
	return FacetsReply.success(ops.size())


static func apply_op(world: FacetsWorldSnapshot, op: Variant) -> FacetsError:
	if not op is Dictionary:
		return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Operation is not an object.")
	var kind := str(op.get("op", ""))
	if not OPS.has(kind):
		return FacetsError.make(FacetsError.UNKNOWN_OPERATION, "Unknown state operation '%s'." % kind)
	if kind == "note":
		return null
	if kind == "add_actor":
		var actor_data: Variant = op.get("actor", {})
		if not actor_data is Dictionary or str(actor_data.get("actor_id", "")).is_empty():
			return FacetsError.make(FacetsError.REPLAY_CORRUPT, "add_actor needs an actor record.")
		if world.has_actor(str(actor_data["actor_id"])):
			return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Actor %s already exists." % actor_data["actor_id"])
		world.add_actor(FacetsActorState.from_dict(actor_data))
		return null
	var path: Variant = op.get("path", [])
	if not path is Array or path.is_empty():
		return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Operation path is missing.")
	var container: Variant = _resolve_container(world, path)
	if container == null:
		return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Path %s does not exist." % str(path))
	var key: Variant = path[path.size() - 1]
	match kind:
		"set":
			var current: Variant = _read(container, key)
			if not FacetsJson.equal(current, op.get("before")):
				return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Path %s expected %s but found %s." % [str(path), FacetsJson.canonical(op.get("before")), FacetsJson.canonical(current)])
			return _write(container, key, op.get("after"))
		"append", "remove":
			var target: Variant = _read(container, key)
			if not target is Array:
				return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Path %s is not a list." % str(path))
			var value: Variant = op.get("value")
			if kind == "append":
				target.append(_coerce_for(target, value))
			else:
				var index := _index_of(target, value)
				if index < 0:
					return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Path %s does not contain %s." % [str(path), FacetsJson.canonical(value)])
				target.remove_at(index)
	return null


static func read_path(world: FacetsWorldSnapshot, path: Array) -> Variant:
	var container: Variant = _resolve_container(world, path)
	if container == null:
		return null
	return _read(container, path[path.size() - 1])


static func _resolve_container(root: Variant, path: Array) -> Variant:
	var node: Variant = root
	for index in range(path.size() - 1):
		node = _read(node, path[index])
		if node == null:
			return null
	return node


static func _read(node: Variant, key: Variant) -> Variant:
	if node is Dictionary:
		return node.get(key)
	if node is Array:
		var index := int(key)
		if index >= 0 and index < node.size():
			return node[index]
		return null
	if node is Object:
		var property := str(key)
		if property in node:
			return node.get(property)
	return null


static func _write(node: Variant, key: Variant, value: Variant) -> FacetsError:
	if node is Dictionary:
		if value == null:
			node.erase(key)
		else:
			node[key] = FacetsJson.clone(value)
		return null
	if node is Object:
		var property := str(key)
		if not property in node:
			return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Unknown property '%s'." % property)
		var current: Variant = node.get(property)
		if current is Array and value is Array:
			current.clear()
			for item in value:
				current.append(_coerce_for(current, item))
			return null
		if current is Dictionary and value is Dictionary:
			current.clear()
			current.merge(FacetsJson.clone(value))
			return null
		node.set(property, FacetsJson.clone(value))
		return null
	return FacetsError.make(FacetsError.REPLAY_CORRUPT, "Cannot write into %s." % type_string(typeof(node)))


static func _coerce_for(target: Array, value: Variant) -> Variant:
	if target.is_typed() and target.get_typed_builtin() == TYPE_STRING:
		return str(value)
	return FacetsJson.clone(value)


static func _index_of(target: Array, value: Variant) -> int:
	var wanted := FacetsJson.canonical(value)
	for index in target.size():
		if FacetsJson.canonical(target[index]) == wanted:
			return index
	return -1
