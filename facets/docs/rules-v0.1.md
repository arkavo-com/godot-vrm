# FACETS rules v0.1 — placeholder

> **Status: placeholder.** The implementation brief says to copy the supplied
> rules draft (`Game-of-Mods-FACETS.md`, playable design draft v0.1,
> October 6, 2026) into this file verbatim and keep its draft status. That
> source document was **not available** when this implementation was written;
> only the implementation brief (`implementation-spec-v0.1.md`) was. Replace
> this file with the verbatim source draft.

Until then, the effective rule set is the digest below, taken from section 3 of
the implementation brief. Anything the brief leaves open is recorded as an
implementation decision in [`decisions.md`](decisions.md), never as source
behavior. When the source draft is added, reconcile every decision marked
"pending source" there.

## Digest of the implemented rules (from the brief, §3)

**Facets:** force, agility, cunning, empathy, tenacity, sense. Standard
creation starts at 2 each, adds six points, caps each at 4, total 18. Creation
cannot refund points by lowering a facet. Progressed ratings may reach 5.

**Skills:** athletics, fighting, marksmanship, stealth, sleight,
investigation, survival, technology, craft, medicine, influence, performance.
Creation spends 12 points, at most 2 per skill; general range 0–4; missing
known skills are rank 0; unknown skill IDs are errors; genre skills share the
budget.

**Talents:** two at creation; repeatability explicit. Bonds store trust and
affinity separately (−2…+2) plus obligations and shared events.

**Journey state:** strain 0, Resolve 1, Growth 0. Strain capacity 4 +
tenacity. Resolve 0–3.

**Resolution:** `total = 2d6 + facet + skill + clamp(modifiers, −3, 3) + push
+ resolve`; `margin = total − target`. Margin ≥4 strong success; 0…3 success;
−2…−1 costly-success offer (accepted → success with cost, declined →
failure; failure when the action has no costly success); ≤−3 failure. No
natural criticals. Routine actions succeed without dice; impossible or
ineligible actions do not roll. Targets 9/11/13/15/17/19; fixed targets
allowed. Opposed target `7 + facet + skill + clamp(defense modifiers)`; the
defender does not roll.

**Modifiers:** every modifier names source, factor, scope and value; the same
factor may not apply twice; one assistance (+1 max); one relationship ±1;
only the worst numeric condition, capped at −2; restrictions apply
independently.

**Push:** before commitment, 2 strain for +1, once, only if the result stays
strictly below capacity; outside the cap; never refunded. **Resolve:** after
the roll, spend 1 for +2, once, optional; shown with its effect on the band.

**Overwhelmed:** at capacity (−1 checks, no pushing or combat reactions);
removed below capacity. Breather −2 strain once per authorized opportunity;
secure rest resets strain.

**Identity trigger:** accepting an authored material disadvantage awards 1
Resolve at most once per actor per scene (0 at the cap); rejection gives
nothing.

**Progression:** milestones 1 (small) or 3 (chapter), never both for one
event. At safe checkpoints: skill 2 × new rank (cap 4, practice/instruction),
talent 5 (prerequisites, ≤6 equipped), facet 8 (cap 5, once per completed
chapter). Ledger with actual costs; respec refunds them.

**Admission:** standard admission preserves identity and proposes a legal
18/12/2 build; drops Growth and unadmitted equipment and powers; memories stay
source-labeled references.

**Combat (optional, §9 of the brief):** see `addons/facets_combat/README.md`.
