extends Control
## Night Market Delivery UI: character sheet, legal actions, preview with
## stakes and exact odds, roll breakdown, choice buttons, event log,
## save/load/reset, optional fake-AI suggestions and debug-only fixed dice.
## All game rules live in FACETS; this script only presents and forwards.

var demo: NightMarketDemo
var adapter: FacetsAiAdapter
var _actor_id := NightMarketDemo.MARA
var _preview: FacetsCheckPreview

var _sheet: RichTextLabel
var _scene_label: Label
var _consequences: Label
var _actions: VBoxContainer
var _preview_text: RichTextLabel
var _push: CheckBox
var _commit: Button
var _choices: HFlowContainer
var _prompt: Label
var _log: RichTextLabel
var _status: Label
var _actor_select: OptionButton
var _dice_row: HBoxContainer


func _ready() -> void:
	var reply := NightMarketDemo.create({"store": FacetsFileStore.at(NightMarketDemo.DEFAULT_SAVE)})
	if not reply.ok:
		push_error("Night Market could not start: %s" % reply.error)
		return
	demo = reply.value
	demo.changed.connect(_refresh)
	demo.logged.connect(_on_logged)
	adapter = FacetsAiAdapter.make(demo.session, FacetsFakeProvider.new())
	adapter.proposal_ready.connect(_on_proposal)
	_build()
	for line in demo.log_lines:
		_on_logged(line)
	_refresh()


func _process(_delta: float) -> void:
	if adapter != null:
		adapter.tick(Time.get_ticks_msec())


