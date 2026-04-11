extends CanvasLayer
## Map editor UI. Works both standalone (map_editor_scene) and in-game (F6 toggle).
## Paint terrain types, set elevation, place ramps, save/load maps.

## Set to true when used as standalone scene (always visible, no toggle).
@export var standalone_mode: bool = false

var hex_grid: HexGrid
var grid_visual: GridVisual

var _panel: PanelContainer
var _visible: bool = false
var _active: bool = false

## Current brush settings.
var _brush_terrain: HexTile.TerrainType = HexTile.TerrainType.GRASS
var _brush_elevation: int = 0
var _brush_ramp: bool = false
var _brush_ramp_dir: int = 0
var _brush_size: int = 0  # 0 = single tile, 1 = radius 1 (7 tiles), etc.
var _is_painting: bool = false

## Terrain button references for highlight.
var _terrain_buttons: Dictionary = {}  # TerrainType -> Button
var _elevation_label: Label
var _ramp_check: CheckBox
var _ramp_dir_label: Label
var _brush_label: Label
var _status_label: Label


func _ready() -> void:
	layer = 18
	# Find grid references.
	hex_grid = get_tree().current_scene.find_child("HexGrid", true, false) as HexGrid
	grid_visual = get_tree().current_scene.find_child("GridVisual", true, false) as GridVisual
	_build_ui()
	if standalone_mode:
		_panel.visible = true
		_active = true
		_visible = true
	else:
		_panel.visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(260, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -270
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.92)
	style.border_color = Color(0.9, 0.75, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "MAP EDITOR (F6)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# Terrain section.
	var terrain_label := Label.new()
	terrain_label.text = "TERRAIN"
	terrain_label.add_theme_font_size_override("font_size", 14)
	terrain_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(terrain_label)

	var terrain_grid := GridContainer.new()
	terrain_grid.columns = 2
	vbox.add_child(terrain_grid)

	var terrain_info: Array[Dictionary] = [
		{"type": HexTile.TerrainType.GRASS, "name": "Grass", "color": Color(0.4, 0.7, 0.3)},
		{"type": HexTile.TerrainType.MOUNTAIN, "name": "Mountain", "color": Color(0.55, 0.5, 0.45)},
		{"type": HexTile.TerrainType.FOREST, "name": "Forest", "color": Color(0.25, 0.5, 0.2)},
		{"type": HexTile.TerrainType.FLOWER, "name": "Flower", "color": Color(0.95, 0.8, 0.3)},
		{"type": HexTile.TerrainType.WATER, "name": "Water", "color": Color(0.3, 0.5, 0.8)},
		{"type": HexTile.TerrainType.HIVE, "name": "Hive", "color": Color(0.9, 0.75, 0.3)},
	]

	for info: Dictionary in terrain_info:
		var btn := Button.new()
		btn.text = info["name"] as String
		btn.custom_minimum_size = Vector2(115, 36)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = (info["color"] as Color) * 0.6
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover := StyleBoxFlat.new()
		btn_hover.bg_color = (info["color"] as Color) * 0.8
		btn_hover.set_corner_radius_all(4)
		btn_hover.set_content_margin_all(4)
		btn.add_theme_stylebox_override("hover", btn_hover)
		var btn_pressed := StyleBoxFlat.new()
		btn_pressed.bg_color = info["color"] as Color
		btn_pressed.border_color = Color.WHITE
		btn_pressed.set_border_width_all(2)
		btn_pressed.set_corner_radius_all(4)
		btn_pressed.set_content_margin_all(4)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.toggle_mode = true
		btn.button_group = _get_terrain_button_group()
		var terrain_type: int = info["type"] as int
		btn.pressed.connect(_on_terrain_selected.bind(terrain_type))
		terrain_grid.add_child(btn)
		_terrain_buttons[terrain_type] = btn

	# Select default.
	if _terrain_buttons.has(int(_brush_terrain)):
		(_terrain_buttons[int(_brush_terrain)] as Button).button_pressed = true

	vbox.add_child(_make_separator())

	# Elevation section.
	var elev_title := Label.new()
	elev_title.text = "ELEVATION"
	elev_title.add_theme_font_size_override("font_size", 14)
	elev_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(elev_title)

	var elev_hbox := HBoxContainer.new()
	vbox.add_child(elev_hbox)

	var elev_minus := Button.new()
	elev_minus.text = " - "
	elev_minus.custom_minimum_size = Vector2(40, 32)
	elev_minus.pressed.connect(_on_elevation_change.bind(-1))
	elev_hbox.add_child(elev_minus)

	_elevation_label = Label.new()
	_elevation_label.text = "Level: 0"
	_elevation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elevation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_elevation_label.add_theme_font_size_override("font_size", 16)
	elev_hbox.add_child(_elevation_label)

	var elev_plus := Button.new()
	elev_plus.text = " + "
	elev_plus.custom_minimum_size = Vector2(40, 32)
	elev_plus.pressed.connect(_on_elevation_change.bind(1))
	elev_hbox.add_child(elev_plus)

	vbox.add_child(_make_separator())

	# Ramp section.
	var ramp_hbox := HBoxContainer.new()
	vbox.add_child(ramp_hbox)

	_ramp_check = CheckBox.new()
	_ramp_check.text = "Ramp"
	_ramp_check.toggled.connect(_on_ramp_toggled)
	ramp_hbox.add_child(_ramp_check)

	ramp_hbox.add_child(HSeparator.new())

	var ramp_dir_minus := Button.new()
	ramp_dir_minus.text = "<"
	ramp_dir_minus.custom_minimum_size = Vector2(30, 28)
	ramp_dir_minus.pressed.connect(_on_ramp_dir_change.bind(-1))
	ramp_hbox.add_child(ramp_dir_minus)

	_ramp_dir_label = Label.new()
	_ramp_dir_label.text = "Dir: 0"
	_ramp_dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ramp_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ramp_hbox.add_child(_ramp_dir_label)

	var ramp_dir_plus := Button.new()
	ramp_dir_plus.text = ">"
	ramp_dir_plus.custom_minimum_size = Vector2(30, 28)
	ramp_dir_plus.pressed.connect(_on_ramp_dir_change.bind(1))
	ramp_hbox.add_child(ramp_dir_plus)

	vbox.add_child(_make_separator())

	# Brush size section.
	var brush_title := Label.new()
	brush_title.text = "BRUSH SIZE"
	brush_title.add_theme_font_size_override("font_size", 14)
	brush_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(brush_title)

	var brush_hbox := HBoxContainer.new()
	vbox.add_child(brush_hbox)

	var brush_minus := Button.new()
	brush_minus.text = " - "
	brush_minus.custom_minimum_size = Vector2(40, 32)
	brush_minus.pressed.connect(_on_brush_size_change.bind(-1))
	brush_hbox.add_child(brush_minus)

	_brush_label = Label.new()
	_brush_label.text = "1 tile"
	_brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brush_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brush_label.add_theme_font_size_override("font_size", 16)
	brush_hbox.add_child(_brush_label)

	var brush_plus := Button.new()
	brush_plus.text = " + "
	brush_plus.custom_minimum_size = Vector2(40, 32)
	brush_plus.pressed.connect(_on_brush_size_change.bind(1))
	brush_hbox.add_child(brush_plus)

	vbox.add_child(_make_separator())

	# Action buttons.
	var actions_title := Label.new()
	actions_title.text = "ACTIONS"
	actions_title.add_theme_font_size_override("font_size", 14)
	actions_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(actions_title)

	var save_btn := Button.new()
	save_btn.text = "SAVE MAP"
	save_btn.custom_minimum_size = Vector2(0, 36)
	save_btn.pressed.connect(_on_save)
	vbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "LOAD MAP"
	load_btn.custom_minimum_size = Vector2(0, 36)
	load_btn.pressed.connect(_on_load)
	vbox.add_child(load_btn)

	var reset_btn := Button.new()
	reset_btn.text = "RESET (Procedural)"
	reset_btn.custom_minimum_size = Vector2(0, 36)
	reset_btn.pressed.connect(_on_reset)
	vbox.add_child(reset_btn)

	var clear_btn := Button.new()
	clear_btn.text = "CLEAR ALL (Grass)"
	clear_btn.custom_minimum_size = Vector2(0, 36)
	clear_btn.pressed.connect(_on_clear)
	vbox.add_child(clear_btn)

	vbox.add_child(_make_separator())

	# Status.
	_status_label = Label.new()
	_status_label.text = "Click tiles to paint"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	# Tile info (under cursor).
	var info_label := Label.new()
	info_label.text = "Right-click: sample tile"
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(info_label)

	# Back to Menu button (standalone mode only).
	if standalone_mode:
		vbox.add_child(_make_separator())
		var back_btn := Button.new()
		back_btn.text = "BACK TO MENU"
		back_btn.custom_minimum_size = Vector2(0, 36)
		back_btn.pressed.connect(_on_back_to_menu)
		vbox.add_child(back_btn)

	add_child(_panel)


var _terrain_btn_group: ButtonGroup = null

func _get_terrain_button_group() -> ButtonGroup:
	if _terrain_btn_group == null:
		_terrain_btn_group = ButtonGroup.new()
	return _terrain_btn_group


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


# -- Callbacks --

func _on_terrain_selected(terrain_type: int) -> void:
	_brush_terrain = terrain_type as HexTile.TerrainType
	_update_status()


func _on_elevation_change(delta: int) -> void:
	_brush_elevation = clampi(_brush_elevation + delta, 0, 3)
	_elevation_label.text = "Level: %d" % _brush_elevation
	_update_status()


func _on_ramp_toggled(pressed: bool) -> void:
	_brush_ramp = pressed
	_update_status()


func _on_ramp_dir_change(delta: int) -> void:
	_brush_ramp_dir = (_brush_ramp_dir + delta) % 6
	if _brush_ramp_dir < 0:
		_brush_ramp_dir += 6
	_ramp_dir_label.text = "Dir: %d" % _brush_ramp_dir
	_update_status()


func _on_brush_size_change(delta: int) -> void:
	_brush_size = clampi(_brush_size + delta, 0, 5)
	if _brush_size == 0:
		_brush_label.text = "1 tile"
	else:
		_brush_label.text = "Radius %d" % _brush_size
	_update_status()


func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_save() -> void:
	if hex_grid.save_map_to_file():
		_status_label.text = "Map saved!"
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_status_label.text = "Save failed!"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _on_load() -> void:
	# Reset tiles first, then load.
	for tile: HexTile in hex_grid.tiles.values():
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
	if hex_grid._load_map_from_file():
		grid_visual.rebuild_all_tiles()
		_status_label.text = "Map loaded!"
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_status_label.text = "No saved map found"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))


