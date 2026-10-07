# FACETS — Narrative RPG Framework for Godot
## Coder implementation specification · v0.1 · October 7, 2026

**Deliverable:** an installable GDScript addon, editor authoring tools, portable data contracts, automated conformance tests, and a playable cyberpunk demonstration. This document is the implementation brief; it does not claim that code has been built or tested.

**Product statement:** A deterministic, data-driven character and action-resolution framework for RPGs, immersive sims, narrative games, and AI-driven characters. Let AI propose intent. Let FACETS decide outcomes.

**Rules authority:** `Game-of-Mods-FACETS.md`, playable design draft v0.1, October 6, 2026. Its mechanics govern this implementation. The Godot pitch establishes packaging and positioning, not replacement mechanics. Decisions explicitly marked “implementation decision” close engineering gaps without claiming to be existing Game of Mods behavior. Copy the supplied rules into the repository as `docs/rules-v0.1.md`; retain their draft status.

## 1. Scope and deliverables

Build FACETS independently of Game of Mods and Arkavo. No Arkavo account, service, model, native library, or commercial application is required. Game of Mods is an intended integration and showcase; do not advertise it as a conformant production implementation until an actual integration passes the shared fixtures.

| Layer | Required responsibility | Dependencies |
|---|---|---|
| Core | Rules, typed data, validation, exact probability, transactional sessions, persistence, progression, admission | Godot built-ins only |
| Editor | Character/action/talent authoring, validation, probability inspector | Core and Godot editor APIs |
| AI | Provider-neutral intent proposals and committed-event narration views | Core; provider supplied by host |
| Combat | Optional zone combat and combat talents | Core |
| Demo | Night Market Delivery, three routes, persistent consequences | Core; editor-created content |

Use typed GDScript and ordinary Godot Resources. No engine fork, C++ module, GDExtension, mandatory autoload, or mandatory scene tree. Core services extend `RefCounted`; authoring assets extend `Resource`. Pure functions accept explicit inputs. Session instances isolate state and random streams.

**Implementation decision:** target Godot 4.6 as the initial compatibility baseline, pin an exact stable patch in CI, and record it in the README. This is a chosen baseline, not a claim about the latest release. Test an additional stable version only when claiming compatibility with it.

Release boundaries:

- **MVP:** core noncombat checks, Resources, all creation rules, strain/Resolve/conditions, six noncombat talents, identity trigger, progression/admission, editor tools, demo, fake AI adapter, save/replay.
- **v0.1 complete:** optional combat adapter plus Bodyguard and Last Reserve, completing all eight source talents; packaging and conformance suite.
- **Deferred:** multiplayer transport, model hosting, voice recognition, VRM, Workshop integration, signed provenance, procedural narrative generation, supernatural pricing, detailed inventory or vehicle simulation. Provide host interfaces where needed; do not implement these platforms.

## 2. Repository and package layout

Use the following paths; the table defines required files rather than a prescribed class-per-concept explosion.

| Path | Contents |
|---|---|
| `addons/facets/plugin.cfg` | Editor plugin metadata |
| `addons/facets/facets_plugin.gd` | `@tool extends EditorPlugin`, registration and cleanup |
| `addons/facets/core/` | `resolver.gd`, `probability.gd`, `validator.gd`, `session.gd`, `reducer.gd`, `admission.gd`, `progression.gd`, `registry.gd` |
| `addons/facets/core/types/` | Request, preview, result, pending decision, event, state and error types |
| `addons/facets/resources/` | Character, facet set, skill, talent, condition, bond, identity trigger, action, archetype and rules-pack Resources |
| `addons/facets/io/` | JSON codec, migrations, save store and portable character codec |
| `addons/facets/editor/` | Character inspector, action/talent editors, validation dock and probability panel |
| `addons/facets/content/core/` | Twelve skills, six noncombat talents, standard conditions and admission preset |
| `addons/facets_ai/` | Optional adapter scripts, proposal schema and deterministic fake provider |
| `addons/facets_combat/` | Optional encounter service, zone types, weapons and two combat talents |
| `examples/night_market/` | Scenes, authored Resources, fixtures and demo README |
| `schemas/` | JSON schemas for portable characters, actions, packs, saves and events |
| `tests/` | Headless runner, unit/integration cases and language-neutral JSON fixtures |
| `docs/` | Rules, API, tutorial, extension guide, compatibility and release checklist |

