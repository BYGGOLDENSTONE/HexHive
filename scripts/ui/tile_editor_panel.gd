extends CanvasLayer
## In-game Tile Visual Editor overlay.
## Toggle with the TILE button (top-right, below EDIT). Adjust elevation
## colors, cliff depth, and preview day/night — changes apply live.
## Press SAVE to write values to a config file, RESET to reload.

const CONFIG_PATH := "res://resources/tile_visual.cfg"
const NIGHT_COLOR := Color(0.45, 0.50, 0.75, 1.0)
const DAY_COLOR := Color(1.0, 0.98, 0.92, 1.0)

## Property definitions: [property_name, display_label, type]
## type: "float" for slider, "color" for ColorPickerButton
const PROPS: Array = [
	["cliff_depth",          "Cliff Depth",     "float", 0.05, 0.60, 0.01],
	["high_ground_fill",     "High Ground",     "color"],
	["low_ground_fill",      "Low Ground",      "color"],
	["cliff_lit_color",      "Cliff Lit (E/SE)","color"],
	["cliff_shadow_color",   "Cliff Shadow (SW)","color"],
	["cliff_back_color",     "Cliff Back (W/NW/NE)","color"],
	["cliff_edge_highlight", "Edge Highlight",  "color"],
	["ramp_fill_color",      "Ramp Fill",       "color"],
	["high_outline_color",   "High Outline",    "color"],
	["outline_color",        "Low Outline",     "color"],
]

var _grid_visual: Node2D = null
var _previewing_day := false
var _saved_color: Color

## UI refs
var _root: Control
var _panel: PanelContainer
var _toggle_btn: Button
var _day_night_btn: Button
var _info_label: Label

## Maps property name → control (HSlider or ColorPickerButton)
var _controls: Dictionary = {}
## Maps property name → value label (for sliders)
var _value_labels: Dictionary = {}


func _ready() -> void:
	layer = 15
	_build_ui()
	_panel.visible = false


func _find_grid_visual() -> void:
	_grid_visual = get_tree().current_scene.get_node_or_null("GridVisual")


# -- Toggle ----------------------------------------------------------------

func _toggle_editor() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_toggle_btn.text = "X"
		_find_grid_visual()
		_load_current_values()
		var dnv := _get_day_night_visual()
		if dnv:
			_saved_color = dnv.color
		_previewing_day = DayNightManager.is_day()
		_update_day_night_btn_text()
	else:
		_toggle_btn.text = "TILE"
		_restore_day_night()


func _load_current_values() -> void:
	if _grid_visual == null:
		return
	for prop_def in PROPS:
		var prop_name: String = prop_def[0]
		var prop_type: String = prop_def[2]
		var value: Variant = _grid_visual.get(prop_name)
		if value == null:
			continue
		var ctrl: Control = _controls.get(prop_name)
		if ctrl == null:
			continue
		if prop_type == "float":
			(ctrl as HSlider).set_value_no_signal(value as float)
			var lbl: Label = _value_labels.get(prop_name)
			if lbl:
				lbl.text = "%.2f" % (value as float)
		elif prop_type == "color":
			(ctrl as ColorPickerButton).color = value as Color


# -- Live apply ------------------------------------------------------------

func _on_float_changed(value: float, prop_name: String) -> void:
	if _grid_visual:
		_grid_visual.set(prop_name, value)
	var lbl: Label = _value_labels.get(prop_name)
	if lbl:
		lbl.text = "%.2f" % value


func _on_color_changed(color: Color, prop_name: String) -> void:
	if _grid_visual:
		_grid_visual.set(prop_name, color)


# -- Day/Night preview -----------------------------------------------------

func _toggle_day_night() -> void:
	_previewing_day = not _previewing_day
	var dnv := _get_day_night_visual()
	if dnv:
		dnv.color = DAY_COLOR if _previewing_day else NIGHT_COLOR
	_update_day_night_btn_text()


func _update_day_night_btn_text() -> void:
	if _day_night_btn:
		_day_night_btn.text = "NIGHT" if _previewing_day else "DAY"


func _get_day_night_visual() -> CanvasModulate:
	return get_tree().current_scene.get_node_or_null("DayNightVisual") as CanvasModulate


func _restore_day_night() -> void:
	var dnv := _get_day_night_visual()
	if dnv:
		dnv.color = DAY_COLOR if DayNightManager.is_day() else NIGHT_COLOR


# -- Save / Reset ----------------------------------------------------------

