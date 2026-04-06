class_name UpgradePopup
extends CanvasLayer
## Manages upgrade popups for buildings near the hero.
## Popups are placed on the opposite side of the building from the hero.
## Lines connect each popup to its building.

## Active popups: Dictionary[Vector2i, PanelContainer]
var _popups: Dictionary = {}

## Building references: Dictionary[Vector2i, Node2D]
var _buildings: Dictionary = {}

## Frozen direction per popup (unit vector, calculated once on creation): Dictionary[Vector2i, Vector2]
var _directions: Dictionary = {}

## Line drawer control (draws connector lines on the CanvasLayer)
var _line_drawer: Control

## Hero reference for directional placement
var _hero: Node2D

## Hex grid reference for size calculations
var _hex_grid: Node2D

## Extra margin in screen pixels beyond the building hex
const POPUP_MARGIN: float = 15.0

## Minimum zoom level to show popups (below this, popups are hidden)
const MIN_ZOOM_FOR_POPUPS: float = 0.7


func _ready() -> void:
	layer = 11
	SignalBus.hero_near_building.connect(_on_hero_near_building)
	SignalBus.hero_left_building.connect(_on_hero_left_building)
	SignalBus.building_upgraded.connect(_on_building_upgraded)
	SignalBus.phase_changed.connect(_on_phase_changed)

	# Line drawer sits behind popups
	_line_drawer = Control.new()
	_line_drawer.name = "LineDrawer"
	_line_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_line_drawer)
	_line_drawer.draw.connect(_on_line_draw)

	_hero = %Hero
	_hex_grid = %HexGrid


func _process(_delta: float) -> void:
	if _popups.is_empty():
		return

	var canvas_transform := get_viewport().get_canvas_transform()
	var cam_scale: float = canvas_transform.x.x
	if cam_scale < 0.01:
		cam_scale = 1.0

	# Hide all popups and lines when zoomed out too far
	var too_far := cam_scale < MIN_ZOOM_FOR_POPUPS
	for coord: Vector2i in _popups.keys():
		(_popups[coord] as PanelContainer).visible = not too_far
	_line_drawer.visible = not too_far
	if too_far:
		return

	# Hex radius in screen pixels at current zoom
	var hex_screen_radius: float = _hex_grid.hex_size * cam_scale

	for coord: Vector2i in _popups.keys():
		var panel: PanelContainer = _popups[coord]
		var building: Node2D = _buildings.get(coord)
		if building == null or not is_instance_valid(building):
			_remove_popup(coord)
			continue

		var dir: Vector2 = _directions.get(coord, Vector2.UP)
		var building_screen: Vector2 = canvas_transform * building.global_position

		# Distance = hex radius + half popup size along direction + margin
		var half_panel: float = (absf(dir.x) * panel.size.x + absf(dir.y) * panel.size.y) / 2.0
		var dist: float = hex_screen_radius + half_panel + POPUP_MARGIN

		var popup_center: Vector2 = building_screen + dir * dist
		panel.position = popup_center - panel.size / 2.0

	_line_drawer.queue_redraw()


func _on_line_draw() -> void:
	if _popups.is_empty():
		return

	var canvas_transform := get_viewport().get_canvas_transform()

	for coord: Vector2i in _popups.keys():
		var panel: PanelContainer = _popups[coord]
		var building: Node2D = _buildings.get(coord)
		if building == null or not is_instance_valid(building):
			continue

		var building_screen: Vector2 = canvas_transform * building.global_position
		# Find the edge point of the popup closest to the building
		var popup_edge: Vector2 = _get_rect_edge_point(
			Rect2(panel.position, panel.size), building_screen
		)

		# Draw connector line
		var line_color := Color(0.85, 0.65, 0.25, 0.5)
		_line_drawer.draw_line(popup_edge, building_screen, line_color, 2.0, true)

		# Draw small circle at building end (anchor dot)
		_line_drawer.draw_circle(building_screen, 4.0, Color(0.85, 0.65, 0.25, 0.7))

		# Draw small diamond at popup end
		var diamond_size := 5.0
		var dir_to_building: Vector2 = (building_screen - popup_edge).normalized()
		var perp: Vector2 = Vector2(-dir_to_building.y, dir_to_building.x)
		var diamond := PackedVector2Array([
			popup_edge + dir_to_building * diamond_size,
			popup_edge + perp * diamond_size * 0.6,
			popup_edge - dir_to_building * diamond_size,
			popup_edge - perp * diamond_size * 0.6,
		])
		_line_drawer.draw_colored_polygon(diamond, Color(0.85, 0.65, 0.25, 0.6))