Keep runtime code independent of `EditorPlugin`, `EditorInterface`, editor scenes and AI/combat packages. Use globally distinctive `Facets*` class names. Editor-callable Resource and pure-helper scripts must support tool execution, with no automatic gameplay side effects. Do not initiate sessions, draw randomness, write files or call providers from Resource initialization or inspector getters.

Example `plugin.cfg`:

```ini
[plugin]
name="FACETS"
description="Character authoring and deterministic narrative RPG rules"
author="Arkavo LLC"
version="0.1.0"
script="facets_plugin.gd"
```

Enable registers inspectors and docks; disable removes them and disconnects signals. Repeated enable/disable must not duplicate UI or modify unrelated project settings. Core remains usable with the editor plugin disabled.

## 3. Rules to implement exactly

### 3.1 Character creation and state

Facets are `force`, `agility`, `cunning`, `empathy`, `tenacity`, `sense`. Standard creation begins at 2 each, adds six points, caps each at 4, and totals 18. Creation cannot refund points by lowering a facet. Progressed ratings may reach 5; custom admission explicitly defines other legal ranges.

Skills are `athletics`, `fighting`, `marksmanship`, `stealth`, `sleight`, `investigation`, `survival`, `technology`, `craft`, `medicine`, `influence`, `performance`. Standard creation spends 12 points, maximum 2 per skill. General range is 0–4; missing known skills mean rank 0. Unknown skill IDs are errors. Genre skills consume the same budget.

Choose two unique talents; repeatability is explicit. Separate narrative identity (drive, code, hindrance, tell, appearance references) from build, journey state and profile accomplishments. Bonds store trust and affinity separately, each −2…+2, plus obligations and shared-event references. There is no generic additive “bond +3” statistic.

New journey state: strain 0, Resolve 1, Growth 0. Strain capacity is `4 + tenacity`; Resolve range is 0–3. Conditions and combat harm belong to journey state. Do not infer mechanics from appearance, personality prose or diagnosis.

### 3.2 Resolution and legal approaches

```
total = die_1 + die_2 + facet + skill + clamp(modifier_sum, -3, 3)
        + push_bonus + resolve_bonus
margin = total - target
```

| Margin | Final meaning |
|---|---|
| ≥ 4 | `strong_success`: objective and one allowed benefit |
| 0…3 | `success`: objective |
| −2…−1 | Offer authored cost if supported; accepted → `success_with_cost`, declined → `failure` |
| ≤ −3 | `failure`: declared consequence |

The near-miss band is a provisional result until a choice is resolved. An action without costly success maps it directly to failure. No natural criticals. Routine actions succeed without RNG; impossible or ineligible actions do not roll. A routine success grants no strong-success bonus.

Targets: 9 favorable, 11 standard pressure, 13 demanding, 15 severe, 17 extreme, 19 legendary. Fixed authored targets such as 14 are allowed. Opposed target is `7 + defending facet + defending skill + clamp(defense modifiers, -3, 3)`; defender does not roll.

Action definitions whitelist facet/skill approaches and prerequisites. The request selects an approach ID, never arbitrary best stats or a caller-chosen difficulty. Standard tools enable an action without a bonus. Assistance adds at most +1 from one eligible helper with relevant skill ≥1 who accepts the risk; it stays within the modifier cap.

Every modifier carries `source_id`, `factor_id`, scope and value. Reject duplicate application of the same factor across target and attacker modifiers. Relationship contribution is at most one authored ±1, never the sum of trust and affinity. Numeric conditions contribute only the worst applicable penalty, capped at −2; restrictions apply independently.

### 3.3 Push, Resolve, recovery and identity

Push is selected before commitment: take 2 strain for +1, once per check, only if resulting strain is strictly below capacity. Push and Resolve are outside the situational cap. Push remains spent on failure or post-roll abandonment.

Resolve may be spent once after the roll: consume 1 for +2. Show whether it changes the result band before confirmation; no extra roll. It may upgrade failure to an offered cost, a costly band to success, or success to strong success. Spending is optional, not automatically optimized for the player.

