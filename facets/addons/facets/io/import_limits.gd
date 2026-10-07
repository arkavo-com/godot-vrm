@tool
class_name FacetsImportLimits
extends RefCounted
## Limits applied to untrusted imports before any runtime object is built.
## Only the trusted host may change them.

var max_bytes: int = 1048576
var max_depth: int = 16
var max_list: int = 128
var max_text: int = 4096


static func standard() -> FacetsImportLimits:
	return FacetsImportLimits.new()
