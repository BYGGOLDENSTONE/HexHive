class_name BuildGhost
extends Node2D
## Renders a ghost preview of the building being placed.
## Follows the mouse cursor, snaps to hex grid, shows green/red validity.

@onready var hex_grid: HexGrid = %HexGrid

## Whether the ghost is active (visible and tracking mouse).
var _active: bool = false

## Building data for the ghost preview.
var _building_data: Resource = null

## Current snapped hex coordinate.
var _current_coord: Variant = null  # Vector2i or null

## Whether current position is valid for placement.
var _is_valid: bool = false

## Draw size based on hex size.
var _draw_size: float = 0.0


func _ready() -> void:
	visible = false
	z_index = 5
	SignalBus.build_preview_started.connect(_on_preview_started)
	SignalBus.build_preview_ended.connect(_on_preview_ended)
	SignalBus.building_placed.connect(_on_building_placed)


func _process(_delta: float) -> void:
	if not _active:
		return

	var mouse_world := get_global_mouse_position()
	var coord := hex_grid.world_to_hex(mouse_world)

	if hex_grid.has_tile(coord):
		if _current_coord == null or coord != (_current_coord as Vector2i):
			_current_coord = coord
			position = hex_grid.hex_to_world(coord)
			_is_valid = hex_grid.can_place_building(coord, _building_data)
			SignalBus.build_preview_moved.emit(coord, _is_valid)
		queue_redraw()
	else:
		if _current_coord != null:
			_current_coord = null
			_is_valid = false
			queue_redraw()


func _on_preview_started(building_data: Resource) -> void:
	_building_data = building_data
	_draw_size = hex_grid.hex_size * 0.7
	_current_coord = null
	_is_valid = false
	_active = true
	visible = true


func _on_preview_ended() -> void:
	_active = false
	visible = false
	_building_data = null
	_current_coord = null


func _on_building_placed(_building_id: StringName, _coord: Vector2i, _level: int) -> void:
	# Reset coord so next hover recalculates validity
	_current_coord = null


func _draw() -> void:
	if not _active or _current_coord == null or _building_data == null:
		return

	var hex_size := hex_grid.hex_size
	var corners := HexHelper.get_hex_corners(Vector2.ZERO, hex_size)

	# Hex fill — green for valid, red for invalid
	var fill_color: Color
	var outline_color: Color
	if _is_valid:
		fill_color = Color(0.3, 1.0, 0.3, 0.2)
		outline_color = Color(0.2, 0.9, 0.2, 0.7)
	else:
		fill_color = Color(1.0, 0.3, 0.3, 0.2)
		outline_color = Color(0.9, 0.2, 0.2, 0.7)

	draw_colored_polygon(corners, fill_color)

	# Hex outline
	for i in range(corners.size()):
		var next := (i + 1) % corners.size()
		draw_line(corners[i], corners[next], outline_color, 2.5, true)

	# Building preview (semi-transparent)
	if _is_valid:
		_draw_building_preview()


func _draw_building_preview() -> void:
	var s := _draw_size
	var base_color := Color(1.0, 1.0, 1.0, 0.4)

	if _building_data.id == &"honey_turret":
		var body := HexHelper.get_flat_hex_corners(Vector2.ZERO, s * 0.6)
		draw_colored_polygon(body, Color(0.85, 0.6, 0.15, 0.4))
		var barrel_w := s * 0.15
		var barrel_h := s * 0.45
		draw_rect(Rect2(-barrel_w / 2.0, -s * 0.6 - barrel_h * 0.3, barrel_w, barrel_h), Color(0.6, 0.4, 0.1, 0.4))
	elif _building_data.id == &"wall":
		var outer := HexHelper.get_flat_hex_corners(Vector2.ZERO, s * 0.9)
		draw_colored_polygon(outer, Color(0.65, 0.5, 0.25, 0.4))
	elif _building_data.id == &"flower_garden":
		var ground := HexHelper.get_flat_hex_corners(Vector2.ZERO, s * 0.85)
		draw_colored_polygon(ground, Color(0.4, 0.7, 0.3, 0.4))
		# Small flower hint
		for i in range(3):
			var angle := TAU * i / 3.0
			var pos := Vector2(cos(angle), sin(angle)) * s * 0.35
			draw_circle(pos, s * 0.08, Color(0.9, 0.5, 0.6, 0.4))
	else:
		var generic := HexHelper.get_flat_hex_corners(Vector2.ZERO, s * 0.7)
		draw_colored_polygon(generic, base_color)
