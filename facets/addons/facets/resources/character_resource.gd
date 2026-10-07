@tool
class_name FacetsCharacterResource
extends Resource
## Authoring definition of a character. This is not a live save object:
## sessions copy it into [FacetsActorState] through an explicit factory, so
## several sessions can share one definition safely.

@export var id: String = "":
	set(value):
		id = value
		emit_changed()
@export var display_name: String = "":
	set(value):
		display_name = value
		emit_changed()
@export_enum("player", "npc") var controller: String = "player":
	set(value):
		controller = value
		emit_changed()
@export var identity: FacetsIdentityResource:
	set(value):
		identity = value
		emit_changed()
@export var facet_set: FacetsFacetSet:
	set(value):
		facet_set = value
		emit_changed()
## skill_id -> rank. Missing known skills mean rank 0.
@export var skills: Dictionary = {}:
	set(value):
		skills = value
		emit_changed()
@export var talents: Array[String] = []:
	set(value):
		talents = value
		emit_changed()
@export var capabilities: Array[String] = []:
	set(value):
		capabilities = value
		emit_changed()
@export var bonds: Array[FacetsBondResource] = []:
	set(value):
		bonds = value
		emit_changed()
@export var identity_triggers: Array[FacetsIdentityTriggerResource] = []:
	set(value):
		identity_triggers = value
		emit_changed()
## Starting tools and consumables: item_id -> count.
@export var items: Dictionary = {}:
	set(value):
		items = value
		emit_changed()
## Optional admission preferences; empty means "the build above".
@export var preferred_build: Dictionary = {}:
	set(value):
		preferred_build = value
		emit_changed()


func build() -> FacetsBuild:
	var result := FacetsBuild.new()
	var source := facet_set if facet_set != null else FacetsFacetSet.new()
	for facet_id in FacetsRules.FACETS:
		result.facets[facet_id] = source.get_rating(facet_id)
	for skill_id in skills:
		result.skills[str(skill_id)] = int(skills[skill_id])
	for talent_id in talents:
		result.talents.append(talent_id)
	for capability_id in capabilities:
		result.capabilities.append(capability_id)
	return result


func identity_dict() -> Dictionary:
	if identity == null:
		return FacetsIdentityResource.new().to_dict()
	return identity.to_dict()


func preferred_build_dict() -> Dictionary:
	if not preferred_build.is_empty():
		return preferred_build.duplicate(true)
	return build().to_dict()


func to_dict() -> Dictionary:
	var bond_list: Array = []
	for bond in bonds:
		if bond != null:
			bond_list.append(bond.to_dict())
	var trigger_list: Array = []
	for trigger in identity_triggers:
		if trigger != null:
			trigger_list.append(trigger.to_dict())
	return {
		"id": id,
		"display_name": display_name,
		"controller": controller,
		"identity": identity_dict(),
		"build": build().to_dict(),
		"bonds": bond_list,
		"identity_triggers": trigger_list,
		"items": items.duplicate(),
		"preferred_build": preferred_build_dict(),
	}


static func from_dict(data: Dictionary) -> FacetsCharacterResource:
	var character := FacetsCharacterResource.new()
	character.id = str(data.get("id", ""))
	character.display_name = str(data.get("display_name", ""))
	character.controller = str(data.get("controller", "player"))
	character.identity = FacetsIdentityResource.from_dict(data.get("identity", {}))
	var build_data: Dictionary = data.get("build", {})
	character.facet_set = FacetsFacetSet.from_dict(build_data.get("facets", {}))
	for skill_id in build_data.get("skills", {}):
		character.skills[str(skill_id)] = int(build_data["skills"][skill_id])
	for talent_id in build_data.get("talents", []):
		character.talents.append(str(talent_id))
	for capability_id in build_data.get("capabilities", []):
		character.capabilities.append(str(capability_id))
	for item in data.get("bonds", []):
		if item is Dictionary:
			character.bonds.append(FacetsBondResource.from_dict(item))
	for item in data.get("identity_triggers", []):
		if item is Dictionary:
			character.identity_triggers.append(FacetsIdentityTriggerResource.from_dict(item))
	var item_data: Variant = data.get("items", {})
	if item_data is Dictionary:
		for item_id in item_data:
			character.items[str(item_id)] = int(item_data[item_id])
	var preferred: Variant = data.get("preferred_build", {})
	character.preferred_build = preferred.duplicate(true) if preferred is Dictionary else {}
	return character