At capacity apply Overwhelmed (−1 checks, no pushing or combat reactions), clamp strain, and remove it below capacity. Further strain alone does not create wounds. A breather removes 2 once per engine-authorized recovery opportunity between consequential scenes; full secure rest resets strain. Condition removal remains condition-specific.

An authored identity trigger awards 1 Resolve at most once per actor per scene only after its material disadvantage is accepted and applied. Store trigger ID, disadvantage, actor/scene award key and amount (possibly 0 at the cap). Rejecting it gives nothing. Client text cannot start a scene, authorize recovery or award Resolve.

### 3.4 Talents, progression and admission

Implement all eight talent rules from source §6 verbatim in behavior. Use registered typed hooks, not scripts embedded in portable content. Second Look requires an alternate authored evidence source and extra interval; it is not a free unchanged reroll. Quiet Hands replaces a strong benefit; Field Engineer substitutes only an authored consumable and expires the repair at scene end. Steady Voice removes 2 strain from a willing communicating ally after fear setback, once per scene, consuming an action. Bargain Maker replaces a benefit with a listed lesser concession. Trail Reader reveals one permitted evidence-supported fact. Combat owns Bodyguard and Last Reserve.

Milestones award 1 for small or 3 for chapter, never both for the same underlying event. Use unique milestone/event award keys. At a safe checkpoint, skill increase costs `2 × new rank` (cap 4, practice/instruction required); talent costs 5 with prerequisites and initially ≤6 equipped; facet increase costs 8 (cap 5, once per completed chapter). Maintain a purchase ledger with actual paid costs. Respec refunds recorded purchases, invalidates dependent talents and reapplies admission constraints; identity editing is separate.

Standard admission preserves identity and proposes a legal 18-facet/12-skill/2-talent build. It drops accumulated Growth and unadmitted equipment/powers. Imported memories remain source-labeled references until admitted as local facts. **Implementation decision:** use a stable greedy proposal: start at baseline, allocate facet points by imported preference descending (ties in FACETS order), allocate skills by preference descending (ties by stable skill ID), and choose eligible talents by preferred order then ID. Validate the result and require host acceptance; never silently replace a live build. “Closest” is advisory here, not an optimization guarantee. Reset policy clears only declared journey state and preserves profile accomplishments.

## 4. Data model and interoperability

Authoring Resources are definitions, not live save objects. Explicit factories copy primitive/nested state into session-owned runtime types; do not mutate a shared `.tres` during play or rely on shallow duplication. A character definition may be referenced by several independent sessions.

| Type | Required data |
|---|---|
| `FacetsCharacterResource` | Stable ID, display name, identity, facet set, skill ranks, talent/capability IDs, bond definitions, preferred build |
| `FacetsActionResource` | ID/version, legal approaches, requirements, fixed/opposed difficulty, push/Resolve flags, costly options, success/failure effects, strong benefits, retry policy |
| `FacetsTalentResource` | ID/version, prerequisites, hook ID, typed parameters, usage scope, repeatability |
| `FacetsConditionResource` | ID, applicability tags, penalty, restrictions, removal operation |
| `FacetsActorState` | Admitted build, strain, Resolve, Growth, conditions, local bonds/facts, usage counters, purchase ledger |
| `FacetsWorldSnapshot` | Revision, actor states, objects, facts, zones, scene/chapter IDs and authoritative opportunities |
| `FacetsCheckPreview` | Legal action, visible requirements, target, modifier explanation, stakes, cost/benefit choices, exact odds, revision token |
| `FacetsResolutionEvent` | IDs, pinned definitions, dice, before/after revisions, arithmetic, choices, effects, resource deltas, visibility policy |
| `FacetsRulesPack` | Pack/version, dependency versions, content IDs, compatibility and admission policy |

Portable JSON uses string IDs, integer mechanics, sorted-key canonical output and arrays with explicitly defined ordering. No node paths, script paths, callable values, Godot object IDs or serialized executable Resources. Trusted local `.tres` files are an authoring convenience; imported third-party character data is parsed as JSON into allowlisted fields, never passed to `load()` as executable content.

