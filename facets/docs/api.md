# FACETS public API (0.1.0)

All APIs return a typed `FacetsReply` (`ok`, `value`, `error`, `errors`)
unless noted. Errors are `FacetsError` objects with `code`, `message`,
`field_path` and `retryable`; messages shown to players never contain hidden
facts (developer detail lives in `error.detail`).

Core scripts extend `RefCounted` (services and runtime state) or `Resource`
(authoring definitions). Nothing requires an autoload, a scene tree or the
editor plugin.

## Pure rules

| API | Notes |
|---|---|
| `FacetsResolver.evaluate(check: FacetsCheckInput, dice: Vector2i, adjustments: FacetsAdjustments) -> FacetsEvaluation` | Pure arithmetic on validated inputs. No state, no RNG. `evaluate_checked()` validates first and returns a reply. |
| `FacetsProbability.enumerate(check, adjustments) -> FacetsOdds` | Exact 36-outcome counts per band. `scenarios(check, adjustments, push_available, resolve_available)` returns separate fixed scenarios. |
| `FacetsModifiers.validate(modifiers, defense_modifiers) / aggregate(modifiers)` | Duplicate factors, assistance/relationship limits, worst condition only, then the ±3 cap. |
| `FacetsValidator.validate_creation(build, registry)` | Standard creation; also `validate_progressed`, `validate_policy_build`, `validate_action`, `validate_talent`, `validate_character`. |
| `FacetsRules` | Constants and helpers (`band_for_margin`, `opposed_target`, `strain_capacity`). |

```gdscript
var check := FacetsCheckInput.make(3, 2, 13, true)
var evaluation := FacetsResolver.evaluate(check, Vector2i(3, 3), FacetsAdjustments.new())
# evaluation.total == 11, evaluation.margin == -2, evaluation.band == "costly_offer"
var odds := FacetsProbability.enumerate(FacetsCheckInput.make(5, 3, 14, true), FacetsAdjustments.new())
# odds.fraction("failure") == "3/36" ... odds.percent_text("success") == "55.56%"
```

## Content

| API | Notes |
|---|---|
| `FacetsRegistry.core()` | Core pack: 12 skills, 6 noncombat talents, standard conditions, 5 presets, standard admission policy. |
| `registry.register_pack(pack: FacetsRulesPack)` / `register_pack_dict(dict)` | Atomic; checks ruleset version and exact dependency versions. |
| `registry.add_action(dict)` / `add_action_resource(res)` | Validates against the operation registry; stores an immutable copy. |
| `registry.operations` (`FacetsOperations`) | Allowlisted requirements and effects with parameter schemas. |
| `registry.hooks` (`FacetsTalentHooks`) | Typed talent hooks. |
| `FacetsCombat.register(registry)` | Optional: combat hooks and the two combat talents. |

## Sessions

```gdscript
var session: FacetsSession = FacetsSession.create(registry, world, {"store": FacetsFileStore.at("user://save.json")}).value
var preview: FacetsCheckPreview = session.preview(FacetsActionRequest.make("mara", "nm.bypass_controller", "tech").with_tools(["tool.signal_kit"]), principal).value
var event: FacetsResolutionEvent = session.commit(preview.token, {"push": false}, "req-1").value
while event.is_pending():
	var decision := event.pending_decision            # kind: resolve | cost | benefit | identity
	event = session.choose(event.event_id, decision.decision_id, decision.option_ids()[0], "req-2").value
```