# --- Layout -------------------------------------------------------------------------

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.07, 0.06, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	margin.add_child(columns)

	var left := _panel(columns, 0.28)
	left.custom_minimum_size.x = 300
	_actor_select = OptionButton.new()
	_actor_select.add_item("Mara Vale")
	_actor_select.set_item_metadata(0, NightMarketDemo.MARA)
	_actor_select.add_item("Iris Kade")
	_actor_select.set_item_metadata(1, NightMarketDemo.IRIS)
	_actor_select.item_selected.connect(func(index: int) -> void:
		_actor_id = str(_actor_select.get_item_metadata(index))
		_preview = null
		_refresh())
	left.add_child(_actor_select)
	_sheet = _rich(left, true)

	var middle := _panel(columns, 0.40)
	middle.custom_minimum_size.x = 400
	_scene_label = _label(middle, 18)
	_consequences = _label(middle, 13)
	_consequences.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_heading("Legal actions"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(scroll)
	_actions = VBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_actions)
	var specials := HFlowContainer.new()
	middle.add_child(specials)
	_button(specials, "Hear Tamsin out (Mara's hindrance)", func() -> void: _report(demo.offer_passenger_lead()))
	_button(specials, "Steady Voice: Iris -> Mara", func() -> void: _report(demo.use_steady_voice(NightMarketDemo.IRIS, NightMarketDemo.MARA)))
	_button(specials, "Take a breather", func() -> void: _report(demo.take_breather(_actor_id)))
	_button(specials, "Go to the clinic", func() -> void: _report(demo.go_to_clinic()))
	_button(specials, "Suggest (offline fake AI)", _suggest)

	var right := _panel(columns, 0.32)
	right.add_child(_heading("Preview and stakes"))
	_preview_text = _rich(right, true)
	_preview_text.scroll_following = false
	_preview_text.custom_minimum_size.y = 260
	var commit_row := HBoxContainer.new()
	_push = CheckBox.new()
	_push.text = "Push (+1 for 2 strain)"
	commit_row.add_child(_push)
	_commit = _button(commit_row, "Commit", _on_commit)
	right.add_child(commit_row)
	_prompt = _label(right, 14)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choices = HFlowContainer.new()
	right.add_child(_choices)
	right.add_child(_heading("Event log"))
	_log = _rich(right, true)
	_log.custom_minimum_size.y = 160
	var system := HFlowContainer.new()
	right.add_child(system)
	_button(system, "Save", func() -> void: _report(demo.save_game()))
	_button(system, "Load", func() -> void:
		_report(demo.load_game())
		adapter.session = demo.session)
	_button(system, "Reset journey", func() -> void:
		_report(demo.new_journey())
		adapter.session = demo.session
		_preview = null)
	_dice_row = HBoxContainer.new()
	right.add_child(_dice_row)
	if NightMarketDemo.fixed_dice_allowed():
		var warning := Label.new()
		warning.text = "DEMO FIXED DICE (debug builds only):"
		warning.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_dice_row.add_child(warning)
		for pair in [Vector2i(3, 3), Vector2i(1, 1), Vector2i(6, 6)]:
			_button(_dice_row, "%d+%d" % [pair.x, pair.y], func() -> void: demo.queue_fixed_dice(pair))
	_status = _label(right, 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _panel(parent: Control, ratio: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	box.size_flags_stretch_ratio = ratio
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	return box


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	return label


func _rich(parent: Control, expand: bool) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.scroll_following = true
	rich.custom_minimum_size.y = 120
	if expand:
		rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(rich)
	return rich


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# --- Refresh ------------------------------------------------------------------------

func _refresh() -> void:
	if demo == null or _sheet == null:
		return
	var world := demo.session.snapshot()
	var state := world.actor(_actor_id)
	_scene_label.text = "Scene: %s   Clock %d / deadline %d   Patrol %d" % ["Market gate" if world.scene_id == NightMarketDemo.SCENE_GATE else "The clinic", world.clock, NightMarketDemo.DEADLINE, int(world.counters.get("patrol", 0))]
	_consequences.text = "\n".join(demo.consequences()) if world.scene_id == NightMarketDemo.SCENE_CLINIC else "Get the sealed package to the clinic inside the market hall before curfew."
	_sheet.text = _sheet_text(state)
	for child in _actions.get_children():
		child.queue_free()
	for entry in demo.actions_for(_actor_id):
		var button := Button.new()
		button.text = str(entry["label"])
		button.disabled = not bool(entry["available"]) or demo.session.has_pending()
		button.tooltip_text = str(entry["reason"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: _on_preview(str(entry["action_id"]), str(entry["approach_id"])))
		_actions.add_child(button)
		if not bool(entry["available"]):
			var reason := Label.new()
			reason.text = "    " + str(entry["reason"])
			reason.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_actions.add_child(reason)
	_render_preview()
	_render_choices()


func _sheet_text(state: FacetsActorState) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % state.display_name)
	lines.append("[i]%s[/i]" % state.identity.get("drive", ""))
	lines.append("Code: %s" % state.identity.get("code", ""))
	lines.append("Hindrance: %s" % state.identity.get("hindrance", ""))
	lines.append("")
	for facet_id in FacetsRules.FACETS:
		lines.append("%s %d" % [facet_id.capitalize(), state.build.facet(facet_id)])
	lines.append("")
	var skills: Array = state.build.skills.keys()
	skills.sort()
	lines.append("Skills: " + ", ".join(skills.map(func(id: String) -> String: return "%s %d" % [id, state.build.skill(id)])))
	lines.append("Talents: " + ", ".join(state.build.talents))
	lines.append("")
	lines.append("Strain %d / %d   Resolve %d / 3   Growth %d" % [state.strain, state.strain_capacity(), state.resolve, state.growth])
	lines.append("Conditions: %s" % (", ".join(state.conditions) if not state.conditions.is_empty() else "none"))
	var items: Array = state.items.keys()
	items.sort()
	lines.append("Carrying: %s" % (", ".join(items.map(func(id: String) -> String: return "%s x%d" % [id, state.item_count(id)])) if not items.is_empty() else "nothing"))
	if not state.known_facts.is_empty():
		lines.append("Knows: " + "; ".join(state.known_facts.map(func(id: String) -> String: return str(demo.session.snapshot().facts.get(id, {}).get("label", id)))))
	var accomplishments: Array = state.profile.get("accomplishments", [])
	if not accomplishments.is_empty():
		lines.append("Profile: " + "; ".join(accomplishments))
	return "\n".join(lines)


func _render_preview() -> void:
	if _preview == null:
		_preview_text.text = "Choose an action to see its stakes and exact odds before committing."
		_commit.disabled = true
		_push.disabled = true
		return
	var p := _preview
	var lines: Array[String] = []
	lines.append("[b]%s[/b] - %s %d + %s %d" % [p.action_name, p.facet_id, p.facet_rating, p.skill_id, p.skill_rank])
	for line in p.target_explanation:
		lines.append(line)
	for modifier in p.modifiers:
		lines.append("Modifier: %s %+d%s" % [modifier["label"], int(modifier["contribution"]), (" (%s)" % modifier["note"]) if not str(modifier["note"]).is_empty() else ""])
	if p.modifier_raw != p.modifier_applied:
		lines.append("Situational total capped at %+d." % p.modifier_applied)
	lines.append("Success: %s" % p.stakes.get("success", ""))
	lines.append("Failure: %s" % p.stakes.get("failure", ""))
	for option in p.cost_options:
		lines.append("Possible cost on a near miss: %s" % option["label"])
	for option in p.benefit_options:
		lines.append("Possible strong benefit: %s" % option["label"])
	for odds in p.odds:
		if odds.routine:
			lines.append("Routine: succeeds without a roll.")
			continue
		var title: String = {"base": "Odds", "push": "With Push", "resolve": "If you spend Resolve after the roll", "push+resolve": "Push + Resolve"}.get(odds.scenario, odds.scenario)
		var parts: Array[String] = ["fail %s" % odds.fraction("failure")]
		if odds.allows_costly_success:
			parts.append("offer %s" % odds.fraction("costly_offer"))
		parts.append("success %s" % odds.fraction("success"))
		parts.append("strong %s" % odds.fraction("strong_success"))
		lines.append("%s: %s" % [title, ", ".join(parts)])
	lines.append(p.push_note)
	_preview_text.text = "\n".join(lines)
	_commit.disabled = demo.session.has_pending()
	_push.disabled = not p.push_available
	if not p.push_available:
		_push.button_pressed = false


func _render_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()
	var event := demo.pending()
	if event == null:
		_prompt.text = ""
		return
	_prompt.text = event.pending_decision.prompt
	for option in event.pending_decision.options:
		var option_id := str(option["id"])
		_button(_choices, str(option["label"]), func() -> void: _report(demo.choose(option_id)))
	_button(_choices, "Walk away", func() -> void: _report(demo.abandon()))


# --- Actions --------------------------------------------------------------------------

func _on_preview(action_id: String, approach_id: String) -> void:
	var reply := demo.preview(_actor_id, action_id, approach_id)
	if reply.ok:
		_preview = reply.value
		_status.text = ""
	else:
		_preview = null
		_status.text = reply.error.message
	_render_preview()


func _on_commit() -> void:
	if _preview == null:
		return
	var reply := demo.commit(_preview, _push.button_pressed)
	_preview = null
	_push.button_pressed = false
	_report(reply)


func _suggest() -> void:
	adapter.session = demo.session
	adapter.propose(_actor_id, FacetsPrincipal.ai("fake_ai", [_actor_id]), Time.get_ticks_msec())


func _on_proposal(ticket: FacetsAiTicket) -> void:
	if not ticket.result.ok:
		_status.text = ticket.result.error.message
		return
	var proposal: Dictionary = ticket.result.value
	var request: FacetsActionRequest = proposal["request"]
	var reply := demo.session.preview(request, FacetsPrincipal.ai("fake_ai", [request.actor_id]))
	if reply.ok:
		_preview = reply.value
		_status.text = "Fake AI suggests: %s" % proposal["display_text"]
	else:
		_status.text = reply.error.message
	_render_preview()


func _report(reply: FacetsReply) -> void:
	_status.text = "" if reply.ok else reply.error.message
	_refresh()


func _on_logged(line: String) -> void:
	if _log != null:
		_log.append_text(line + "\n")
