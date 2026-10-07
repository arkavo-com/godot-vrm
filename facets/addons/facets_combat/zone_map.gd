@tool
class_name FacetsZoneMap
extends RefCounted
## Abstract combat zones. Each zone lists adjacent zones, zones visible from
## it (line of sight) and whether it offers cover.

var zones: Dictionary = {}


static func from_dict(data: Dictionary) -> FacetsZoneMap:
	var map := FacetsZoneMap.new()
	map.zones = FacetsJson.clone(data)
	return map


func has_zone(zone_id: String) -> bool:
	return zones.has(zone_id)


func adjacent(a: String, b: String) -> bool:
	return zones.get(a, {}).get("adjacent", []).has(b) or zones.get(b, {}).get("adjacent", []).has(a)


## Same and adjacent zones are visible unless "blocked" lists them.
func visible(from_zone: String, to_zone: String) -> bool:
	var zone: Dictionary = zones.get(from_zone, {})
	if zone.get("blocked", []).has(to_zone):
		return false
	return from_zone == to_zone or adjacent(from_zone, to_zone) or zone.get("visible", []).has(to_zone)


func has_cover(zone_id: String) -> bool:
	return bool(zones.get(zone_id, {}).get("cover", false))


## "same", "adjacent" or "distant".
func band(a: String, b: String) -> String:
	if a == b:
		return "same"
	if adjacent(a, b):
		return "adjacent"
	return "distant"
