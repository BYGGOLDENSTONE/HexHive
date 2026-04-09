extends CanvasLayer
## In-game Sprite Placement Editor overlay.
## Toggle with the wrench button (top-right). Adjust building sprite scale,
## offset, and preview day/night lighting — changes apply live to placed
## buildings. Press SAVE to persist values to disk.

const HEX_SIZE := 48.0
const HEX_WIDTH := 1.7320508 * 48.0  # sqrt(3) * HEX_SIZE

const NIGHT_COLOR := Color(0.45, 0.50, 0.75, 1.0)
const DAY_COLOR := Color(1.0, 0.98, 0.92, 1.0)

## Loaded building resources.
var _buildings: Array[Resource] = []
var _current_idx: int = -1

## Editable values.
var _spr_scale := Vector2(1.0, 1.0)
var _spr_offset := Vector2(0.0, 0.0)

## Day/night preview state.
var _previewing_day := false
var _saved_color: Color

## UI refs.
var _root: Control
var _panel: PanelContainer
var _toggle_btn: Button
var _selector: OptionButton
var _sx_slider: HSlider
var _sy_slider: HSlider
var _ox_slider: HSlider
var _oy_slider: HSlider
var _sx_label: Label
var _sy_label: Label
var _ox_label: Label
var _oy_label: Label
var _info_label: Label
var _sprite_path_label: Label
var _day_night_btn: Button


func _ready() -> void:
	layer = 15
	_load_buildings()
	_build_ui()
	_panel.visible = false


# -- Data ----------------------------------------------------------------------

func _load_buildings() -> void:
	var all: Array = BuildingRegistry.get_all()
	for bd in all:
		_buildings.append(bd)
	_buildings.sort_custom(func(a: Resource, b: Resource) -> bool: return a.display_name < b.display_name)


# -- Toggle --------------------------------------------------------------------

func _toggle_editor() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_toggle_btn.text = "X"
		# Save current visual state for restore.
		var dnv := _get_day_night_visual()
		if dnv:
			_saved_color = dnv.color
		_previewing_day = DayNightManager.is_day()
		_update_day_night_btn_text()
		_select_first_with_sprite()
	else:
		_toggle_btn.text = "EDIT"
		_restore_day_night()


func _select_first_with_sprite() -> void:
	for i in range(_buildings.size()):
		if _buildings[i].sprite_path != "":
			_selector.select(i)
			_on_building_selected(i)
			return
	if _buildings.size() > 0:
		_selector.select(0)
		_on_building_selected(0)


# -- Building selection --------------------------------------------------------

func _on_building_selected(idx: int) -> void:
	if idx < 0 or idx >= _buildings.size():
		return
	_current_idx = idx
	var bd: Resource = _buildings[idx]

	_spr_scale = bd.sprite_scale
	_spr_offset = bd.sprite_offset

	# Block signals during bulk slider update.
	_sx_slider.value_changed.disconnect(_on_scale_x_changed)
	_sy_slider.value_changed.disconnect(_on_scale_y_changed)
	_ox_slider.value_changed.disconnect(_on_offset_x_changed)
	_oy_slider.value_changed.disconnect(_on_offset_y_changed)

	_sx_slider.value = _spr_scale.x
	_sy_slider.value = _spr_scale.y
	_ox_slider.value = _spr_offset.x
	_oy_slider.value = _spr_offset.y

	_sx_slider.value_changed.connect(_on_scale_x_changed)
	_sy_slider.value_changed.connect(_on_scale_y_changed)
	_ox_slider.value_changed.connect(_on_offset_x_changed)
	_oy_slider.value_changed.connect(_on_offset_y_changed)

	_sprite_path_label.text = bd.sprite_path if bd.sprite_path != "" else "(no sprite)"
	_update_value_labels()
	_info_label.text = ""


# -- Sliders -------------------------------------------------------------------

func _on_scale_x_changed(val: float) -> void:
	_spr_scale.x = val
	_apply_live()

func _on_scale_y_changed(val: float) -> void:
	_spr_scale.y = val
	_apply_live()

func _on_offset_x_changed(val: float) -> void:
	_spr_offset.x = val
	_apply_live()

func _on_offset_y_changed(val: float) -> void:
	_spr_offset.y = val
	_apply_live()


func _apply_live() -> void:
	_update_value_labels()
	if _current_idx < 0:
		return
	var bd: Resource = _buildings[_current_idx]
	bd.sprite_scale = _spr_scale
	bd.sprite_offset = _spr_offset
	_refresh_placed_buildings(bd.id)


func _update_value_labels() -> void:
	_sx_label.text = "%.2f" % _spr_scale.x
	_sy_label.text = "%.2f" % _spr_scale.y
	_ox_label.text = "%.0f px" % _spr_offset.x
	_oy_label.text = "%.0f px" % _spr_offset.y


func _refresh_placed_buildings(building_id: StringName) -> void:
	var container: Node2D = get_tree().current_scene.get_node_or_null("Buildings") as Node2D
	if container == null:
		return
	for child in container.get_children():
		if child is Building and child.data != null and child.data.id == building_id:
			child.refresh_sprite()


# -- Day/Night preview ---------------------------------------------------------

func _toggle_day_night() -> void:
	_previewing_day = not _previewing_day
	var dnv := _get_day_night_visual()
	if dnv:
		var target: Color = DAY_COLOR if _previewing_day else NIGHT_COLOR
		dnv.color = target
	_update_day_night_btn_text()


func _update_day_night_btn_text() -> void:
	if _day_night_btn == null:
		return
	_day_night_btn.text = "NIGHT" if _previewing_day else "DAY"


func _get_day_night_visual() -> CanvasModulate:
	return get_tree().current_scene.get_node_or_null("DayNightVisual") as CanvasModulate


