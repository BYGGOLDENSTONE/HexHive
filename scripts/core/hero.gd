class_name Hero
extends Node2D
## Player-controlled hero bee. Moves freely with WASD/arrow keys.
## The grid system tracks which large hex tile the hero occupies.

## Emitted when the hero transitions to a new large hex tile.
signal hex_changed(old_hex: Vector2i, new_hex: Vector2i)

## Movement speed in pixels per second.
@export var move_speed: float = 200.0

## Speed multiplier during night phase (hero moves faster at night for building).
@export var night_speed_multiplier: float = 1.5

## Active speed multiplier (updated by day/night signals).
var _speed_multiplier: float = 1.5

## Visual scale relative to a slot hex (1.0 = same size as slot).
@export var visual_scale: float = 1.1

## Reference to the hex grid.
@onready var hex_grid: HexGrid = %HexGrid

## The hero's current official large hex tile coordinate.
var current_hex: Vector2i = Vector2i.ZERO

## Cached visual size for drawing.
var _draw_size: float = 0.0

## Auto-walk target world position (null when not auto-walking).
var _auto_walk_target_pos: Variant = null  # Vector2 or null

## Auto-walk target hex coordinate.
var _auto_walk_target_hex: Variant = null  # Vector2i or null

## How close (in hex distance) hero needs to be to stop auto-walking.
var _auto_walk_range: int = 1

## Whether hero is currently auto-walking.
var is_auto_walking: bool = false

## Stuck detection: time since last hex change during auto-walk.
var _auto_walk_stuck_time: float = 0.0

## Stuck timeout in seconds.
const AUTO_WALK_STUCK_TIMEOUT: float = 3.0


func _ready() -> void:
	var slot_size: float = hex_grid.slot_radius / sqrt(3.0)
	_draw_size = slot_size * visual_scale

	# Start hero at hex (1, 0) — next to the Hive at center
	position = HexHelper.axial_to_pixel(Vector2i(1, 0), hex_grid.hex_size)
	current_hex = HexHelper.pixel_to_hex(position, hex_grid.hex_size)

	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.build_walk_requested.connect(_on_build_walk_requested)


func _process(delta: float) -> void:
	if is_auto_walking:
		var input_dir := _get_input_direction()
		if input_dir != Vector2.ZERO:
			_cancel_auto_walk()
			_apply_movement(input_dir, delta)
		else:
			_process_auto_walk(delta)
	else:
		var input_dir := _get_input_direction()
		if input_dir != Vector2.ZERO:
			_apply_movement(input_dir, delta)
	_update_hex_tracking()
	queue_redraw()


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	return dir.normalized()


func _apply_movement(input_dir: Vector2, delta: float) -> void:
	var move_vec := input_dir * move_speed * _speed_multiplier * delta

	# Try full movement
	var desired := position + move_vec
	if _is_position_walkable(desired):
		position = desired
		return

	# Wall slide: try horizontal only
	var h_pos := position + Vector2(move_vec.x, 0.0)
	if move_vec.x != 0.0 and _is_position_walkable(h_pos):
		position = h_pos
		return

	# Wall slide: try vertical only
	var v_pos := position + Vector2(0.0, move_vec.y)
	if move_vec.y != 0.0 and _is_position_walkable(v_pos):
		position = v_pos
		return


func _is_position_walkable(pos: Vector2) -> bool:
	var hex := HexHelper.pixel_to_hex(pos, hex_grid.hex_size)
	var tile := hex_grid.get_tile(hex)
	return tile != null and tile.is_walkable()


func _update_hex_tracking() -> void:
	var position_hex := HexHelper.pixel_to_hex(position, hex_grid.hex_size)
	if position_hex != current_hex:
		var old_hex := current_hex
		current_hex = position_hex
		if is_auto_walking:
			_auto_walk_stuck_time = 0.0
		hex_changed.emit(old_hex, current_hex)


func _draw() -> void:
	# Hero body — flat-top hex shape, warm gold
	var corners := HexHelper.get_flat_hex_corners(Vector2.ZERO, _draw_size)
	draw_colored_polygon(corners, Color(0.95, 0.75, 0.2, 0.9))

	# Thick outline — darker gold
	for i in range(corners.size()):
		var next := (i + 1) % corners.size()
		draw_line(corners[i], corners[next], Color(0.75, 0.55, 0.1, 1.0), 2.5, true)

	# Inner glow — lighter center hex
	var inner := HexHelper.get_flat_hex_corners(Vector2.ZERO, _draw_size * 0.55)
	draw_colored_polygon(inner, Color(1.0, 0.9, 0.5, 0.6))

	# Direction indicator — small upward triangle
	var s := _draw_size * 0.3
	var off := Vector2(0.0, -_draw_size * 0.35)
	var tri := PackedVector2Array([
		off + Vector2(0.0, -s),
		off + Vector2(-s * 0.6, s * 0.4),
		off + Vector2(s * 0.6, s * 0.4),
	])
	draw_colored_polygon(tri, Color(1.0, 1.0, 1.0, 0.8))


func _on_phase_changed(phase: StringName) -> void:
	_speed_multiplier = night_speed_multiplier if phase == &"night" else 1.0
	if phase == &"day" and is_auto_walking:
		_cancel_auto_walk()


func _on_build_walk_requested(target_coord: Vector2i) -> void:
	# Check if already in range
	if HexHelper.distance(current_hex, target_coord) <= _auto_walk_range:
		SignalBus.hero_reached_build_range.emit(target_coord)
		return
	_auto_walk_target_hex = target_coord
	_auto_walk_target_pos = HexHelper.axial_to_pixel(target_coord, hex_grid.hex_size)
	is_auto_walking = true
	_auto_walk_stuck_time = 0.0


func _process_auto_walk(delta: float) -> void:
	if _auto_walk_target_hex == null or _auto_walk_target_pos == null:
		_cancel_auto_walk()
		return

	var target_hex: Vector2i = _auto_walk_target_hex as Vector2i
	var target_pos: Vector2 = _auto_walk_target_pos as Vector2

	# Check if already in range
	if HexHelper.distance(current_hex, target_hex) <= _auto_walk_range:
		_finish_auto_walk()
		return

	# Move toward target
	var dir: Vector2 = (target_pos - position).normalized()
	_apply_movement(dir, delta)

	# Stuck detection
	_auto_walk_stuck_time += delta
	if _auto_walk_stuck_time >= AUTO_WALK_STUCK_TIMEOUT:
		_cancel_auto_walk()
		return

	# Re-check after movement
	if HexHelper.distance(current_hex, target_hex) <= _auto_walk_range:
		_finish_auto_walk()


func _finish_auto_walk() -> void:
	var target := _auto_walk_target_hex as Vector2i
	_auto_walk_target_pos = null
	_auto_walk_target_hex = null
	is_auto_walking = false
	_auto_walk_stuck_time = 0.0
	SignalBus.hero_reached_build_range.emit(target)


func _cancel_auto_walk() -> void:
	_auto_walk_target_pos = null
	_auto_walk_target_hex = null
	is_auto_walking = false
	_auto_walk_stuck_time = 0.0
	SignalBus.build_walk_cancelled.emit()
