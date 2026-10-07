@tool
class_name FacetsWeaponResource
extends Resource
## Weapon definition for the optional combat package.
## Range: close (same zone), ranged (same or adjacent zone, line of sight),
## long (also distant visible zones). Harm: light 1, standard 2, heavy 3.
## Heavy weapons forbid moving in the same turn as the attack.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("close", "ranged", "long") var range_band: String = "close"
@export_enum("light", "standard", "heavy") var harm_class: String = "standard"
## Compatible ammunition item; empty for weapons that need none.
@export var ammo_type: String = ""
@export var approaches: Array[FacetsApproachResource] = []


func to_dict() -> Dictionary:
	var approach_list: Array = []
	for approach in approaches:
		if approach != null:
			approach_list.append(approach.to_dict())
	return {"id": id, "display_name": display_name, "range_band": range_band, "harm_class": harm_class, "ammo_type": ammo_type, "approaches": approach_list}


static func from_dict(data: Dictionary) -> FacetsWeaponResource:
	var weapon := FacetsWeaponResource.new()
	weapon.id = str(data.get("id", ""))
	weapon.display_name = str(data.get("display_name", ""))
	weapon.range_band = str(data.get("range_band", "close"))
	weapon.harm_class = str(data.get("harm_class", "standard"))
	weapon.ammo_type = str(data.get("ammo_type", ""))
	for item in data.get("approaches", []):
		weapon.approaches.append(FacetsApproachResource.from_dict(item))
	return weapon
