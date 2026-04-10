extends CanvasLayer
## In-game editor for tuning 3D model scales and Y offsets in real time.
## Right-side panel with sliders; changes apply live. Save persists to .tres / .cfg.
## Toggle with the SCALE button (top-right) or F2 key.

const CONFIG_PATH: String = "res://config/model_scales.cfg"

# -- UI references --
var _root: Control
var _toggle_btn: Button
var _panel: PanelContainer
var _dropdown: OptionButton
var _scale_slider: HSlider
var _scale_value: Label
var _y_label: Label
var _y_row: HBoxContainer
var _y_slider: HSlider
var _y_value: Label
var _day_night_btn: Button

# -- Data --
var _entries: Array[Dictionary] = []
var _current_idx: int = 0
var _originals: Dictionary = {}  # idx -> { scale, y_offset }
var _preview_is_day: bool = false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_entries()
	_snapshot_originals()
	_build_ui()
	_select_entry(0)
	_reposition_ui.call_deferred()
	get_viewport().size_changed.connect(_reposition_ui)
	SignalBus.phase_changed.connect(_on_game_phase_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F2:
			_toggle_panel()
			get_viewport().set_input_as_handled()


# ── Entry collection ──────────────────────────────────────────

func _collect_entries() -> void:
	_entries.clear()

	# 1) Hex Tile
	var gv := _get_grid_visual()
	_entries.append({
		"name": "Hex Tile",
		"type": "tile",
		"scale": gv.tile_model_scale.x if gv else 1.0,
		"y_offset": 0.0,
		"has_y": false,
	})

	# 2) Hero
	var hero := _get_hero()
	_entries.append({
		"name": "Hero",
		"type": "hero",
		"scale": hero.model_scale_factor if hero else 0.5,
		"y_offset": hero.model_y_offset if hero else 0.15,
		"has_y": true,
	})

	# 3) Enemies from registry
	for ed in EnemyRegistry.get_all():
		_entries.append({
			"name": ed.display_name,
			"type": "enemy",
			"id": ed.id,
			"data": ed,
			"scale": ed.model_scale,
			"y_offset": ed.model_y_offset,
			"has_y": true,
		})

	# 4) Buildings with GLB models only
	for bd in BuildingRegistry.get_all():
		if bd.model_path != "":
			_entries.append({
				"name": bd.display_name,
				"type": "building",
				"id": bd.id,
				"data": bd,
				"scale": bd.model_scale.x,
				"y_offset": bd.model_y_offset,
				"has_y": true,
			})


func _snapshot_originals() -> void:
	for i in range(_entries.size()):
		_originals[i] = {
			"scale": _entries[i]["scale"],
			"y_offset": _entries[i]["y_offset"],
		}


# ── UI construction ──────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "EditorRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Toggle button
	_toggle_btn = Button.new()
	_toggle_btn.text = "SCALE"
	_toggle_btn.add_theme_font_size_override("font_size", 13)
	_root.add_child(_toggle_btn)
	_toggle_btn.pressed.connect(_toggle_panel)

	# Panel
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(280, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Model Scale Editor"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Entity dropdown
	_dropdown = OptionButton.new()
	for i in range(_entries.size()):
		_dropdown.add_item(_entries[i]["name"], i)
	_dropdown.item_selected.connect(_on_entry_selected)
	vbox.add_child(_dropdown)

	vbox.add_child(HSeparator.new())

	# Scale controls
	var scale_lbl := Label.new()
	scale_lbl.text = "Scale"
	scale_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(scale_lbl)

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	vbox.add_child(scale_row)

	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.05
	_scale_slider.max_value = 3.0
	_scale_slider.step = 0.01
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.value_changed.connect(_on_scale_changed)
	scale_row.add_child(_scale_slider)

	_scale_value = Label.new()
	_scale_value.custom_minimum_size = Vector2(45, 0)
	_scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scale_value.add_theme_font_size_override("font_size", 13)
	scale_row.add_child(_scale_value)

	# Y Offset controls
	_y_label = Label.new()
	_y_label.text = "Y Offset"
	_y_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_y_label)

	_y_row = HBoxContainer.new()
	_y_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_y_row)

	_y_slider = HSlider.new()
	_y_slider.min_value = -1.0
	_y_slider.max_value = 1.0
	_y_slider.step = 0.01
	_y_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_y_slider.value_changed.connect(_on_y_changed)
	_y_row.add_child(_y_slider)

	_y_value = Label.new()
	_y_value.custom_minimum_size = Vector2(45, 0)
	_y_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_y_value.add_theme_font_size_override("font_size", 13)
	_y_row.add_child(_y_value)

	vbox.add_child(HSeparator.new())

	# Day/Night preview toggle
	_day_night_btn = Button.new()
	_day_night_btn.text = "Switch to Day"
	_day_night_btn.pressed.connect(_toggle_day_night)
	vbox.add_child(_day_night_btn)

	vbox.add_child(HSeparator.new())

	# Save / Reset
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)


func _reposition_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	_toggle_btn.position = Vector2(vp.x - 80, 8)
	_toggle_btn.size = Vector2(72, 28)
	_panel.position = Vector2(vp.x - 296, 44)


# ── Panel toggle ─────────────────────────────────────────────

func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_toggle_btn.text = "CLOSE" if _panel.visible else "SCALE"
	if not _panel.visible:
		# Restore game lighting when closing
		var dnv := _get_day_night_visual()
		if dnv:
			dnv.restore_current_phase()
		_preview_is_day = DayNightManager.is_day()
		_day_night_btn.text = "Switch to Night" if _preview_is_day else "Switch to Day"


