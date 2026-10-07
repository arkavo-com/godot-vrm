@tool
class_name FacetsFacetSet
extends Resource
## The six facet ratings. Standard creation: start at 2, add six points,
## cap 4, total 18. Progressed ratings may reach 5.

@export_range(1, 6) var force: int = 2:
	set(value):
		force = value
		emit_changed()
@export_range(1, 6) var agility: int = 2:
	set(value):
		agility = value
		emit_changed()
@export_range(1, 6) var cunning: int = 2:
	set(value):
		cunning = value
		emit_changed()
@export_range(1, 6) var empathy: int = 2:
	set(value):
		empathy = value
		emit_changed()
@export_range(1, 6) var tenacity: int = 2:
	set(value):
		tenacity = value
		emit_changed()
@export_range(1, 6) var sense: int = 2:
	set(value):
		sense = value
		emit_changed()


func get_rating(facet_id: String) -> int:
	if not FacetsRules.FACETS.has(facet_id):
		return 0
	return int(get(facet_id))


func set_rating(facet_id: String, value: int) -> void:
	if FacetsRules.FACETS.has(facet_id):
		set(facet_id, value)


func total() -> int:
	var sum := 0
	for facet_id in FacetsRules.FACETS:
		sum += get_rating(facet_id)
	return sum


func to_dict() -> Dictionary:
	var result := {}
	for facet_id in FacetsRules.FACETS:
		result[facet_id] = get_rating(facet_id)
	return result


static func from_dict(data: Dictionary) -> FacetsFacetSet:
	var facet_set := FacetsFacetSet.new()
	for facet_id in FacetsRules.FACETS:
		facet_set.set_rating(facet_id, int(data.get(facet_id, FacetsRules.FACET_BASELINE)))
	return facet_set
