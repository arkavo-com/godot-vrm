# Five-minute tutorial

This walks through one check end to end with the public API. Run it as a
`SceneTree` script (`godot --headless --path . --script my_tutorial.gd`) after
importing the project once.

## 1. Load the rules and author an action

```gdscript
extends SceneTree

func _initialize() -> void:
	var registry := FacetsRegistry.core()
	registry.add_action({
		"id": "tutorial.pick_lock", "version": 1, "display_name": "Pick the lock",
		"approaches": [{"id": "fingers", "facet": "agility", "skill": "sleight"}],
		"difficulty": {"kind": "fixed", "target": 13},
		"allows_costly_success": true,
		"costly_options": [{"id": "noise", "label": "Make some noise", "effects": [
			{"op": "world.counter_add", "params": {"counter_id": "alarm", "amount": 1}, "label": "Someone hears you"}]}],
		"success_effects": [{"op": "object.set_flag", "params": {"object_id": "door", "key": "open", "value": true}, "label": "The door opens"}],
		"failure_effects": [{"op": "actor.strain", "params": {"amount": 1}, "label": "Frustration"}],
		"stakes": {"success": "The door opens.", "failure": "You lose time (1 strain)."},
		"retry_policy": "lock_until_change",
	})
```

In the editor you would author the same action as a `FacetsActionResource`
(**New Resource → FacetsActionResource**); the FACETS panel above the
inspector shows odds per preset and only lets you add allowlisted operations.

## 2. Create a character and a world

```gdscript
	var hero := FacetsActorState.new()
	hero.actor_id = "hero"
	hero.display_name = "Hero"
	hero.build = FacetsBuild.from_dict(registry.get_archetype("core.archetype.courier")["build"])
	print(FacetsValidator.validate_creation(hero.build, registry))  # [] means legal
	var world := FacetsWorldSnapshot.new()
	world.scene_id = "tutorial"
	world.add_actor(hero)
	world.objects = {"door": {"open": false}}
	var session: FacetsSession = FacetsSession.create(registry, world, {"seed": 42}).value
```

## 3. Preview: stakes and exact odds before committing

```gdscript
	var request := FacetsActionRequest.make("hero", "tutorial.pick_lock", "fingers")
	var preview: FacetsCheckPreview = session.preview(request).value
	for odds in preview.odds:
		print(odds.scenario, " fail ", odds.fraction("failure"), " offer ", odds.fraction("costly_offer"),
			" success ", odds.fraction("success"), " strong ", odds.fraction("strong_success"))
	print("Push: ", preview.push_note)
```

## 4. Commit, then answer decisions

```gdscript
	var event: FacetsResolutionEvent = session.commit(preview.token, {"push": false}, "tutorial-1").value
	print("Rolled ", event.dice, " total ", event.base["total"], " -> ", event.base["band"])
	var step := 0
	while event.is_pending():
		step += 1
		var decision := event.pending_decision
		print(decision.prompt)
		for option in decision.options:
			print("  ", option["id"], ": ", option["label"])
		event = session.choose(event.event_id, decision.decision_id, decision.option_ids()[0], "tutorial-choice-%d" % step).value
	print("Final: ", event.final_band, " ", event.effect_labels)
	print("Door open: ", session.snapshot().object_flag("door", "open"))
	quit()
```

Decisions arrive in a fixed order: **Resolve** (spend 1 for +2, shown with
the band it would produce), then the **costly offer** (accept the authored
cost or fail), then a **strong benefit** choice when more than one benefit is
legal.

## 5. Persist and recover

Pass `{"store": FacetsFileStore.at("user://tutorial.json")}` to
`FacetsSession.create`. Every transaction is written atomically before it is
visible; `FacetsSession.restore(FacetsFileStore.at("user://tutorial.json"),
registry)` replays the journal and restores pending choices, request IDs and
the RNG stream.

Next: play `examples/night_market/night_market.tscn`, read `api.md`, and see
`extension-guide.md` to add your own operations and packs.
