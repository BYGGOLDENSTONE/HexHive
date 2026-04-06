class_name Building
extends Node2D
## A placed building on the hex grid.
## Renders itself using procedural _draw() based on BuildingData and current level.

## The building type definition.
var data: Resource

## Axial coordinate of the tile this building occupies.
var hex_coord: Vector2i

## Current upgrade level (starts at 1).
var level: int = 1

## Runtime tags copied from data (can be modified by buffs/upgrades).
var tags: Array[StringName] = []

## Draw size (set during setup based on hex grid size).
var _draw_size: float = 0.0


## Initialize the building with its data, coordinate, and position.
func setup(building_data: Resource, coord: Vector2i, world_pos: Vector2, hex_size: float) -> void:
	data = building_data
	hex_coord = coord
	position = world_pos
	tags = data.tags.duplicate()
	_draw_size = hex_size
	z_index = -1


## Upgrade the building to the next level. Returns true if successful.
func upgrade() -> bool:
	if level >= data.max_level:
		return false
	level += 1
	_play_upgrade_effect()
	queue_redraw()
	return true


## Get the color for the current level.
func _get_level_color() -> Color:
	var idx := level - 1
	if idx < data.level_colors.size():
		return data.level_colors[idx]
	return Color(0.8, 0.8, 0.8, 1.0)


## Get the accent color for the current level.
func _get_accent_color() -> Color:
	var idx := level - 1
	if idx < data.level_accent_colors.size():
		return data.level_accent_colors[idx]
	return Color(0.5, 0.5, 0.5, 1.0)


func _draw() -> void:
	if data == null:
		return

	var base_color := _get_level_color()
	var accent := _get_accent_color()

	if data.id == &"honey_turret":
		_draw_turret(base_color, accent)
	elif data.id == &"wall":
		_draw_wall(base_color, accent)
	elif data.id == &"flower_garden":
		_draw_flower_garden(base_color, accent)
	elif data.id == &"hive":
		_draw_hive(base_color, accent)
	else:
		_draw_generic(base_color, accent)


func _draw_turret(base: Color, accent: Color) -> void:
	var s := _draw_size

	# Base platform — full pointy-top hex
	var base_corners := HexHelper.get_hex_corners(Vector2.ZERO, s)
	draw_colored_polygon(base_corners, accent)

	# Turret body — inner hex
	var body_corners := HexHelper.get_hex_corners(Vector2.ZERO, s * 0.65)
	draw_colored_polygon(body_corners, base)

	# Cannon barrel
	var barrel_w := s * 0.18
	var barrel_h := s * 0.5
	draw_rect(Rect2(-barrel_w / 2.0, -s * 0.65 - barrel_h * 0.2, barrel_w, barrel_h), accent)

	# Cannon tip glow
	var tip_pos := Vector2(0.0, -s * 0.65 - barrel_h * 0.2)
	draw_circle(tip_pos, s * 0.12, Color(1.0, 0.85, 0.3, 0.8))

	# Level indicators — small dots
	for i in range(level):
		var dot_x := -s * 0.3 + i * s * 0.3
		draw_circle(Vector2(dot_x, s * 0.4), s * 0.07, Color(1.0, 0.9, 0.4, 0.9))

	# Outline
	_draw_hex_outline(base_corners, accent.darkened(0.3), 2.5)


