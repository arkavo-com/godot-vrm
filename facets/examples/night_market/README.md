# Night Market Delivery (FACETS demo)

A compact, Control-based scene (about ten minutes) that runs offline with no
AI and no network. Open `night_market.tscn` (the project's main scene) and
press Play.

**Goal:** get Mara Vale's sealed package to the clinic inside the market hall
before the clock passes 3. Every attempt at the gate costs time.

## Routes into the hall

| Route | Check | Prerequisites | On a near miss | On failure |
|---|---|---|---|---|
| Ask Rook to open the side gate | Empathy + Influence vs 11 | Gate closed, Rook not alerted | Owe Rook a favor | Rook raises the alarm, patrol +1 |
| Bypass the service door controller | Cunning + Technology vs 13 | Controller reachable and unlocked; signal kit (or scrap wire with Field Engineer) | Leave a trace in the market grid | Patrol +1, controller locks |
| Climb in through the roof hatch | Agility + Athletics vs 13 | Hatch reachable, not Injured | 2 strain | Fall (2 strain, fear), patrol +1, route collapses |

All stakes, costs, benefits and exact odds are shown before you commit.

## Other beats

* **Stranded passenger.** Tamsin saw something. *Hear Tamsin out* offers
  Mara's identity trigger: accept and you miss the delivery window but gain
  1 Resolve (once per scene) and learn the lead.
* **Deadline.** Delivering after the window marks the package late.
* **Milestone.** Delivering awards +1 Growth (small milestone) once.
* **Second scene.** *Go to the clinic* starts the next scene. Earlier choices
  persist: a grid trace makes slipping away harder (-1), a late package makes
  the doctor harder to settle (-1), a locked controller stays locked, and
  Tamsin's lead unlocks *Follow the passenger's lead*.
* **Iris Kade** (Empathy/Tenacity) can help Tamsin and use *Steady Voice* on
  Mara after a fear setback (for example a fall from the roof).

## Controls

Character sheet, legal actions (with reasons when unavailable), preview and
stakes, push toggle, roll breakdown in the log, choice buttons for Resolve,
costs and benefits, *Walk away* (abandon: declines Resolve and costs, never
refunds a push), event log, Save, Load and Reset journey. Reset starts a new
journey but keeps profile accomplishments.

*Suggest (offline fake AI)* asks the deterministic fake provider for a
proposal; it goes through the same validation and preview as a button press.

**DEMO FIXED DICE** buttons appear only in debug builds and are visibly
marked; they are absent from release exports.

## Scripted walkthrough

`fixtures/walkthrough_mara.json` is the language-neutral fixture used by the
automated test `tests/cases/test_demo.gd`: Mara bypasses the controller at
target 13 with Cunning 3 + Technology 2 and dice 3+3 (total 11, margin -2).
Branch A accepts the trace and opens the door; branch B declines and fails;
branch C spends Resolve for a clean success. The test saves during the
offered choice, reloads and finishes each branch.

Content lives in `content/` as ordinary Resources (regenerate with
`tools/build_demo_content.gd`).