| API | Contract |
|---|---|
| `FacetsSession.create(registry, world, options)` | Owns a copy of the world, its RNG (`seed`) or injected `dice`, and an optional persistence `store` (initial state is written). |
| `session.preview(request, principal)` | Validates authority, knowledge, tools, requirements, approach, helper, retry lock; returns a `FacetsCheckPreview` (target, visible modifiers, stakes, costs, benefits, exact odds, push note, token). Spends nothing, rolls nothing. |
| `session.commit(token, {"push": bool}, request_id)` | Rejects stale tokens before costs and RNG; pays Push; draws dice once; durably records the commitment; returns the pending record or the final event. Same `request_id` + payload returns the prior record; a different payload is `IDEMPOTENCY_CONFLICT`. |
| `session.choose(event_id, decision_id, option_id, request_id)` | Validates against the frozen options; finalizes atomically when no decision remains. |
| `session.abandon(event_id, request_id)` | Declines Resolve and costs; picks only a declared safe default benefit. |
| `session.get_event(event_id)` | Pending or final record; never rerolls. |
| `session.save(store)` / `FacetsSession.restore(store, registry, options)` | Full save; restore replays the journal from recorded ops, verifies the digest and pinned pack versions. |
| `session.checkpoint(principal)` | Compacts the journal. |
| `FacetsSession.replay(checkpoint_state, journal, checkpoint_sequence)` | Pure replay. |
| `session.catalog(actor_id, principal)` / `suggest_request(...)` | Every action/approach with availability and visible reasons. |
| `session.published` signal, `add_presentation_port(port)` | Fired after durable commits only; presentation never changes state. |

Host-authority commands (require a host principal; client text can never do
these): `grant_opportunity`, `start_scene`, `end_scene`, `complete_chapter`,
`authorize_meaningful_change`, `award_milestone`, `offer_identity_trigger`,
`apply_host_effects`, `add_actor`, `grant_training`, `reset_journey`.
Actor commands (principal must control the actor): `take_breather`,
`full_rest`, `use_steady_voice`, `purchase`, `respec`.

## Ports

| Port | Implementation |
|---|---|
| WorldPort | The session-owned `FacetsWorldSnapshot`; host batches via `apply_host_effects` (validated, atomic). External worlds must provide equivalent atomic revision semantics. |
| OperationRegistry | `FacetsOperations` (`register(kind, op_id, version, schema, callable)`). |
| DiceSource | `FacetsDiceSource.seeded(seed)` or `FacetsDiceSource.fixed(pairs)`. |
| PersistencePort | `FacetsSessionStore` → `FacetsMemoryStore`, `FacetsFileStore` (temp file, validate, keep `.bak`, atomic rename). |
| PresentationPort | Any object with `present(event: FacetsResolutionEvent)`. |

## Portable data

| API | Notes |
|---|---|
| `FacetsCharacterCodec.decode(json, registry, limits)` | Allowlisted fields only; 1 MiB, depth 16, 128 list items, 4096-character text limits (host-configurable via `FacetsImportLimits`); legacy alias migration; future schemas fail clearly. Never `load()`s imported data. |
| `FacetsCharacterCodec.encode(character)` | Canonical sorted-key JSON with integer mechanics. |
| `FacetsAdmission.propose(character, policy, registry)` | Legal proposed build, exclusions, warnings, explanation; `accept(proposal)` creates a fresh `FacetsActorState` for `session.add_actor`. |
| `FacetsJson` | `canonical`, `parse` (size/depth limits, integer normalization), `digest`. |

## Optional AI adapter (`addons/facets_ai`)

`FacetsAiAdapter.make(session, provider)`, `propose(actor_id, principal,
now_ms) -> FacetsAiTicket`, `narrate(event, observer_id, now_ms)`,
`tick(now_ms)`, `cancel(ticket)`; `FacetsProposalValidator.validate(raw,
observation)`; `FacetsAiViews.observation(...)`; `FacetsFakeProvider`;
`FacetsNpcPolicy`.

## Optional combat (`addons/facets_combat`)

`FacetsEncounter.create(registry, zones, actors, setup, dice, options)`,
`move`, `attack(attacker, target, approach, {"push", "interceptor_id"})`,
`defend`, `medicine`, `use_last_reserve`, `end_turn`, `end_encounter`,
`journey_effects(actor_id)`.