Use separate version domains: `schema_version: 1`, `ruleset_id: "facets.core"`, `ruleset_version: "0.1.0"`, and independently versioned addon releases. The source sample `gom.facets.core@0.1.0` becomes an explicit legacy alias in a migration; reject unrecognized versions. Future-major schemas fail clearly, without lossy loading. Namespaced `extensions` may round-trip as inert JSON; unknown mechanics fail validation.

A portable character envelope contains identity and a preferred build; it does not authorize importing live journey state:

```json
{
  "schema_version": 1,
  "ruleset_id": "facets.core",
  "ruleset_version": "0.1.0",
  "character_id": "demo.mara_vale",
  "identity": {
    "name": "Mara Vale",
    "drive": "Find the missing people from the night market",
    "code": "Never abandon a passenger",
    "hindrance": "Pursues disappearance leads despite urgent deliveries",
    "tell": "Touches the seal on her courier bag"
  },
  "preferred_build": {
    "facets": {"force": 2, "agility": 4, "cunning": 3, "empathy": 3, "tenacity": 2, "sense": 4},
    "skills": {"stealth": 2, "investigation": 2, "influence": 2, "technology": 2, "athletics": 1, "sleight": 1, "survival": 1, "medicine": 1},
    "talents": ["core.second_look", "core.field_engineer"],
    "capabilities": []
  },
  "memories": [],
  "extensions": {}
}
```

Publish JSON Schema and positive/negative fixtures for every transport type. Enforce type/range checks in GDScript too; schemas alone do not validate gameplay eligibility. Import limits: 1 MiB per character, nesting ≤16, ≤128 skills/talents/capabilities each, text fields ≤4096 characters; oversized data fails before constructing runtime objects. Limits are configurable only by the trusted host.

## 5. Public APIs and host integration

These are proposed interfaces to implement, not existing executable code. Return typed replies carrying either a value or a structured error; never use ambiguous null or a dictionary with optional magic keys. Error fields: `code`, `message`, `field_path`, `retryable`; visible messages must omit hidden facts.

| API | Contract |
|---|---|
| `FacetsResolver.evaluate(check, dice, adjustments)` | Pure arithmetic on already validated inputs; no state mutation or RNG |
| `FacetsProbability.enumerate(check, adjustments)` | Exact 36-outcome counts, no RNG |
| `session.preview(request)` | Validate authority/eligibility and build visible immutable preview; no spending |
| `session.commit(preview_token, options, request_id)` | Revalidate revision, persist commitment and dice once, return decision or final event |
| `session.choose(event_id, decision_id, option_id, request_id)` | Validate and persist choice; finalize atomically when decisions complete |
| `session.get_event(event_id)` | Return existing pending/final record without reroll |
| `session.save(store)` / `FacetsSession.restore(store, registry)` | Persist/recover state, pending choices and idempotency records |
| `FacetsCharacterCodec.decode(json)` | Parse, validate and return portable definition or field errors |
| `FacetsAdmission.propose(character, policy)` | Return legal proposed build plus exclusions, warnings and explanation |

`FacetsActionRequest` fields: actor ID, action ID, approach ID, target IDs, tool/helper IDs, expected revision. Authorization is an out-of-band session/host principal, not a trusted field supplied by the model. Resolve difficulty and effects from the pinned registry and world snapshot.

Convenience arithmetic example, intentionally separate from stateful gameplay:

```gdscript
# API-shape illustration; supporting types are deliverables.
var check := FacetsCheckInput.new()
check.facet = 3
check.skill = 2
check.target = 13
check.allows_costly_success = true
var evaluation := FacetsResolver.evaluate(check, Vector2i(3, 3), FacetsAdjustments.new())
# total 11, margin -2, provisional costly-success offer; no effects applied.
```

Host ports:

- `WorldPort`: snapshots, validated perception/access/adjacency facts, atomic effect batches and revision checking.
- `OperationRegistry`: allowlisted requirements/effects with parameter schemas and deterministic evaluation. Examples: require accessible controller, open target, advance patrol, lock controller, mark trace.
- `DiceSource`: returns two integers in 1…6; production uses a session-owned RNG, tests inject dice.
- `PersistencePort`: atomic durable session transactions, load and migration support.
- `PresentationPort`: receives committed visible events; never changes authoritative state.