## Get the point on a rectangle's edge closest to an external point.
func _get_rect_edge_point(rect: Rect2, target: Vector2) -> Vector2:
	var center: Vector2 = rect.position + rect.size / 2.0
	var dir: Vector2 = target - center
	if dir.length_squared() < 1.0:
		return center

	# Scale direction to hit rectangle edge
	var half_w: float = rect.size.x / 2.0
	var half_h: float = rect.size.y / 2.0

	var scale_x: float = absf(dir.x) / half_w if absf(dir.x) > 0.001 else 99999.0
	var scale_y: float = absf(dir.y) / half_h if absf(dir.y) > 0.001 else 99999.0
	var scale_factor: float = maxf(scale_x, scale_y)

	return center + dir / scale_factor


func _on_hero_near_building(building_node: Node2D, coord: Vector2i) -> void:
	if _popups.has(coord):
		return
	if not building_node.has_method("upgrade"):
		return
	_buildings[coord] = building_node
	_create_popup(coord, building_node)
	_calculate_directions()


func _on_hero_left_building() -> void:
	_clear_all_popups()


func _on_building_upgraded(coord: Vector2i, _new_level: int) -> void:
	if _popups.has(coord) and _buildings.has(coord):
		_update_popup_display(coord)


func _on_phase_changed(phase: StringName) -> void:
	if phase == &"day":
		_clear_all_popups()


## Calculate frozen directions for all popups (called once when popups change).
## Direction is away from hero, spread apart to avoid overlap.
func _calculate_directions() -> void:
	var hero_pos: Vector2 = _hero.global_position

	# Calculate base direction for each popup (away from hero)
	var dirs: Array[Dictionary] = []
	for coord: Vector2i in _popups.keys():
		var building: Node2D = _buildings.get(coord)
		if building == null:
			continue
		var dir: Vector2 = (building.global_position - hero_pos)
		if dir.length_squared() < 1.0:
			dir = Vector2.UP
		dir = dir.normalized()
		dirs.append({"coord": coord, "dir": dir})

	# Spread directions apart if they're too similar (minimum 30 degrees apart)
	var min_angle := deg_to_rad(35.0)
	for iteration in range(3):
		for i in range(dirs.size()):
			for j in range(i + 1, dirs.size()):
				var angle: float = dirs[i].dir.angle_to(dirs[j].dir)
				if absf(angle) < min_angle:
					# Rotate them apart
					var spread: float = (min_angle - absf(angle)) / 2.0 + 0.05
					dirs[i].dir = dirs[i].dir.rotated(-spread)
					dirs[j].dir = dirs[j].dir.rotated(spread)

	# Store frozen directions
	for entry in dirs:
		_directions[entry.coord] = (entry.dir as Vector2).normalized()


func _create_popup(coord: Vector2i, _building_node: Node2D) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(170, 0)

	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.04, 0.92)
	style.border_color = Color(0.85, 0.65, 0.25, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_width_top = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	# Header: Name + Level
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45, 1.0))
	name_label.add_theme_font_size_override("font_size", 14)
	header.add_child(name_label)

	var level_badge := Label.new()
	level_badge.name = "LevelBadge"
	level_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_badge.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4, 0.85))
	level_badge.add_theme_font_size_override("font_size", 12)
	header.add_child(level_badge)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	vbox.add_child(sep)

	# Stats container
	var stats_box := VBoxContainer.new()
	stats_box.name = "StatsBox"
	stats_box.add_theme_constant_override("separation", 2)
	vbox.add_child(stats_box)

	# Upgrade button
	var btn := Button.new()
	btn.name = "UpgradeBtn"
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.9, 1.0))

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.45, 0.15, 0.9)
	btn_style.border_color = Color(0.45, 0.75, 0.25, 0.85)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(5)
	btn_style.content_margin_left = 10.0
	btn_style.content_margin_top = 5.0
	btn_style.content_margin_right = 10.0
	btn_style.content_margin_bottom = 5.0
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.35, 0.55, 0.2, 0.95)
	btn_hover.border_color = Color(0.55, 0.85, 0.3, 1.0)
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := btn_style.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.2, 0.4, 0.12, 0.95)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	var upgrade_coord := coord
	btn.pressed.connect(func(): SignalBus.upgrade_requested.emit(upgrade_coord))
	vbox.add_child(btn)

	# Max level label
	var max_label := Label.new()
	max_label.name = "MaxLabel"
	max_label.text = "MAX LEVEL"
	max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.7))
	max_label.add_theme_font_size_override("font_size", 11)
	max_label.visible = false
	vbox.add_child(max_label)

	add_child(panel)
	_popups[coord] = panel

	# Fade in
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)

	_update_popup_display(coord)


