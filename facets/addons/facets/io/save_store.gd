@tool
class_name FacetsSessionStore
extends RefCounted
## PersistencePort: atomic durable session transactions and loading.
##
## [method write_save] must either durably replace the previous save with the
## complete new one or leave the previous save intact and report failure. A
## session never treats an in-memory success as a durable commit.


func write_save(_data: Dictionary) -> FacetsReply:
	return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "write_save is not implemented.", "", true)


func read_save() -> FacetsReply:
	return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "read_save is not implemented.")


func has_save() -> bool:
	return false
