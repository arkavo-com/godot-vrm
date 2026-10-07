@tool
class_name FacetsAiTicket
extends RefCounted
## One asynchronous provider request. Completes exactly once: delivered,
## failed, timed out or cancelled. Late deliveries after completion are
## ignored.

signal completed(ticket: FacetsAiTicket)

const PENDING := "pending"
const DONE := "done"
const FAILED := "failed"
const TIMED_OUT := "timed_out"
const CANCELLED := "cancelled"

var id: String = ""
## "proposal" or "narration".
var kind: String = ""
var actor_id: String = ""
var state: String = PENDING
var deadline_ms: int = 0
## Raw provider output (untrusted).
var raw: Variant = null
## Validated outcome: FacetsReply.
var result: FacetsReply = null
## Context the adapter needs to finish the ticket.
var context: Dictionary = {}


func is_pending() -> bool:
	return state == PENDING


func _finish(new_state: String, reply: FacetsReply) -> void:
	if state != PENDING:
		return
	state = new_state
	result = reply
	completed.emit(self)
