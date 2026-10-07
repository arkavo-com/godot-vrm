# Extension and operation guide

FACETS is extended with **data** (packs, Resources, JSON) and **trusted code**
registered by the host (operations, talent hooks, providers). Portable
content never contains scripts, callables, node paths or object IDs.

## Content packs

A `FacetsRulesPack` (or its JSON form, `schemas/pack.schema.json`) bundles
skills, talents, conditions, actions, archetypes and an admission policy with
an exact version and exact dependency versions:

```gdscript
var pack := FacetsRulesPack.new()
pack.pack_id = "mygame.city"
pack.version = "1.0.0"
pack.dependencies = {"facets.core": "0.1.0"}
pack.actions.append(load("res://content/actions/bribe_guard.tres"))
var reply := registry.register_pack(pack)   # atomic; all or nothing
```

Genre skills are ordinary skill definitions (`genre = true`) and share the
creation budget. Saves pin the pack versions they were made with; restoring
with different versions fails with `UNSUPPORTED_VERSION` rather than silently
changing balance.

## Operations (requirements and effects)

Actions reference operations by ID with parameters. Add new operations in
trusted host code before registering content that uses them:

```gdscript
registry.operations.register(FacetsOperations.KIND_EFFECT, "mygame.raise_heat", 1,
	{"district": "string", "amount": "int"},
	func(context: FacetsOpContext, txn: FacetsTxn, params: Dictionary) -> bool:
		return txn.add_counter("heat:%s" % params["district"], int(params["amount"])),
	"Raise a district's heat level.")
```

Rules for operation code:

* Deterministic: read only `context` and `params`; never use RNG, time,
  files or the network.
* Change state only through the `FacetsTxn` helpers (`set_path`, `append`,
  `remove`, `add_strain`, `set_object_flag`, ...). They record the low-level
  ops that make replay possible.
* Fail with `txn.fail(FacetsError.make(...))`; the whole transaction is then
  discarded.
* Bump the operation version when behavior changes; journals store resolved
  low-level ops, so old saves replay unchanged.

Parameter types: `string`, `int`, `bool`, `scalar`, `string_list`; a
trailing `?` marks optional parameters. Unknown parameters fail validation.

Requirements use `KIND_REQUIREMENT` and a callable `func(context, params) ->
bool`. Mark a requirement `secret` in content to hide what it is when unmet.

## Talent hooks

Talents name a hook and typed parameters. Register new hooks with
`registry.hooks.register(hook_id, package, param_schema, description)` and
implement their behavior in the host (see `core/talents.gd` for the six core
hooks and `addons/facets_combat/encounter.gd` for Bodyguard and Last
Reserve). The talent editor only offers registered hooks.

## AI providers

Subclass `FacetsAiProvider` and call `adapter.deliver(ticket, raw_json)` or
`adapter.fail(ticket, reason)` when your model answers. The adapter validates
the output against `proposal.schema.json` and the observer's catalog; it still
has to pass `session.preview` with the host's principal. Do not put API keys
in the addon.

## World integration

The default world is session-owned so effects, counters and the journal share
one transaction. If your game keeps authoritative state elsewhere, wrap it in
an equivalent atomic, revision-checked store and apply visuals only from
committed events (`session.published`). Mutating a scene tree from inside an
effect is not sufficient.

## Combat

`FacetsCombat.register(registry)` adds the combat hooks and talents.
Encounters work on copies of actor state; apply `encounter.journey_effects()`
through `session.apply_host_effects` when the fight ends.
