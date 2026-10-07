@tool
class_name FacetsNpcPolicy
extends RefCounted
## Authored priorities for NPC choices (Resolve, costs, benefits). Chooses
## only among the options the session offered, through the normal
## [method FacetsSession.choose] path, so it cannot bypass any rule.

## Option ID patterns in preference order, e.g. ["spend", "accept:*", "decline"].
var priorities: Array[String] = []


static func make(p_priorities: Array[String]) -> FacetsNpcPolicy:
	var policy := FacetsNpcPolicy.new()
	policy.priorities = p_priorities.duplicate()
	return policy


func choose_option(decision: FacetsPendingDecision) -> String:
	var offered := decision.option_ids()
	for pattern in priorities:
		for option_id in offered:
			if option_id.match(pattern):
				return option_id
	return offered[offered.size() - 1] if not offered.is_empty() else ""


## Resolves every pending decision of [param event] with this policy.
func resolve(session: FacetsSession, event: FacetsResolutionEvent, request_prefix: String) -> FacetsReply:
	var current := event
	var step := 0
	while current != null and current.is_pending():
		step += 1
		var decision := current.pending_decision
		var reply := session.choose(current.event_id, decision.decision_id, choose_option(decision), "%s-%d" % [request_prefix, step])
		if not reply.ok:
			return reply
		current = reply.value
	return FacetsReply.success(current)
