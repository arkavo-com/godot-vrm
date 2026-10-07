@tool
class_name FacetsValidationScanner
extends RefCounted
## Finds FACETS Resources in the project and validates them. Issues name the
## Resource and field so the dock can navigate to them. Exporting content is
## refused while any definition is invalid.

const SKIP_DIRS: Array[String] = [".godot", ".import", "build"]
const COMBAT_SCRIPT := "res://addons/facets_combat/combat.gd"


## Core registry plus optional packages (combat hooks) when installed, plus
## every non-core rules pack found under [param roots].
static func registry_for(roots: Array = ["res://"]) -> FacetsRegistry:
	var registry := FacetsRegistry.core()
	_register_optional_hooks(registry)
	for path in collect(roots):
		var resource := load(path)
		if resource is FacetsRulesPack and resource.pack_id != "facets.core" and not registry.pack_versions().has(resource.pack_id):
			registry.register_pack(resource)
	return registry


## Soft dependency: the combat package registers its operations and hooks
## when installed. Core and editor never require it.
static func _register_optional_hooks(registry: FacetsRegistry) -> void:
	if ResourceLoader.exists(COMBAT_SCRIPT):
		var combat: Script = load(COMBAT_SCRIPT)
		if combat != null and combat.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "register_hooks"):
			combat.call("register_hooks", registry)


static func collect(roots: Array) -> Array[String]:
	var result: Array[String] = []
	for root in roots:
		_walk(str(root), result)
	result.sort()
	return result


static func _walk(directory: String, result: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub in dir.get_directories():
		if SKIP_DIRS.has(sub) or sub.begins_with("."):
			continue
		_walk(directory.path_join(sub), result)
	for file in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			result.append(directory.path_join(file))


## Validates one Resource. Field paths are Resource property names.
static func validate_resource(resource: Resource, registry: FacetsRegistry) -> Array[FacetsError]:
	if resource is FacetsCharacterResource:
		return FacetsValidator.validate_character(resource, registry)
	if resource is FacetsActionResource:
		return _map_paths(FacetsValidator.validate_action(resource.to_dict(), registry, ""))
	if resource is FacetsTalentResource:
		return _map_paths(FacetsValidator.validate_talent(resource.to_dict(), registry, ""))
	if resource is FacetsConditionResource:
		return _map_paths(FacetsValidator.validate_condition(resource.to_dict(), ""))
	if resource is FacetsSkillResource:
		return _map_paths(FacetsValidator.validate_skill(resource.to_dict(), ""))
	if resource is FacetsArchetypeResource:
		return _map_paths(FacetsValidator.validate_creation(resource.build(), registry, ""))
	if resource is FacetsRulesPack:
		var errors: Array[FacetsError] = []
		var staged := FacetsRegistry.create() if resource.pack_id == "facets.core" else FacetsRegistry.core()
		_register_optional_hooks(staged)
		var reply := staged.register_pack(resource)
		if not reply.ok:
			errors.append_array(reply.errors)
		return errors
	return []


static func _map_paths(errors: Array[FacetsError]) -> Array[FacetsError]:
	for error in errors:
		var path := error.field_path.trim_prefix(".")
		path = path.replace("difficulty.kind", "difficulty_kind")
		if path.begins_with("prerequisites."):
			path = "prerequisite_" + path.trim_prefix("prerequisites.")
		if path.begins_with("facets."):
			path = "facets"
		error.field_path = path
	return errors


## Issues: [{path, type, field_path, code, message}].
static func scan(registry: FacetsRegistry, roots: Array = ["res://"]) -> Array:
	var issues: Array = []
	for path in collect(roots):
		var resource := load(path)
		if resource == null:
			continue
		var type_name := _type_name(resource)
		if type_name.is_empty():
			continue
		for error in validate_resource(resource, registry):
			issues.append({"path": path, "type": type_name, "field_path": error.field_path, "code": error.code, "message": error.message})
	return issues


static func _type_name(resource: Resource) -> String:
	var script := resource.get_script() as Script
	if script == null:
		return ""
	var global_name := str(script.get_global_name())
	return global_name if global_name.begins_with("Facets") else ""


## Writes a portable JSON pack of the actions under [param roots]. Refused
## while any FACETS definition has validation errors.
static func export_content(registry: FacetsRegistry, roots: Array, pack_id: String, output_path: String) -> FacetsReply:
	var issues := scan(registry, roots)
	if not issues.is_empty():
		return FacetsReply.fail(FacetsError.INELIGIBLE, "Export blocked: %d invalid definition(s). Fix the validation errors first." % issues.size(), issues[0]["path"])
	var pack := FacetsRulesPack.new()
	pack.pack_id = pack_id
	pack.dependencies = {"facets.core": FacetsRules.RULESET_VERSION}
	for path in collect(roots):
		var resource := load(path)
		if resource is FacetsActionResource:
			pack.actions.append(resource)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "Could not write %s." % output_path)
	file.store_string(FacetsJson.pretty(pack.to_dict()))
	file.close()
	return FacetsReply.success(output_path)


## Resolves "facet_set.force" style paths to [object, property] for
## inspector navigation.
static func resolve_field(resource: Resource, field_path: String) -> Array:
	var target: Object = resource
	var parts := field_path.split(".")
	var property := parts[0].get_slice("[", 0) if not parts.is_empty() else ""
	if parts.size() > 1 and property in target:
		var child: Variant = target.get(property)
		if child is Resource:
			return [child, parts[1].get_slice("[", 0)]
	return [target, property]
