@tool
class_name FacetsDiceSource
extends RefCounted
## DiceSource port: returns two integers in 1..6.
##
## The default implementation is a session-owned RandomNumberGenerator. Tests
## and conformance fixtures inject explicit dice with [method fixed]. Seeded
## reproducibility is limited to the pinned Godot build; portable replay uses
## recorded dice, never a seed.

const KIND_RNG := "rng"
const KIND_FIXED := "fixed"

var kind: String = KIND_RNG
var draws: int = 0
var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _queue: Array[Vector2i] = []
var _exhausted: bool = false


static func seeded(p_seed: int) -> FacetsDiceSource:
	var source := FacetsDiceSource.new()
	source.kind = KIND_RNG
	source._seed = p_seed
	source._rng.seed = p_seed
	return source


static func fixed(pairs: Array) -> FacetsDiceSource:
	var source := FacetsDiceSource.new()
	source.kind = KIND_FIXED
	for pair in pairs:
		if pair is Vector2i:
			source._queue.append(pair)
		elif pair is Array and pair.size() == 2:
			source._queue.append(Vector2i(int(pair[0]), int(pair[1])))
	return source


## Draws one pair. Returns Vector2i.ZERO when a fixed source is exhausted;
## callers must treat that as a hard error, never as a roll. An RNG source
## first consumes any pairs queued with [method push_fixed] (debug and
## demo tooling only).
func roll_pair() -> Vector2i:
	draws += 1
	if not _queue.is_empty():
		return _queue.pop_front()
	if kind == KIND_FIXED:
		_exhausted = true
		return Vector2i.ZERO
	return Vector2i(_rng.randi_range(1, 6), _rng.randi_range(1, 6))


func push_fixed(pair: Vector2i) -> void:
	_queue.append(pair)


func remaining_fixed() -> int:
	return _queue.size()


func is_exhausted() -> bool:
	return _exhausted


## Metadata persisted in saves so a failed commit can restore the stream.
func get_state() -> Dictionary:
	var queue: Array = []
	for pair in _queue:
		queue.append([pair.x, pair.y])
	if kind == KIND_FIXED:
		return {"kind": KIND_FIXED, "queue": queue, "draws": draws}
	return {"kind": KIND_RNG, "seed": str(_seed), "state": str(_rng.state), "queue": queue, "draws": draws}


func set_state(state: Dictionary) -> void:
	draws = int(state.get("draws", 0))
	_queue.clear()
	for pair in state.get("queue", []):
		_queue.append(Vector2i(int(pair[0]), int(pair[1])))
	if str(state.get("kind", KIND_RNG)) == KIND_FIXED:
		kind = KIND_FIXED
		return
	kind = KIND_RNG
	_seed = str(state.get("seed", "0")).to_int()
	_rng.seed = _seed
	_rng.state = str(state.get("state", "0")).to_int()