Deliver an in-memory world implementation and a file-backed session store. The default world is owned by the session so its changes and counters share one transaction. External host worlds must implement equivalent atomic revision semantics; a callback that partially mutates a scene tree is insufficient. Apply visuals from committed events afterward.

## 6. Transaction, choice and replay semantics

State machine: preview → committed/rolled → pending decisions → finalized. Preview can be discarded freely. A committed check cannot be canceled into a free reroll.

1. Preview checks actor authority, knowledge, tools, capabilities, restrictions, approach and retry lock. It returns an opaque token bound to actor, canonical request, definition versions and state revision. Do not expose secret prerequisite details or internal objects.
2. On commit, reject stale tokens before costs or RNG. Serialize transactions per session. Check `request_id`: same ID and payload returns the prior response; different payload returns `IDEMPOTENCY_CONFLICT`.
3. Reserve needed resources, draw two dice, and durably record push payment, dice, pinned inputs and pending record in one transaction. Publish the roll only after storage succeeds. Persistence failure leaves the old committed state intact; restore RNG state before retry.
4. Offer Resolve spending first when legal, then recompute bands. Offer costly-success acceptance/decline if still relevant. Offer a strong-benefit selection when multiple legal benefits exist. Freeze each decision ID and allowed options. A single harmless strong benefit may auto-select; consent-requiring benefits may not.
5. **Implementation decision:** a simple default session holds its world revision locked while a check awaits choices. UI/narration may run, but new state-changing commands queue. This avoids invalidating accepted stakes mid-choice. More concurrent hosts need explicit reservation/conflict design and are outside v0.1.
6. Missing response stays pending across save/load. Explicit abandonment declines Resolve and costly success; use the normal determined outcome, or failure for an unaccepted costly band. Do not refund push. If a strong benefit choice is abandoned, choose only a predeclared safe default; otherwise remain pending.
7. Validate every chosen effect against the registry, stage a complete state copy, then atomically finalize effects, resources, counters and event. A failed write or effect validation applies nothing partially and retains the pending record for recovery.
8. Emit presentation signals after durable finalization. Duplicate narration, delivery or load does not reapply effects, spend resources or award milestones.

Save format includes schema/rules versions, initial or checkpoint state, ordered event journal, last sequence, pending transaction/choices, request-id map, random stream metadata and usage/award ledgers. The file store writes a validated complete temporary save and atomically replaces the prior save, retaining a recoverable previous copy. Report write failure; never claim durable commit from an in-memory success alone.

Replay uses recorded dice and ordered effects, not a new seed. Godot's RNG implementation is not a cross-version portability contract. Seeded reproducibility is limited to the pinned implementation; language-neutral conformance supplies explicit dice. Apply events after the checkpoint sequence only. Unknown operation versions or corrupt event sequences stop with actionable errors.

Retry locks key on actor, objective, approach and relevant-state fingerprint. The host authorizes meaningful changes (new tool/evidence/route/helper or consequential time); a global revision increment alone does not unlock attempts. Cache unchanged observations by observer and relevant scene/perception state. Second Look uses its specific alternate-evidence exception and scene counter.

## 7. Editor experience and exact probability

Character inspector: display six facet controls, creation budgets, skill ranks, two starting talents, identity fields, bond trust/affinity, derived strain capacity and validation errors. Offer courier/investigator/mediator/protector/tinkerer presets as editable templates. Editing one instance must not mutate another shared definition accidentally. Use editor undo/redo for every authoring mutation and mark changed Resources for saving.

Action editor: approaches, requirements, target/defense, modifier sources, push/Resolve eligibility, costly choices, decline effects, failure stakes and bounded benefits on one inspectable surface. Registry-backed selectors prevent unknown operations. Talent editor selects typed hooks and parameters, usage scope and prerequisites; it cannot enter arbitrary effect scripts.

Probability inspector enumerates all 36 dice pairs and shows four bands: failure, costly-success offer, success, strong success. Call the second band an **offer**, not guaranteed success. If cost is unsupported, merge it into failure. Show exact fractions and rounded percentages; independently rounded totals may vary slightly from 100%. Show fixed Push/Resolve scenarios separately; do not assume the player always spends Resolve. Disable impossible toggles using supplied state.