func _restore_day_night() -> void:
	var dnv := _get_day_night_visual()
	if dnv == null:
		return
	# Restore to match current game phase.
	var target: Color = DAY_COLOR if DayNightManager.is_day() else NIGHT_COLOR
	dnv.color = target


# -- Save / Reset --------------------------------------------------------------

func _on_save() -> void:
	if _current_idx < 0 or _current_idx >= _buildings.size():
		return
	var bd: Resource = _buildings[_current_idx]
	bd.sprite_scale = _spr_scale
	bd.sprite_offset = _spr_offset
	var path: String = bd.resource_path
	var err := ResourceSaver.save(bd, path)
	if err == OK:
		_info_label.text = "Saved!"
		_info_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.45))
	else:
		_info_label.text = "Save FAILED (err %d)" % err
		_info_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))


func _on_reset() -> void:
	if _current_idx < 0:
		return
	# Reload from disk.
	var bd: Resource = _buildings[_current_idx]
	var path: String = bd.resource_path
	var fresh: Resource = load(path)
	if fresh == null:
		return
	bd.sprite_scale = fresh.sprite_scale
	bd.sprite_offset = fresh.sprite_offset
	_on_building_selected(_current_idx)
	_refresh_placed_buildings(bd.id)
	_info_label.text = "Reset to saved values."
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


# -- UI construction -----------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Toggle button — top-right corner.
	_toggle_btn = Button.new()
	_toggle_btn.text = "EDIT"
	_toggle_btn.anchor_left = 1.0
	_toggle_btn.anchor_right = 1.0
	_toggle_btn.anchor_top = 0.0
	_toggle_btn.offset_left = -70.0
	_toggle_btn.offset_right = -12.0
	_toggle_btn.offset_top = 12.0
	_toggle_btn.offset_bottom = 42.0
	_toggle_btn.pressed.connect(_toggle_editor)
	_style_button(_toggle_btn, Color(0.55, 0.42, 0.18))
	_root.add_child(_toggle_btn)

	# Right-side editor panel.
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -310.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.border_width_left = 2
	style.border_color = Color(0.85, 0.70, 0.30, 0.55)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "SPRITE EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.90, 0.75, 0.30))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Building selector.
	var sel_lbl := Label.new()
	sel_lbl.text = "Building"
	sel_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(sel_lbl)

	_selector = OptionButton.new()
	for bd in _buildings:
		var suffix: String = "  *" if bd.sprite_path != "" else ""
		_selector.add_item(bd.display_name + suffix)
	_selector.item_selected.connect(_on_building_selected)
	vbox.add_child(_selector)

	_sprite_path_label = Label.new()
	_sprite_path_label.text = ""
	_sprite_path_label.add_theme_font_size_override("font_size", 11)
	_sprite_path_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_sprite_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sprite_path_label)

	vbox.add_child(HSeparator.new())

	# Scale X.
	var sx_row := _make_slider_row("Scale X", 0.1, 10.0, 0.05, 1.0)
	_sx_slider = sx_row[0]
	_sx_label = sx_row[1]
	_sx_slider.value_changed.connect(_on_scale_x_changed)
	vbox.add_child(sx_row[2])

	# Scale Y.
	var sy_row := _make_slider_row("Scale Y", 0.1, 10.0, 0.05, 1.0)
	_sy_slider = sy_row[0]
	_sy_label = sy_row[1]
	_sy_slider.value_changed.connect(_on_scale_y_changed)
	vbox.add_child(sy_row[2])

	vbox.add_child(HSeparator.new())

	# Offset X.
	var ox_row := _make_slider_row("Offset X", -200.0, 200.0, 1.0, 0.0)
	_ox_slider = ox_row[0]
	_ox_label = ox_row[1]
	_ox_slider.value_changed.connect(_on_offset_x_changed)
	vbox.add_child(ox_row[2])

	# Offset Y.
	var oy_row := _make_slider_row("Offset Y", -200.0, 200.0, 1.0, 0.0)
	_oy_slider = oy_row[0]
	_oy_label = oy_row[1]
	_oy_slider.value_changed.connect(_on_offset_y_changed)
	vbox.add_child(oy_row[2])

	vbox.add_child(HSeparator.new())

	# Day/Night toggle.
	_day_night_btn = Button.new()
	_day_night_btn.text = "DAY"
	_day_night_btn.pressed.connect(_toggle_day_night)
	_style_button(_day_night_btn, Color(0.25, 0.30, 0.50))
	vbox.add_child(_day_night_btn)

	vbox.add_child(HSeparator.new())

	# Buttons row.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "  SAVE  "
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save)
	_style_button(save_btn, Color(0.22, 0.50, 0.28))
	btn_row.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "  RESET  "
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset)
	_style_button(reset_btn, Color(0.45, 0.32, 0.22))
	btn_row.add_child(reset_btn)

	# Info label.
	_info_label = Label.new()
	_info_label.text = ""
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_label)


func _style_button(btn: Button, bg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	btn.add_theme_stylebox_override("normal", s)
	var s_hover := s.duplicate() as StyleBoxFlat
	s_hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", s_hover)
	var s_pressed := s.duplicate() as StyleBoxFlat
	s_pressed.bg_color = bg.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", s_pressed)


func _make_slider_row(title: String, min_val: float, max_val: float, step_val: float, default_val: float) -> Array:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	header.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % default_val if step_val < 1.0 else "%.0f" % default_val
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.custom_minimum_size = Vector2(65, 0)
	val_lbl.add_theme_color_override("font_color", Color(0.90, 0.75, 0.30))
	header.add_child(val_lbl)

	container.add_child(header)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = default_val
	container.add_child(slider)

	return [slider, val_lbl, container]
