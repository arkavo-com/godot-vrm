@tool
class_name FacetsAiAdapter
extends RefCounted
## Optional conversion boundary between a session and an AI provider:
## bounded observation -> proposed intent -> normal validation/preview ->
## normal transaction -> visible event -> narration.
##
## Proposals become ordinary [FacetsActionRequest]s that still go through
## [method FacetsSession.preview] with the host-supplied principal. The
## adapter never commits, spends or rolls on its own. Narration failures
## fall back to deterministic text built from the committed event.

signal proposal_ready(ticket: FacetsAiTicket)
signal narration_ready(ticket: FacetsAiTicket)

const MAX_NARRATION := 2000

var session: FacetsSession
var provider: FacetsAiProvider
var timeout_ms: int = 4000
var cache_hits: int = 0
var _tickets: Array[FacetsAiTicket] = []
var _counter: int = 0
var _cache: Dictionary = {}


static func make(p_session: FacetsSession, p_provider: FacetsAiProvider) -> FacetsAiAdapter:
	var adapter := FacetsAiAdapter.new()
	adapter.session = p_session
	adapter.provider = p_provider
	return adapter


## Perception-filtered observation, cached per observer while the relevant
## state is unchanged.
func observe(actor_id: String, principal: FacetsPrincipal) -> Dictionary:
	var fresh := FacetsAiViews.observation(session, actor_id, principal)
	var key := FacetsAiViews.observation_key(fresh)
	var cached: Dictionary = _cache.get(actor_id, {})
	if cached.get("key", "") == key:
		cache_hits += 1
		return cached["observation"].duplicate(true)
	_cache[actor_id] = {"key": key, "observation": fresh}
	return fresh.duplicate(true)


func propose(actor_id: String, principal: FacetsPrincipal, now_ms: int) -> FacetsAiTicket:
	var ticket := _ticket("proposal", actor_id, now_ms)
	var observation := observe(actor_id, principal)
	ticket.context = {"observation": observation}
	provider.request_proposal(ticket, observation, self)
	return ticket


func narrate(event: FacetsResolutionEvent, observer_id: String, now_ms: int) -> FacetsAiTicket:
	var ticket := _ticket("narration", observer_id, now_ms)
	var view := FacetsAiViews.narration_view(session, event, observer_id)
	ticket.context = {"view": view}
	provider.request_narration(ticket, view, self)
	return ticket


func _ticket(kind: String, actor_id: String, now_ms: int) -> FacetsAiTicket:
	_counter += 1
	var ticket := FacetsAiTicket.new()
	ticket.id = "ai-%d" % _counter
	ticket.kind = kind
	ticket.actor_id = actor_id
	ticket.deadline_ms = now_ms + timeout_ms
	ticket.completed.connect(_on_completed)
	_tickets.append(ticket)
	return ticket


## Called by providers with untrusted output.
func deliver(ticket: FacetsAiTicket, payload: Variant) -> void:
	if ticket == null or not ticket.is_pending():
		return
	ticket.raw = payload
	if ticket.kind == "proposal":
		var reply := FacetsProposalValidator.validate(payload, ticket.context.get("observation", {}))
		ticket._finish(FacetsAiTicket.DONE if reply.ok else FacetsAiTicket.FAILED, reply)
		return
	if payload is String and not str(payload).strip_edges().is_empty() and str(payload).length() <= MAX_NARRATION:
		ticket._finish(FacetsAiTicket.DONE, FacetsReply.success({"text": str(payload), "fallback": false}))
	else:
		_fallback(ticket, FacetsAiTicket.DONE)


## Called by providers on errors.
func fail(ticket: FacetsAiTicket, _reason: String) -> void:
	if ticket == null or not ticket.is_pending():
		return
	if ticket.kind == "proposal":
		ticket._finish(FacetsAiTicket.FAILED, FacetsReply.fail(FacetsError.CANCELLED, "The assistant couldn't suggest an action. Choose one yourself or try again."))
	else:
		_fallback(ticket, FacetsAiTicket.FAILED)


func cancel(ticket: FacetsAiTicket) -> void:
	if ticket == null or not ticket.is_pending():
		return
	provider.cancel(ticket)
	ticket._finish(FacetsAiTicket.CANCELLED, FacetsReply.fail(FacetsError.CANCELLED, "Cancelled."))


## Drives timeouts (and the fake provider's simulated latency).
func tick(now_ms: int) -> void:
	if provider.has_method("pump"):
		provider.call("pump")
	for ticket in _tickets.duplicate():
		if ticket.is_pending() and now_ms >= ticket.deadline_ms:
			provider.cancel(ticket)
			if ticket.kind == "proposal":
				ticket._finish(FacetsAiTicket.TIMED_OUT, FacetsReply.fail(FacetsError.TIMEOUT, "The assistant took too long. Choose an action yourself or try again.", "", true))
			else:
				_fallback(ticket, FacetsAiTicket.TIMED_OUT)


func pending_count() -> int:
	return _tickets.filter(func(ticket: FacetsAiTicket) -> bool: return ticket.is_pending()).size()


func _fallback(ticket: FacetsAiTicket, state: String) -> void:
	ticket._finish(state, FacetsReply.success({"text": FacetsAiViews.fallback_narration(ticket.context.get("view", {})), "fallback": true}))


func _on_completed(ticket: FacetsAiTicket) -> void:
	_tickets.erase(ticket)
	if ticket.kind == "proposal":
		proposal_ready.emit(ticket)
	else:
		narration_ready.emit(ticket)
