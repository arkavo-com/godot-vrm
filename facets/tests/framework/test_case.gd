class_name FacetsTestCase
extends RefCounted
## Minimal assertion base for the headless FACETS suite. Test methods are
## named test_<group>_<description>, e.g. test_t08_push_capacity_boundary.

var failures: Array[String] = []
var assertions: int = 0


func fixture(relative_path: String) -> Variant:
	var path := "res://tests/fixtures/".path_join(relative_path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		fail("fixture missing: %s" % path)
		return null
	var reply := FacetsJson.parse(text, 8 * 1048576, 64)
	if not reply.ok:
		fail("fixture %s unreadable: %s" % [path, reply])
		return null
	return reply.value


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> bool:
	assertions += 1
	if not condition:
		fail(message)
	return condition


func assert_false(condition: bool, message: String = "expected false") -> bool:
	return assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	assertions += 1
	var same: bool = FacetsJson.equal(actual, expected) if (actual is Dictionary or actual is Array or expected is Dictionary or expected is Array) else actual == expected
	if not same:
		fail("%sexpected %s, got %s" % [(message + ": ") if not message.is_empty() else "", _show(expected), _show(actual)])
	return same


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	assertions += 1
	if FacetsJson.equal(actual, unexpected):
		fail("%sdid not expect %s" % [(message + ": ") if not message.is_empty() else "", _show(unexpected)])
		return false
	return true


func assert_ok(reply: FacetsReply, message: String = "") -> Variant:
	assertions += 1
	if reply == null or not reply.ok:
		fail("%sexpected ok reply, got %s" % [(message + ": ") if not message.is_empty() else "", str(reply)])
		return null
	return reply.value


func assert_error(reply: FacetsReply, code: String, message: String = "") -> bool:
	assertions += 1
	if reply == null or reply.ok:
		fail("%sexpected error %s, got ok" % [(message + ": ") if not message.is_empty() else "", code])
		return false
	if not reply.error_codes().has(code):
		fail("%sexpected error %s, got %s" % [(message + ": ") if not message.is_empty() else "", code, str(reply)])
		return false
	return true


func assert_has_error(errors: Array, code: String, message: String = "") -> bool:
	assertions += 1
	for error in errors:
		if error.code == code:
			return true
	fail("%sexpected error %s in %s" % [(message + ": ") if not message.is_empty() else "", code, str(errors)])
	return false


func _show(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return FacetsJson.canonical(value)
	return var_to_str(value)