Correct fixture for Cunning 5 + Technology 3 versus target 14, no bonuses:

| Band | Outcomes | Probability |
|---|---:|---:|
| Failure | 3/36 | 8.33% |
| Costly-success offer | 7/36 | 19.44% |
| Success | 20/36 | 55.56% |
| Strong success | 6/36 | 16.67% |

Without costly success, failure is 10/36 (27.78%). Do not use the illustrative pitch's 8/14/42/36 percentages or its “failure + progress” outcome label. Label this build as advanced: skill 3 and facet 5 are not standard creation values.

Validation dock lists errors by Resource and field, navigates to the offending field, and blocks demo content export on invalid definitions. Runtime/import validation remains mandatory even when editor controls constrain inputs. Do not reveal private NPC facts in player-facing probability explanations.

## 8. Optional AI adapter

Core has no network access. AI is an optional conversion boundary: bounded observation → proposed intent → normal validation/preview → normal transaction → visible event → narration. Manual UI and fake provider use the same requests.

Proposal schema allows only actor/action/approach/target/tool/helper references and optional display text. Forbid difficulty, dice, stat mutations, resource grants, arbitrary effects, new object IDs and private facts. Provider output is untrusted JSON: validate shape, size and catalog membership before creating a request. The host checks authority even for well-formed proposals.

Supply a provider interface with asynchronous proposal/narration callbacks, cancellation and timeout handling, plus a deterministic fake implementation. No API keys or vendor SDK in the addon. A host may connect any local or remote model that can satisfy the schema; do not claim every model will do so reliably.

Build observation and narration views through witness/perception policy before invoking the provider. Preview errors cannot disclose unseen evidence. Dialogue is presentation, never executable state. On malformed intent, show actionable clarification and keep state unchanged. On narration failure, show a deterministic fallback from the committed event; retry without reroll. NPC policies choose resources/costs from authored priorities and cannot bypass the same rules.

## 9. Optional combat adapter

Implement source §7 as a separate package. Initiative is Agility + Sense descending with stable actor-ID ties. One move and one action per turn; action may become a second move. One reaction per round, including first round; Overwhelmed/Incapacitated restrictions prevail.

Close defense: `7 + Agility + Fighting`; ranged defense: `7 + Agility + Athletics`. Cover contributes +2 defense once, within cap. Close range is same zone, ordinary ranged adjacent, long-range distant visible; compatible ammunition and line of sight are prerequisites. Standard strikes have no costly-success option.

Light/standard/heavy harm: 1/2/3; strong adds 1; armor 0–2 subtracts to minimum zero. Heavy disallows movement for the entire attacking turn: reject attack after movement and movement after attack. Harm 3 gives Injured (−1 physical); 6 Incapacitated. Death only under a declared journey policy. Defend consumes action for +2 defense until next turn, within cap; no default opportunity attacks.

Medicine against 11 with supplies/action and willing target removes 1 harm on success, 2 on strong, no costly success, one benefit per patient per encounter. Stabilized Incapacitated actors remain unable to act until encounter end and harm below 6. Full rest removes 2 harm. Bodyguard intercepts once per round using reaction, same-zone clear path, interceptor armor; disallow interception chains for one hit. Last Reserve permits one normal turn while Overwhelmed once per scene, without restoring reaction or bypassing Incapacitated. These last ordering/chain constraints are implementation decisions that prevent ambiguous recursion.

## 10. Playable demonstration

Build a compact 2D Control-based demo; no expensive art prerequisite. Use Mara's exact source build and a second standard character focused on Empathy/Tenacity, validated against creation budgets. Scene: **Night Market Delivery**, approximately ten minutes, playable without AI or network.

Three authored routes: social request to guard (Empathy + Influence), controller access/repair (Cunning + Technology), rooftop entry (Agility + Athletics). Each has its own prerequisites and consequences, with all stakes visible before commitment. Include a stranded passenger, a real deadline, one identity-trigger choice, one milestone and a second scene showing the retained consequence.

