@tool
class_name FacetsJson
extends RefCounted
## Canonical JSON helpers: sorted keys, integer mechanics, bounded parsing.
##
## Godot's JSON parser returns every number as a float. Portable FACETS data
## only uses integers, so parsing converts integral floats back to int and
## rejects fractional numbers.

const DEFAULT_MAX_BYTES := 1048576
const DEFAULT_MAX_DEPTH := 16


## Sorted-key canonical string with integers preserved.
static func canonical(value: Variant) -> String:
	return JSON.stringify(normalize(value), "", true)


static func pretty(value: Variant) -> String:
	return JSON.stringify(normalize(value), "  ", true)


static func digest(value: Variant) -> String:
	return canonical(value).sha256_text()


## Recursively converts integral floats to int and Godot vectors to arrays.
static func normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and number == floorf(number) and absf(number) < 9.0e15:
				return int(number)
			return number
		TYPE_DICTIONARY:
			var result := {}
			var source: Dictionary = value
			for key in source:
				result[str(key)] = normalize(source[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(normalize(item))
			return result
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_VECTOR2I:
			var vector: Vector2i = value
			return [vector.x, vector.y]
		TYPE_STRING_NAME:
			return str(value)
	return value


## Deep copy through canonical normalization.
static func clone(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return normalize(value.duplicate(true))
	return normalize(value)


static func equal(a: Variant, b: Variant) -> bool:
	return canonical(a) == canonical(b)


## Parses untrusted text with size and nesting limits applied before the
## parser runs. Returns FacetsReply with the normalized value.
static func parse(text: String, max_bytes: int = DEFAULT_MAX_BYTES, max_depth: int = DEFAULT_MAX_DEPTH) -> FacetsReply:
	var byte_length := text.to_utf8_buffer().size()
	if byte_length > max_bytes:
		return FacetsReply.fail(FacetsError.TOO_LARGE, "Input exceeds %d bytes." % max_bytes)
	var depth := nesting_depth(text)
	if depth < 0:
		return FacetsReply.fail(FacetsError.MALFORMED, "Unbalanced JSON brackets.")
	if depth > max_depth:
		return FacetsReply.fail(FacetsError.TOO_LARGE, "Input nesting exceeds %d levels." % max_depth)
	var json := JSON.new()
	var status := json.parse(text)
	if status != OK:
		return FacetsReply.fail(FacetsError.MALFORMED, "Malformed JSON at line %d." % json.get_error_line())
	var fractional := _find_fractional(json.data, "")
	if not fractional.is_empty():
		return FacetsReply.fail(FacetsError.INVALID_FIELD, "Mechanics use integers only.", fractional)
	return FacetsReply.success(normalize(json.data))


## Bracket depth outside strings; -1 when unbalanced.
static func nesting_depth(text: String) -> int:
	var depth := 0
	var deepest := 0
	var in_string := false
	var escaped := false
	for index in text.length():
		var character := text.unicode_at(index)
		if in_string:
			if escaped:
				escaped = false
			elif character == 92:  # backslash
				escaped = true
			elif character == 34:  # quote
				in_string = false
			continue
		match character:
			34:
				in_string = true
			91, 123:  # [ {
				depth += 1
				deepest = maxi(deepest, depth)
			93, 125:  # ] }
				depth -= 1
				if depth < 0:
					return -1
	if depth != 0:
		return -1
	return deepest


static func _find_fractional(value: Variant, path: String) -> String:
	match typeof(value):
		TYPE_FLOAT:
			var number: float = value
			if not is_finite(number) or number != floorf(number):
				return path if not path.is_empty() else "$"
		TYPE_DICTIONARY:
			for key in value:
				var found := _find_fractional(value[key], key if path.is_empty() else "%s.%s" % [path, key])
				if not found.is_empty():
					return found
		TYPE_ARRAY:
			for index in value.size():
				var found := _find_fractional(value[index], "%s[%d]" % [path, index])
				if not found.is_empty():
					return found
	return ""
