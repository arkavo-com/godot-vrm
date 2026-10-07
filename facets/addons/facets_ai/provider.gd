@tool
class_name FacetsAiProvider
extends RefCounted
## Provider-neutral interface. A host connects any local or remote model by
## subclassing this and calling [method FacetsAiAdapter.deliver] (or
## [method FacetsAiAdapter.fail]) when output arrives. FACETS ships no API
## keys, vendor SDKs or network code; there is no guarantee a given model
## will satisfy the proposal schema reliably.


## Ask for an intent proposal. [param observation] is already filtered by
## witness/perception policy. Output must match proposal.schema.json.
func request_proposal(_ticket: FacetsAiTicket, _observation: Dictionary, _adapter: Object) -> void:
	pass


## Ask for narration of a committed, visible event view.
func request_narration(_ticket: FacetsAiTicket, _view: Dictionary, _adapter: Object) -> void:
	pass


func cancel(_ticket: FacetsAiTicket) -> void:
	pass