Mandatory scripted walkthrough fixture: Mara bypasses controller at target 13, Cunning 3 + Technology 2, dice 3 and 3 → total 11, margin −2. Branch A accepts trace and opens door. Branch B declines and fails, advancing patrol/locking controller. Branch C spends 1 Resolve → total 13, clean success. Save during the offered choice; reload and finish each branch. Investigating the passenger misses the delivery window and awards eligible Resolve once.

Runtime UI includes character sheet, legal actions, preview/stakes, roll breakdown, choice buttons, event log, save/load and demo reset. Reset creates a new journey state under policy. It does not silently erase profile records. Demo-only fixed dice are visibly marked and absent from normal exported gameplay controls.

## 11. Acceptance suite

Implement a headless test runner using Godot built-ins; external test frameworks may be development-only. Exit nonzero on failure. Commit explicit input/expected-output JSON fixtures so a future Swift implementation can run the same rules tests. The following are minimum acceptance groups, not a claim that 30 individual assertions suffice.

| ID | Required test and expected behavior |
|---|---|
| T01 | Standard creation totals/caps; negative ranks, overspend and lowering below 2 rejected |
| T02 | Enumerate every 2d6 pair across representative bonus/target values; match all source calibration rows |
| T03 | Margins −3, −2, −1, 0, 3, 4 map exactly; costly band fails when disabled |
| T04 | No natural criticals; impossible actions consume neither dice nor resources |
| T05 | Modifiers clamp after validated aggregation; duplicated factors rejected |
| T06 | Only one +1 assistance, relationship ±1, worst condition up to −2 |
| T07 | Opposed defense uses correct stats/cap and never rolls |
| T08 | Push at capacity−3 allowed; at capacity−2 rejected; rejected push draws nothing |
| T09 | Resolve 0/3 boundaries, once-per-check spending and all upgrade bands |
| T10 | Overwhelmed activates/removes correctly; no stacked numeric condition penalties |
| T11 | Breather once per authorized opportunity; no recovery from spoken scene reset |
| T12 | Accepted identity cost awards once per actor/scene; rejection/trivial duplicate awards zero |
| T13 | Each noncombat talent triggers only under exact source prerequisites and usage limit |
| T14 | Rephrase failed action twenty times; unchanged relevant state gets no new dice |
| T15 | Unrelated world revision does not unlock retry; meaningful authored change does |
| T16 | Stale preview rejected before push/resource use and RNG consumption |
| T17 | Duplicate commit/choice returns same record; conflicting payload same ID errors |
| T18 | Save/reload pending Resolve/cost/benefit choice retains dice, payments and options |
| T19 | Inject persistence/effect failure; no partial final state, recoverable pending record |
| T20 | Replay checkpoint plus events reproduces state/counters; replay never redraws dice |
| T21 | Duplicate events/narration never duplicate effects, Growth or resource spending |
| T22 | Unknown effect, nonexistent tool, injected stat change and inaccessible fact rejected |
| T23 | NPC/private facts absent from another actor's provider and preview views |
| T24 | Hard social refusal survives every dice outcome; player beliefs remain unmodified |
| T25 | Milestone dedupe, costs, facet chapter limit, prerequisites and actual-cost respec |
| T26 | Advanced character standard admission legal; identity retained; local powers/facts excluded |
| T27 | JSON round trip, alias migration, future version, oversize and malformed import handling |
| T28 | Shared `.tres` creates independent live actors; core works with plugin disabled |
| T29 | Editor enable/disable cycles, undo/redo, budgets and exact probability fixture |
| T30 | All three demo routes, Mara branches, persistent consequence and offline fake AI flow |
| C01 | Combat initiative ties, turn movement budget, heavy weapon and reaction refresh |
| C02 | Range/LOS/ammo/cover, defend expiry, harm/armor and no costly standard strike |
| C03 | Injury/incapacity, medicine encounter limit, stabilization and recovery |
| C04 | Bodyguard eligibility/interception armor and Last Reserve limits |

