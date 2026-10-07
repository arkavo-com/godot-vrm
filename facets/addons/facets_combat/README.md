# FACETS combat (optional)

Zone combat adapter implementing rules source section 7, plus the two combat
talents (Bodyguard, Last Reserve) that complete the eight source talents.
Core FACETS never depends on this package.

```gdscript
var registry := FacetsRegistry.core()
FacetsCombat.register(registry)            # hooks + combat talents pack
var zones := FacetsZoneMap.from_dict({"alley": {"adjacent": ["roof"]}, "roof": {"adjacent": ["alley"], "cover": true}})
var setup := {"mara": {"zone": "alley", "weapon": load("res://addons/facets_combat/content/weapons/knife.tres").to_dict(), "armor": 0}}
var encounter: FacetsEncounter = FacetsEncounter.create(registry, zones, actors, setup, FacetsDiceSource.seeded(7)).value
encounter.attack("mara", "thug", "slash")
encounter.end_turn("mara")
...
encounter.end_encounter()
session.apply_host_effects("mara", encounter.journey_effects("mara"), "Fight in the alley")
```

* Initiative: Agility + Sense descending, ties by actor ID.
* One move and one action per turn; the action may become a second move.
* One reaction per round (available in the first round); Overwhelmed and
  Incapacitated actors cannot react.
* Close defense 7 + Agility + Fighting; ranged 7 + Agility + Athletics; cover
  (ranged attacks) and Defend each +2 once, within the +/-3 cap.
* Ranges: close = same zone; ranged = same or adjacent with line of sight;
  long = any visible zone. Ranged weapons need compatible ammunition.
* Standard strikes have no costly success. Harm light 1 / standard 2 /
  heavy 3, +1 on a strong hit, minus armor 0-2. Harm 3 Injured, 6
  Incapacitated; death only under a declared lethal journey policy.
* Heavy weapons: no attack after moving, no moving after attacking.
* Medicine vs 11 with supplies and an action: -1 harm, -2 on strong, one
  benefit per patient per encounter; stabilizes Incapacitated patients, who
  stay unable to act until the encounter ends with harm below 6.
* Overwhelmed actors get a move *or* an action each turn (implementation
  decision D-016); Last Reserve grants one normal turn per scene.

See `docs/decisions.md` for the implementation decisions behind the parts
the source draft leaves open.
