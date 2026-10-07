# Save compatibility policy

Saves are canonical JSON (`schemas/save.schema.json`) written atomically:
temporary file → re-read and validate → previous save kept as `.bak` →
atomic rename. A failed write is reported and nothing is committed.

## Version domains

* `schema_version` — JSON shape (currently `1`). Newer values fail with
  `FUTURE_SCHEMA` and a clear message; nothing is loaded lossily.
* `ruleset_id` / `ruleset_version` — `facets.core` / `0.1.0`. The legacy
  source alias `gom.facets.core@0.1.0` is migrated explicitly
  (`FacetsMigrations`); any other value fails with `UNSUPPORTED_VERSION`.
* `packs` — exact versions of every registered pack. Restoring with a
  different pack version fails rather than silently changing balance.
* Journal entries carry `format: 1`; unknown formats or unknown state
  operations stop replay with an actionable error.
* Addon releases are versioned independently (`plugin.cfg`).

## What a save contains

Schema and rules versions, the checkpoint state, the ordered journal of
low-level state operations after the checkpoint, the last sequence, the
pending transaction and its frozen choices, the request-ID map (for
idempotent retries), random-stream metadata, an archive of final events, and
the actors' usage and award ledgers. Restore replays the journal from
recorded operations (never dice) and checks the state digest.

## Migrations

Migrations are explicit functions over JSON, recorded in `migration_notes`,
and never change balance. A future rules version that changes mechanics will
require an explicit migration or a new journey, never automatic reinterpretation
of old events.

## Portability

Replaying a save in another implementation requires the same rules version,
the same operation semantics and the recorded dice. Godot RNG state is not a
cross-version contract.