func _on_reset() -> void:
	hex_grid.reset_to_procedural()
	grid_visual.rebuild_all_tiles()
	_status_label.text = "Reset to procedural"
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))


func _on_clear() -> void:
	for tile: HexTile in hex_grid.tiles.values():
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
	grid_visual.rebuild_all_tiles()
	_status_label.text = "All tiles cleared to grass"
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _update_status() -> void:
	var terrain_names: Dictionary = {
		HexTile.TerrainType.GRASS: "Grass",
		HexTile.TerrainType.MOUNTAIN: "Mountain",
		HexTile.TerrainType.FOREST: "Forest",
		HexTile.TerrainType.FLOWER: "Flower",
		HexTile.TerrainType.WATER: "Water",
		HexTile.TerrainType.HIVE: "Hive",
	}
	var terrain_name: String = terrain_names.get(int(_brush_terrain), "Unknown") as String
	var text: String = "Brush: %s | Elev: %d" % [terrain_name, _brush_elevation]
	if _brush_ramp:
		text += " | Ramp dir: %d" % _brush_ramp_dir
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


# -- Toggle & Input --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_F6:
			_toggle()
			get_viewport().set_input_as_handled()
			return

	if not _active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_painting = true
				_paint_at_mouse()
			else:
				_is_painting = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_sample_at_mouse()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _is_painting:
		_paint_at_mouse()


