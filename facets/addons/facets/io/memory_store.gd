@tool
class_name FacetsMemoryStore
extends FacetsSessionStore
## In-memory persistence port. Stores canonical JSON text so a restore goes
## through the same parsing path as a file. [member fail_next_writes] injects
## persistence failures for tests.

var text: String = ""
var writes: int = 0
var fail_next_writes: int = 0


func write_save(data: Dictionary) -> FacetsReply:
	if fail_next_writes > 0:
		fail_next_writes -= 1
		return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "Injected persistence failure.", "", true)
	text = FacetsJson.canonical(data)
	writes += 1
	return FacetsReply.success(writes)


func read_save() -> FacetsReply:
	if text.is_empty():
		return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "No save present.")
	return FacetsJson.parse(text, 64 * 1048576, 64)


func has_save() -> bool:
	return not text.is_empty()


## Copy of the stored text, e.g. to simulate loading on another machine.
func clone_store() -> FacetsMemoryStore:
	var copy := FacetsMemoryStore.new()
	copy.text = text
	return copy
