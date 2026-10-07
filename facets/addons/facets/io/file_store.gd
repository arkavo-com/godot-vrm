@tool
class_name FacetsFileStore
extends FacetsSessionStore
## File-backed persistence port.
##
## Writes a complete temporary save, re-reads and validates it, keeps the
## previous save as "<path>.bak", then atomically renames the temporary file
## over the save. If the primary file is unreadable, [method read_save]
## recovers from the backup.

var path: String = ""
var max_bytes: int = 64 * 1048576


static func at(p_path: String) -> FacetsFileStore:
	var store := FacetsFileStore.new()
	store.path = p_path
	return store


func _absolute(suffix: String = "") -> String:
	return ProjectSettings.globalize_path(path + suffix)


func write_save(data: Dictionary) -> FacetsReply:
	var text := FacetsJson.canonical(data)
	var target := _absolute()
	var temp := _absolute(".tmp")
	var backup := _absolute(".bak")
	var directory := target.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return _fail("could not create save directory (%s)" % error_string(made))
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _fail("could not open temporary save (%s)" % error_string(FileAccess.get_open_error()))
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _fail("temporary save write failed (%s)" % error_string(write_error))
	var verify := FacetsJson.parse(FileAccess.get_file_as_string(temp), max_bytes, 64)
	if not verify.ok or FacetsJson.canonical(verify.value) != text:
		DirAccess.remove_absolute(temp)
		return _fail("temporary save did not validate")
	if FileAccess.file_exists(target):
		var copied := DirAccess.copy_absolute(target, backup)
		if copied != OK:
			DirAccess.remove_absolute(temp)
			return _fail("could not retain previous save (%s)" % error_string(copied))
	var renamed := DirAccess.rename_absolute(temp, target)
	if renamed != OK:
		return _fail("atomic replace failed (%s)" % error_string(renamed))
	return FacetsReply.success(target)


func read_save() -> FacetsReply:
	var primary := _read_file(_absolute())
	if primary.ok:
		return primary
	var backup := _read_file(_absolute(".bak"))
	if backup.ok:
		return backup
	return primary


func has_save() -> bool:
	return FileAccess.file_exists(_absolute()) or FileAccess.file_exists(_absolute(".bak"))


func delete_all() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_absolute(suffix)):
			DirAccess.remove_absolute(_absolute(suffix))


func _read_file(file_path: String) -> FacetsReply:
	if not FileAccess.file_exists(file_path):
		return FacetsReply.fail(FacetsError.PERSISTENCE_FAILED, "No save present.")
	return FacetsJson.parse(FileAccess.get_file_as_string(file_path), max_bytes, 64)


func _fail(detail: String) -> FacetsReply:
	return FacetsReply.failure(FacetsError.make(FacetsError.PERSISTENCE_FAILED, "The save could not be written.", "", true).with_detail(detail))