func _make_separator_style() -> StyleBoxFlat:
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.7, 0.55, 0.2, 0.3)
	sep_style.content_margin_top = 1.0
	sep_style.content_margin_bottom = 1.0
	return sep_style


func _update_popup_display(coord: Vector2i) -> void:
	if not _popups.has(coord) or not _buildings.has(coord):
		return
	var panel: PanelContainer = _popups[coord]
	var building: Node2D = _buildings[coord]
	var vbox: VBoxContainer = panel.get_child(0) as VBoxContainer

	# Header
	var header: HBoxContainer = vbox.get_child(0) as HBoxContainer
	var name_label: Label = header.get_node("NameLabel") if header else null
	var level_badge: Label = header.get_node("LevelBadge") if header else null

	if name_label:
		name_label.text = building.data.display_name
	if level_badge:
		level_badge.text = "Lv%d" % building.level

	# Stats
	var stats_box: VBoxContainer = vbox.get_node("StatsBox") if vbox.has_node("StatsBox") else null
	if stats_box:
		for child in stats_box.get_children():
			child.queue_free()
		_add_stat_line(stats_box, building)

	# Upgrade button
	var btn: Button = vbox.get_node("UpgradeBtn") if vbox.has_node("UpgradeBtn") else null
	var max_label: Label = vbox.get_node("MaxLabel") if vbox.has_node("MaxLabel") else null

	if building.level < building.data.max_level:
		if btn:
			btn.visible = true
			btn.text = "Upgrade to Lv%d" % (building.level + 1)
		if max_label:
			max_label.visible = false
	else:
		if btn:
			btn.visible = false
		if max_label:
			max_label.visible = true


func _add_stat_line(stats_box: VBoxContainer, building: Node2D) -> void:
	var id: StringName = building.data.id
	var lv: int = building.level

	if id == &"honey_turret":
		_add_stat(stats_box, "Damage", "%d" % (5 + lv * 3), Color(1.0, 0.6, 0.3))
		_add_stat(stats_box, "Range", "%d tiles" % (2 + lv), Color(0.6, 0.85, 1.0))
		_add_stat(stats_box, "Speed", "%.1f/s" % (0.8 + lv * 0.2), Color(0.8, 1.0, 0.6))
	elif id == &"wall":
		_add_stat(stats_box, "HP", "%d" % (20 + lv * 15), Color(1.0, 0.5, 0.5))
		_add_stat(stats_box, "Armor", "%d" % (lv * 2), Color(0.7, 0.7, 0.85))
	elif id == &"flower_garden":
		_add_stat(stats_box, "Income", "+%d/cycle" % (3 + lv * 2), Color(1.0, 0.85, 0.3))
		_add_stat(stats_box, "Range", "%d tiles" % (1 + lv), Color(0.6, 0.85, 1.0))
	elif id == &"hive":
		_add_stat(stats_box, "HP", "%d" % (50 + lv * 25), Color(1.0, 0.5, 0.5))
		_add_stat(stats_box, "Aura", "%d tiles" % (2 + lv), Color(1.0, 0.9, 0.5))


func _add_stat(container: VBoxContainer, stat_name: String, stat_value: String, value_color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)

	var label := Label.new()
	label.text = stat_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 0.8))
	label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(label)

	var value := Label.new()
	value.text = stat_value
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", value_color)
	value.add_theme_font_size_override("font_size", 12)
	hbox.add_child(value)

	container.add_child(hbox)


func _remove_popup(coord: Vector2i) -> void:
	if _popups.has(coord):
		var panel: PanelContainer = _popups[coord]
		panel.queue_free()
		_popups.erase(coord)
	_buildings.erase(coord)
	_directions.erase(coord)


func _clear_all_popups() -> void:
	for coord: Vector2i in _popups.keys():
		var panel: PanelContainer = _popups[coord]
		panel.queue_free()
	_popups.clear()
	_buildings.clear()
	_directions.clear()
	_line_drawer.queue_redraw()
