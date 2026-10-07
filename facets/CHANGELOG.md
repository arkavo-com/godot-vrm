# Changelog

## 0.1.0 — 2026-10-07

First implementation of the FACETS v0.1 implementation brief.

### Core (`addons/facets`)
- Pure resolver, exact 36-outcome probability and modifier aggregation
  (duplicate factors rejected, one assistance, one relationship ±1, worst
  condition capped at −2, ±3 cap; Push and Resolve outside the cap).
- Standard creation, progressed and policy-based build validation.
- Typed authoring Resources (character, facet set, skill, talent, condition,
  bond, identity, identity trigger, action, approach, operation reference,
  cost/benefit options, archetype, admission policy, rules pack).
- Registry with an allowlisted operation registry and typed talent hooks.
- Transactional session: preview → commit → Resolve/cost/benefit decisions →
  finalize; idempotent request IDs; stale-preview rejection before costs and
  RNG; retry locks; identity triggers; breathers and secure rest; milestones,
  purchases, ledger and actual-cost respec; journey reset preserving profile.
- Journal of low-level state ops, replay with integrity checks, memory and
  atomic file stores with backup recovery, legacy alias migration.
- Portable character codec with import limits; stable greedy admission.
- Six noncombat talents: Second Look, Quiet Hands, Field Engineer, Steady
  Voice, Bargain Maker, Trail Reader.
- Editor plugin: character/action/talent inspector panels with undoable
  edits, validation dock with field navigation and blocked content export,
  probability dock.

### Optional packages
- `facets_ai`: provider interface, deterministic fake provider, strict
  proposal validation, perception-filtered observation and narration views,
  timeouts, cancellation, narration fallback, NPC choice policy.
- `facets_combat`: zone encounters, Bodyguard and Last Reserve.

### Demo, data and tooling
- Night Market Delivery demo (three routes, identity trigger, deadline,
  milestone, retained consequences in a second scene, save/load/reset).
- JSON Schemas with positive and negative fixtures; independent Python
  reference for probability fixtures.
- Headless test runner (138 tests, T01–T30 and C01–C04), real-editor
  self-test, clean-install check, release archive builder, CI workflow.
- Baseline Godot 4.7.2 (latest stable); also verified on Godot 4.6.3 (CI matrix).