func _draw_wall(base: Color, accent: Color) -> void:
	var s := _draw_size

	# Honeycomb wall — full hex
	var outer := HexHelper.get_hex_corners(Vector2.ZERO, s)
	draw_colored_polygon(outer, base)

	# Inner honeycomb pattern
	var inner := HexHelper.get_hex_corners(Vector2.ZERO, s * 0.65)
	draw_colored_polygon(inner, accent)

	# Cross-hatching for reinforcement look (per level)
	if level >= 2:
		var inner2 := HexHelper.get_hex_corners(Vector2.ZERO, s * 0.45)
		draw_colored_polygon(inner2, base.lightened(0.15))
	if level >= 3:
		# Spikes on top and bottom
		for angle_offset in [0.0, PI]:
			var spike_base := Vector2(0.0, -s * 0.9).rotated(angle_offset)
			var spike_tip := Vector2(0.0, -s * 1.15).rotated(angle_offset)
			var spike_left := spike_base + Vector2(-s * 0.14, 0.0).rotated(angle_offset)
			var spike_right := spike_base + Vector2(s * 0.14, 0.0).rotated(angle_offset)
			draw_colored_polygon(PackedVector2Array([spike_tip, spike_left, spike_right]), accent.lightened(0.2))

	# Outline
	_draw_hex_outline(outer, accent.darkened(0.3), 3.0)


func _draw_flower_garden(base: Color, accent: Color) -> void:
	var s := _draw_size

	# Ground patch — full hex
	var ground := HexHelper.get_hex_corners(Vector2.ZERO, s)
	draw_colored_polygon(ground, base)

	# Flowers — petals around center points
	var flower_count := level + 1
	for i in range(flower_count):
		var angle := TAU * i / flower_count
		var flower_pos := Vector2(cos(angle), sin(angle)) * s * 0.35
		# Petals
		for p in range(5):
			var petal_angle := TAU * p / 5.0
			var petal_pos := flower_pos + Vector2(cos(petal_angle), sin(petal_angle)) * s * 0.1
			draw_circle(petal_pos, s * 0.07, accent)
		# Flower center
		draw_circle(flower_pos, s * 0.06, Color(1.0, 0.9, 0.3, 1.0))

	# Center honey drop
	draw_circle(Vector2.ZERO, s * 0.1, Color(1.0, 0.8, 0.2, 0.7))

	# Outline
	_draw_hex_outline(ground, base.darkened(0.3), 1.5)


func _draw_hive(base: Color, accent: Color) -> void:
	var s := _draw_size

	# Main dome shape — full hex
	var dome := HexHelper.get_hex_corners(Vector2.ZERO, s)
	draw_colored_polygon(dome, base)

	# Inner honeycomb rings
	var ring1 := HexHelper.get_hex_corners(Vector2.ZERO, s * 0.7)
	draw_colored_polygon(ring1, accent)
	var ring2 := HexHelper.get_hex_corners(Vector2.ZERO, s * 0.45)
	draw_colored_polygon(ring2, base.lightened(0.15))

	# Core glow
	draw_circle(Vector2.ZERO, s * 0.2, Color(1.0, 0.9, 0.4, 0.8))
	draw_circle(Vector2.ZERO, s * 0.12, Color(1.0, 0.95, 0.7, 0.9))

	# Entrance — small arch at bottom
	var entrance_w := s * 0.25
	var entrance_h := s * 0.18
	var entrance_y := s * 0.5
	draw_rect(Rect2(-entrance_w / 2.0, entrance_y, entrance_w, entrance_h), accent.darkened(0.4))

	# Level crown — dots on top
	for i in range(level):
		var dot_x := -s * 0.2 + i * s * 0.2
		draw_circle(Vector2(dot_x, -s * 0.7), s * 0.06, Color(1.0, 0.95, 0.6, 0.9))

	# Thick outline
	_draw_hex_outline(dome, accent.darkened(0.2), 3.0)


func _draw_generic(base: Color, accent: Color) -> void:
	var s := _draw_size
	var corners := HexHelper.get_hex_corners(Vector2.ZERO, s)
	draw_colored_polygon(corners, base)
	_draw_hex_outline(corners, accent.darkened(0.3), 2.0)


func _draw_hex_outline(corners: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(corners.size()):
		var next := (i + 1) % corners.size()
		draw_line(corners[i], corners[next], color, width, true)


func _play_upgrade_effect() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.15)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)


## Play a placement animation (called after building is added to the scene).
func play_place_effect() -> void:
	scale = Vector2(0.0, 0.0)
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.35)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