# ── Entry selection ──────────────────────────────────────────

func _on_entry_selected(idx: int) -> void:
	_select_entry(idx)


func _select_entry(idx: int) -> void:
	_current_idx = idx
	var entry := _entries[idx]

	_scale_slider.set_value_no_signal(entry["scale"])
	_scale_value.text = "%.2f" % entry["scale"]

	var has_y: bool = entry["has_y"]
	_y_label.visible = has_y
	_y_row.visible = has_y
	if has_y:
		_y_slider.set_value_no_signal(entry["y_offset"])
		_y_value.text = "%.2f" % entry["y_offset"]


# ── Slider callbacks ─────────────────────────────────────────

func _on_scale_changed(value: float) -> void:
	_entries[_current_idx]["scale"] = value
	_scale_value.text = "%.2f" % value
	_apply_scale(_current_idx)


func _on_y_changed(value: float) -> void:
	_entries[_current_idx]["y_offset"] = value
	_y_value.text = "%.2f" % value
	_apply_y_offset(_current_idx)


# ── Live update ──────────────────────────────────────────────

func _apply_scale(idx: int) -> void:
	var entry := _entries[idx]
	var s: float = entry["scale"]

	match entry["type"]:
		"tile":
			var gv := _get_grid_visual()
			if gv:
				gv.update_tile_scale(Vector3(s, s, s))
		"hero":
			var hero := _get_hero()
			if hero:
				hero.update_model_scale(s)
		"enemy":
			entry["data"].model_scale = s
			for e in get_tree().get_nodes_in_group(&"enemies"):
				if is_instance_valid(e) and e.data and e.data.id == entry["id"]:
					e.update_model_scale(s)
		"building":
			var sv := Vector3(s, s, s)
			entry["data"].model_scale = sv
			var bnode := get_tree().current_scene.get_node_or_null("Buildings")
			if bnode:
				for b in bnode.get_children():
					if is_instance_valid(b) and b.has_method("update_model_scale") and b.data and b.data.id == entry["id"]:
						b.update_model_scale(sv)


func _apply_y_offset(idx: int) -> void:
	var entry := _entries[idx]
	var y: float = entry["y_offset"]

	match entry["type"]:
		"hero":
			var hero := _get_hero()
			if hero:
				hero.update_model_y_offset(y)
		"enemy":
			entry["data"].model_y_offset = y
			for e in get_tree().get_nodes_in_group(&"enemies"):
				if is_instance_valid(e) and e.data and e.data.id == entry["id"]:
					e.update_model_y_offset(y)
		"building":
			entry["data"].model_y_offset = y
			var bnode := get_tree().current_scene.get_node_or_null("Buildings")
			if bnode:
				for b in bnode.get_children():
					if is_instance_valid(b) and b.has_method("update_model_y_offset") and b.data and b.data.id == entry["id"]:
						b.update_model_y_offset(y)


func _apply_all() -> void:
	for i in range(_entries.size()):
		_apply_scale(i)
		if _entries[i]["has_y"]:
			_apply_y_offset(i)


# ── Day/Night preview ───────────────────────────────────────

func _toggle_day_night() -> void:
	_preview_is_day = not _preview_is_day
	var dnv := _get_day_night_visual()
	if dnv:
		if _preview_is_day:
			dnv.set_preview_day()
		else:
			dnv.set_preview_night()
	_day_night_btn.text = "Switch to Night" if _preview_is_day else "Switch to Day"


func _on_game_phase_changed(phase: StringName) -> void:
	_preview_is_day = (phase == &"day")
	_day_night_btn.text = "Switch to Night" if _preview_is_day else "Switch to Day"


# ── Save / Reset ─────────────────────────────────────────────

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute("res://config")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)

	for i in range(_entries.size()):
		var entry := _entries[i]
		match entry["type"]:
			"tile":
				cfg.set_value("tile", "scale", entry["scale"])
			"hero":
				cfg.set_value("hero", "scale", entry["scale"])
				cfg.set_value("hero", "y_offset", entry["y_offset"])
			"enemy":
				var data: Resource = entry["data"]
				data.model_scale = entry["scale"]
				data.model_y_offset = entry["y_offset"]
				ResourceSaver.save(data)
			"building":
				var data: Resource = entry["data"]
				var s: float = entry["scale"]
				data.model_scale = Vector3(s, s, s)
				data.model_y_offset = entry["y_offset"]
				ResourceSaver.save(data)

	cfg.save(CONFIG_PATH)
	_snapshot_originals()


func _on_reset() -> void:
	for i in range(_entries.size()):
		var orig: Dictionary = _originals[i]
		_entries[i]["scale"] = orig["scale"]
		_entries[i]["y_offset"] = orig["y_offset"]

		var entry: Dictionary = _entries[i]
		if entry["type"] == "enemy":
			entry["data"].model_scale = orig["scale"]
			entry["data"].model_y_offset = orig["y_offset"]
		elif entry["type"] == "building":
			var s: float = orig["scale"]
			entry["data"].model_scale = Vector3(s, s, s)
			entry["data"].model_y_offset = orig["y_offset"]

	_apply_all()
	_select_entry(_current_idx)


# ── Node references ──────────────────────────────────────────

func _get_hero() -> Node3D:
	return get_tree().get_first_node_in_group(&"hero")


func _get_grid_visual() -> GridVisual:
	var scene := get_tree().current_scene
	if scene:
		return scene.get_node_or_null("GridVisual") as GridVisual
	return null


func _get_day_night_visual() -> DayNightVisual:
	var scene := get_tree().current_scene
	if scene:
		return scene.get_node_or_null("DayNightVisual") as DayNightVisual
	return null
