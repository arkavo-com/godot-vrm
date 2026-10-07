@tool
class_name FacetsAdmissionProposal
extends RefCounted
## Proposed local admission of a portable character. Advisory until the host
## accepts it; it never replaces a live build by itself.

var character_id: String = ""
var policy_id: String = ""
## Preserved verbatim from the import.
var identity: Dictionary = {}
var build: FacetsBuild = FacetsBuild.new()
## [{kind, id, reason}] what was not admitted (Growth, equipment, powers...).
var exclusions: Array = []
var warnings: Array[String] = []
var explanation: Array[String] = []
## Source-labeled memory references (status "reference").
var memories: Array = []
var accomplishments: Array[String] = []
var extensions: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"policy_id": policy_id,
		"identity": identity.duplicate(true),
		"build": build.to_dict(),
		"exclusions": exclusions.duplicate(true),
		"warnings": warnings.duplicate(),
		"explanation": explanation.duplicate(),
		"memories": memories.duplicate(true),
		"accomplishments": accomplishments.duplicate(),
		"extensions": extensions.duplicate(true),
	}