func _on_save() -> void:
	if _grid_visual == null:
		return
	var cfg := ConfigFile.new()
	for prop_def in PROPS:
		var prop_name: String = prop_def[0]
		var prop_type: String = prop_def[2]
		var value: Variant = _grid_visual.get(prop_name)
		if prop_type == "float":
			cfg.set_value("tile_visual", prop_name, value as float)
		elif prop_type == "color":
			var c: Color = value as Color
			cfg.set_value("tile_visual", prop_name, c)
	var err := cfg.save(CONFIG_PATH)
	if err == OK:
		_info_label.text = "Saved!"
		_info_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.45))
	else:
		_info_label.text = "Save FAILED (err %d)" % err
		_info_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))


func _on_reset() -> void:
	if _grid_visual == null:
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		_info_label.text = "No saved config found."
		_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		return
	for prop_def in PROPS:
		var prop_name: String = prop_def[0]
		var prop_type: String = prop_def[2]
		if not cfg.has_section_key("tile_visual", prop_name):
			continue
		var value: Variant = cfg.get_value("tile_visual", prop_name)
		_grid_visual.set(prop_name, value)
		var ctrl: Control = _controls.get(prop_name)
		if ctrl == null:
			continue
		if prop_type == "float":
			(ctrl as HSlider).set_value_no_signal(value as float)
			var lbl: Label = _value_labels.get(prop_name)
			if lbl:
				lbl.text = "%.2f" % (value as float)
		elif prop_type == "color":
			(ctrl as ColorPickerButton).color = value as Color
	_info_label.text = "Reset to saved."
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


## Load saved config at startup and apply to GridVisual.
func load_config_if_exists() -> void:
	_find_grid_visual()
	if _grid_visual == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for prop_def in PROPS:
		var prop_name: String = prop_def[0]
		if cfg.has_section_key("tile_visual", prop_name):
			_grid_visual.set(prop_name, cfg.get_value("tile_visual", prop_name))


# -- UI construction -------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Toggle button — top-right corner, below sprite EDIT.
	_toggle_btn = Button.new()
	_toggle_btn.text = "TILE"
	_toggle_btn.anchor_left = 1.0
	_toggle_btn.anchor_right = 1.0
	_toggle_btn.anchor_top = 0.0
	_toggle_btn.offset_left = -70.0
	_toggle_btn.offset_right = -12.0
	_toggle_btn.offset_top = 50.0
	_toggle_btn.offset_bottom = 80.0
	_toggle_btn.pressed.connect(_toggle_editor)
	_style_button(_toggle_btn, Color(0.18, 0.42, 0.55))
	_root.add_child(_toggle_btn)

	# Left-side editor panel (opposite side from sprite editor).
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 310.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.10, 0.95)
	style.border_width_right = 2
	style.border_color = Color(0.30, 0.65, 0.85, 0.55)
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
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "TILE EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.30, 0.75, 0.90))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Build controls from PROPS
	for prop_def in PROPS:
		var prop_name: String = prop_def[0]
		var display_label: String = prop_def[1]
		var prop_type: String = prop_def[2]

		if prop_type == "float":
			var min_v: float = prop_def[3]
			var max_v: float = prop_def[4]
			var step_v: float = prop_def[5]
			var row := _make_slider_row(display_label, min_v, max_v, step_v)
			var slider: HSlider = row[0]
			var val_lbl: Label = row[1]
			slider.value_changed.connect(_on_float_changed.bind(prop_name))
			_controls[prop_name] = slider
			_value_labels[prop_name] = val_lbl
			vbox.add_child(row[2])

		elif prop_type == "color":
			var row := _make_color_row(display_label)
			var picker: ColorPickerButton = row[0]
			picker.color_changed.connect(_on_color_changed.bind(prop_name))
			_controls[prop_name] = picker
			vbox.add_child(row[1])

	vbox.add_child(HSeparator.new())

	# Day/Night toggle
	_day_night_btn = Button.new()
	_day_night_btn.text = "DAY"
	_day_night_btn.pressed.connect(_toggle_day_night)
	_style_button(_day_night_btn, Color(0.25, 0.30, 0.50))
	vbox.add_child(_day_night_btn)

	vbox.add_child(HSeparator.new())

	# Save/Reset buttons
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

	# Info label
	_info_label = Label.new()
	_info_label.text = ""
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_label)


func _make_slider_row(title: String, min_val: float, max_val: float, step_val: float) -> Array:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	header.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % min_val
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.custom_minimum_size = Vector2(60, 0)
	val_lbl.add_theme_color_override("font_color", Color(0.30, 0.75, 0.90))
	header.add_child(val_lbl)

	container.add_child(header)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = min_val
	container.add_child(slider)

	return [slider, val_lbl, container]


func _make_color_row(title: String) -> Array:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	container.add_child(name_lbl)

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(50, 28)
	picker.edit_alpha = true
	container.add_child(picker)

	return [picker, container]


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