Minimum developer command contract:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script tests/run_tests.gd
```

The implementer must verify these commands against the pinned binary and document its actual invocation name. CI runs import, parse and headless tests on that exact version; desktop demo/export smoke tests cover macOS, Windows and Linux before claiming those platforms. Record performance on a declared machine, but do not promise an arbitrary NPC throughput target. Inspect editor UX manually at normal and high display scaling.

## 12. Ordered implementation milestones

| Milestone | Concrete output | Completion gate |
|---|---|---|
| M0: Contracts | Repository, copied source rules, schemas, typed DTOs, fixtures and decision log | Creation/action data validates; no unexplained rule changes |
| M1: Pure core | Resolver, modifiers, probability, DiceSource, Resources | T01–T10; exact pitch-correction fixture |
| M2: Session | Preview/commit/choice, registry, file store, replay/retry, state effects | T11–T12 and T14–T24, including injected failures |
| M3: Content | Six noncombat talents, identity, progression, admission and codecs | T13, T25–T28; sample character validates |
| M4: Editor | Inspectors, authoring dock, probability and undo/redo | T29; fresh project installation demonstrated |
| M5: Playable MVP | Three-route demo, fake AI adapter, tutorial | T30 plus full noncombat regression suite |
| M6: v0.1 release | Combat and remaining talents, release ZIP, documentation and CI | C01–C04; all eight talents and clean-project import/export |

Do not begin by building AI prompts or a large editor. First prove the rules with injected dice, then transactional state, then authoring and presentation. Each milestone includes a short implementation summary, actual test output and remaining known limitations. Do not call a milestone complete if its gate is stubbed or skipped.

## 13. Release and integration checklist

Deliver the repository with README, installation/uninstallation, five-minute tutorial, public API guide, extension/operation guide, save compatibility policy, original rules, implementation decisions, conformance fixtures, changelog, demo and issue templates. Recommend MIT for original implementation and documentation, subject to owner approval before public licensing; inventory and preserve third-party asset licenses. No publishing, account setup or store submission is authorized by this document alone.

Produce an addon-only ZIP containing `addons/facets/`, with optional AI/combat packages clearly identified, plus a separate example-project release. Verify installation in a blank project and gameplay export with editor plugin disabled. Pin pack and save dependencies; migrations are explicit, never automatic silent balance changes.

Before distribution, verify the current Godot catalog submission route and AI-disclosure policy on official publisher pages. The pitch's specific Asset Store launch date and requirements are not dependencies or verified claims in this implementation brief. Separate AI functionality from any disclosure about how the source/assets were authored; separation does not remove applicable disclosure obligations.

For Game of Mods/Swift integration, share schemas, fixtures and rules versions. Build a Swift adapter only after inspecting the actual repository; do not infer existing type names. Character interchange carries identity/preferences plus admission; identical gameplay replay requires matching rules, operations and recorded dice. Cross-game achievements, memories and powers are never trusted merely because the file is valid JSON.

## 14. Official engineering references

Checked October 7, 2026; implementation details above are proposed project design unless attributed here.

- [Godot 4.6: Making plugins](https://docs.godotengine.org/en/4.6/tutorials/plugins/editor/making_plugins.html) — addon location, `plugin.cfg`, GDScript editor plugins, tool execution and lifecycle cleanup.
- [Godot 4.6: Resources](https://docs.godotengine.org/en/4.6/tutorials/scripting/resources.html) — custom data Resources and reuse; motivates separating definitions from live session state.
- [Godot 4.6: RandomNumberGenerator](https://docs.godotengine.org/en/4.6/classes/class_randomnumbergenerator.html) — seed/state behavior and implementation-version caveat; motivates storing actual dice for portable replay.
- Supplied `Game-of-Mods-FACETS.md`, October 6, 2026 — source of all FACETS mechanics. Godot documentation is authority for platform APIs, not game rules.

## 15. Copyable assignment for the implementing coder

> Implement FACETS according to this specification and the supplied rules draft. Start with M0 and M1 and continue in milestone order. Keep Core free of editor, network, AI-provider and Game of Mods dependencies. Implement exact rules and fixture-driven probability before UI. Preserve pending decisions, resource accounting and idempotency across save/load. Use Godot Resources for trusted authoring and validated JSON for portability. Deliver a playable offline demo and an optional fake-provider AI path. Record departures as explicit design decisions, never silently change the rules to make tests pass. Report only verification actually executed. Do not publish the repository or submit a store listing as part of implementation without the owner's authorization.
