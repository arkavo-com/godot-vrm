# FACETS AI adapter (optional)

Provider-neutral boundary that lets a model *propose intent* while FACETS
*decides outcomes*:

```
bounded observation -> proposal JSON -> FacetsProposalValidator -> FacetsActionRequest
  -> session.preview(request, principal) -> session.commit(...) -> committed event -> narration
```

* `FacetsAiProvider` — subclass it to connect any local or remote model. The
  addon contains no network code, API keys or vendor SDKs.
* `FacetsFakeProvider` — deterministic offline provider used by tests and the
  Night Market demo.
* `FacetsAiAdapter` — tickets with timeouts and cancellation; observation
  caching per observer; narration fallback from the committed event.
* `FacetsAiViews` — witness/perception filtering. Private facts, NPC internals
  and hidden objects never reach a provider.
* `FacetsNpcPolicy` — authored priorities for NPC choices through the normal
  `session.choose` path.
* `proposal.schema.json` — the only accepted proposal shape.

Provider output is untrusted. Malformed or out-of-catalog proposals produce an
actionable clarification and leave state unchanged. Nothing guarantees that a
particular model will produce valid proposals reliably.