func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	_active = _visible
	if _active:
		_update_status()


func _paint_at_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		return
	var center_coord: Vector2i = hex_grid.world_to_hex(world_pos)
	var coords_to_paint: Array[Vector2i]
	if _brush_size == 0:
		coords_to_paint = [center_coord]
	else:
		coords_to_paint = HexHelper.get_hexes_in_range(center_coord, _brush_size)

	for coord: Vector2i in coords_to_paint:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		tile.terrain = _brush_terrain
		tile.elevation = _brush_elevation
		tile.is_ramp = _brush_ramp
		tile.ramp_exit_dir = _brush_ramp_dir if _brush_ramp else -1
		grid_visual.rebuild_tile(coord)


func _sample_at_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		return
	var coord: Vector2i = hex_grid.world_to_hex(world_pos)
	var tile: HexTile = hex_grid.get_tile(coord)
	if tile == null:
		return
	_brush_terrain = tile.terrain
	_brush_elevation = tile.elevation
	_brush_ramp = tile.is_ramp
	_brush_ramp_dir = tile.ramp_exit_dir if tile.is_ramp else 0

	# Update UI.
	_elevation_label.text = "Level: %d" % _brush_elevation
	_ramp_check.button_pressed = _brush_ramp
	_ramp_dir_label.text = "Dir: %d" % _brush_ramp_dir
	if _terrain_buttons.has(int(_brush_terrain)):
		(_terrain_buttons[int(_brush_terrain)] as Button).button_pressed = true
	_update_status()
	_status_label.text = "Sampled: (%d,%d)" % [coord.x, coord.y]
