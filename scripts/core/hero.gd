class_name Hero
extends Node2D
## Player-controlled hero bee. Moves freely with WASD/arrow keys.
## The grid system tracks which large hex tile the hero occupies.
## Auto-attacks the nearest enemy in range with honey projectiles.

const HealthScript = preload("res://scripts/combat/health.gd")
const ProjectileScript = preload("res://scripts/combat/projectile.gd")

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

## How big the sprite renders relative to the hex slot diameter.
## 1.0 = sprite spans one slot diameter; >1 = larger so wings show.
@export var sprite_scale_factor: float = 2.6

## Hover (idle bobbing) frequency in radians per second.
@export var hover_frequency: float = 5.0

## Hover amplitude in pixels.
@export var hover_amplitude: float = 3.5

## -- Combat stats --

## Maximum HP.
@export var max_hp: float = 100.0

## Damage per attack.
@export var attack_damage: float = 15.0

## Attack range in pixels.
@export var attack_range: float = 165.0

## Attacks per second.
@export var attack_speed: float = 1.5

## Time stunned/dead before respawning at Hive.
@export var respawn_delay: float = 3.0

## Reference to the hex grid.
@onready var hex_grid: HexGrid = %HexGrid

## The hero's current official large hex tile coordinate.
var current_hex: Vector2i = Vector2i.ZERO

## Cached visual size for drawing.
var _draw_size: float = 0.0

## Auto-walk target hex coordinate.
var _auto_walk_target_hex: Variant = null  # Vector2i or null

## How close (in hex distance) hero needs to be to stop auto-walking.
var _auto_walk_range: int = 1

## Whether hero is currently auto-walking.
var is_auto_walking: bool = false

## Current path being followed (Array[Vector2i]). Empty when no path.
var _auto_walk_path: Array[Vector2i] = []

## Index of the next hex in `_auto_walk_path` to walk toward.
var _auto_walk_path_index: int = 0

## Stuck detection: time since last hex change during auto-walk.
var _auto_walk_stuck_time: float = 0.0

## Stuck timeout in seconds.
const AUTO_WALK_STUCK_TIMEOUT: float = 3.0

## -- Combat state --

## Health component (added in _ready).
var health: HealthScript

## Cached attack cooldown.
var _attack_cooldown: float = 0.0

## Damage flash timer.
var _flash_timer: float = 0.0

## True while dead/respawning — disables movement, attack, and rendering.
var _is_dead: bool = false

## Time remaining until respawn.
var _respawn_timer: float = 0.0

## Cached projectile scene.
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

## Lazy reference to projectiles container.
var _projectiles_container: Node2D = null

## Spawn position (set on first ready, used for respawn).
var _spawn_position: Vector2 = Vector2.ZERO

## -- Sprite & hover state --

## 8-direction sprite textures (preloaded).
const SPRITE_TEXTURES: Dictionary = {
	&"e":  preload("res://assets/sprites/hero/hero_e.png"),
	&"se": preload("res://assets/sprites/hero/hero_se.png"),
	&"s":  preload("res://assets/sprites/hero/hero_s.png"),
	&"sw": preload("res://assets/sprites/hero/hero_sw.png"),
	&"w":  preload("res://assets/sprites/hero/hero_w.png"),
	&"nw": preload("res://assets/sprites/hero/hero_nw.png"),
	&"n":  preload("res://assets/sprites/hero/hero_n.png"),
	&"ne": preload("res://assets/sprites/hero/hero_ne.png"),
}

## Direction names indexed by 45-degree sector starting at East = 0.
const DIRECTION_BY_SECTOR: Array[StringName] = [
	&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne",
]

## Sprite child node (created in _ready).
var _sprite: Sprite2D

## Currently displayed facing direction.
var _facing: StringName = &"se"

## Hover animation phase (radians).
var _hover_time: float = 0.0


func _ready() -> void:
	add_to_group(&"hero")

	var slot_size: float = hex_grid.slot_radius / sqrt(3.0)
	_draw_size = slot_size * visual_scale

	# Start hero at hex (1, 0) — next to the Hive at center
	_spawn_position = HexHelper.axial_to_pixel(Vector2i(1, 0), hex_grid.hex_size)
	position = _spawn_position
	current_hex = HexHelper.pixel_to_hex(position, hex_grid.hex_size)

	# Health component
	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = max_hp
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	# Create the directional sprite child. Drawn behind the hero's _draw output
	# (HP bar, respawn ring) via z_index = -1.
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.z_index = -1
	_sprite.texture = SPRITE_TEXTURES[_facing]
	var tex_w: float = float(_sprite.texture.get_width())
	if tex_w > 0.0:
		var sprite_pixel_target: float = _draw_size * 2.0 * sprite_scale_factor
		var s: float = sprite_pixel_target / tex_w
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)

	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.build_walk_requested.connect(_on_build_walk_requested)
	SignalBus.restart_requested.connect(_on_restart_requested)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	# Hover bobbing — independent of dead/alive so the visual stays alive feeling
	# (skipped while dead since the sprite is hidden anyway).
	_hover_time += delta * hover_frequency

	if _is_dead:
		if _sprite != null:
			_sprite.visible = false
		_respawn_timer = maxf(0.0, _respawn_timer - delta)
		if _respawn_timer <= 0.0:
			_respawn()
		queue_redraw()
		return

	if _sprite != null and not _sprite.visible:
		_sprite.visible = true

	# Track movement input so we can update facing only when actually moving.
	var moved_dir: Vector2 = Vector2.ZERO

	if is_auto_walking:
		var input_dir := _get_input_direction()
		if input_dir != Vector2.ZERO:
			_cancel_auto_walk()
			_apply_movement(input_dir, delta)
			moved_dir = input_dir
		else:
			moved_dir = _process_auto_walk(delta)
	else:
		var input_dir := _get_input_direction()
		if input_dir != Vector2.ZERO:
			_apply_movement(input_dir, delta)
			moved_dir = input_dir
	_update_hex_tracking()

	# Update facing sprite if there is meaningful movement input.
	if moved_dir.length_squared() > 0.0001:
		_set_facing_from_vector(moved_dir)

	# Apply hover offset and damage flash to the sprite.
	if _sprite != null:
		_sprite.position = Vector2(0.0, sin(_hover_time) * hover_amplitude)
		if _flash_timer > 0.0:
			var t: float = _flash_timer / 0.18
			_sprite.modulate = Color(1.0, 1.0 - 0.55 * t, 1.0 - 0.55 * t, 1.0)
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Auto-attack during day phase.
	if DayNightManager.is_day():
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
		if _attack_cooldown <= 0.0:
			var target: Node2D = _find_nearest_enemy()
			if target != null:
				_fire_at(target)
				_attack_cooldown = 1.0 / maxf(attack_speed, 0.01)

	queue_redraw()


## Maps a movement vector to one of the 8 sprite directions and updates the
## sprite texture if the facing actually changed.
func _set_facing_from_vector(v: Vector2) -> void:
	# atan2 in Godot: 0 = +X (east), +PI/2 = +Y (south, screen down).
	var deg: float = rad_to_deg(v.angle())
	deg = fposmod(deg, 360.0)
	var sector: int = int(round(deg / 45.0)) % 8
	var dir_name: StringName = DIRECTION_BY_SECTOR[sector]
	if dir_name == _facing:
		return
	_facing = dir_name
	if _sprite != null:
		_sprite.texture = SPRITE_TEXTURES[_facing]


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


# -- Combat --------------------------------------------------------------------

func _find_nearest_enemy() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var enemies: Array = tree.get_nodes_in_group(&"enemies")
	var best: Node2D = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= attack_range and d < best_d:
			best_d = d
			best = e
	return best


func _fire_at(target: Node2D) -> void:
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles") as Node2D
	if _projectiles_container == null:
		return
	var p: ProjectileScript = PROJECTILE_SCENE.instantiate() as ProjectileScript
	_projectiles_container.add_child(p)
	p.team = &"player"
	p.setup(global_position + Vector2(0.0, -_draw_size * 0.4), target, attack_damage, 580.0)


## External damage entry-point used by enemies.
func take_damage(amount: float) -> void:
	if _is_dead or health == null:
		return
	health.take_damage(amount)


func _on_damaged(amount: float, current: float, maximum: float) -> void:
	_flash_timer = 0.18
	SignalBus.hero_damaged.emit(amount, current, maximum)


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	_respawn_timer = respawn_delay
	_cancel_auto_walk()
	SignalBus.hero_died.emit()


func _respawn() -> void:
	_is_dead = false
	position = _spawn_position
	current_hex = HexHelper.pixel_to_hex(position, hex_grid.hex_size)
	if health != null:
		health.revive(max_hp)
	_flash_timer = 0.0
	_attack_cooldown = 0.0
	scale = Vector2(0.4, 0.4)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.35)
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	SignalBus.hero_respawned.emit()


func _on_restart_requested() -> void:
	# Reset hero to spawn state for a new run.
	_is_dead = false
	_respawn_timer = 0.0
	position = _spawn_position
	current_hex = HexHelper.pixel_to_hex(position, hex_grid.hex_size)
	if health != null:
		health.revive(max_hp)
	scale = Vector2.ONE
	modulate.a = 1.0
	_flash_timer = 0.0
	_attack_cooldown = 0.0


## Returns true if the hero is alive (used by enemy targeting).
func is_alive() -> bool:
	return not _is_dead


func _draw() -> void:
	if _is_dead:
		_draw_respawn_indicator()
		return

	# Body is rendered by the directional Sprite2D child; only overlays here.
	# Damage flash is applied to the sprite's modulate in _process.

	# HP bar (only when damaged). Drawn at a fixed offset so it doesn't bob
	# with the hover animation.
	if health != null and health.current_hp < health.max_hp:
		_draw_hp_bar()


func _draw_hp_bar() -> void:
	var width: float = _draw_size * 2.2
	var height: float = 5.0
	# Place above the sprite (sprite spans ~_draw_size * sprite_scale_factor px high).
	var y: float = -_draw_size * (sprite_scale_factor + 0.2)
	draw_rect(Rect2(-width / 2.0, y, width, height), Color(0.05, 0.05, 0.05, 0.85))
	var frac: float = health.get_fraction()
	var col: Color = Color(0.4, 0.95, 0.4, 1.0) if frac > 0.5 else (Color(1.0, 0.85, 0.3, 1.0) if frac > 0.25 else Color(1.0, 0.35, 0.3, 1.0))
	draw_rect(Rect2(-width / 2.0 + 1.0, y + 1.0, (width - 2.0) * frac, height - 2.0), col)


func _draw_respawn_indicator() -> void:
	# Faint ghost outline + countdown ring.
	var corners := HexHelper.get_flat_hex_corners(Vector2.ZERO, _draw_size)
	for i in range(corners.size()):
		var next := (i + 1) % corners.size()
		draw_line(corners[i], corners[next], Color(0.95, 0.75, 0.2, 0.25), 1.5, true)
	# Countdown number.
	var font: Font = ThemeDB.fallback_font
	var text: String = "%.1f" % _respawn_timer
	var size_v: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	draw_string(font, Vector2(-size_v.x / 2.0, size_v.y / 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4, 0.85))


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
	is_auto_walking = true
	_auto_walk_stuck_time = 0.0
	if not _recompute_auto_walk_path():
		_cancel_auto_walk()


## Computes a fresh A* path from the hero's current hex toward the build
## target. The target hex itself is unwalkable (it will hold a building), so the
## search succeeds when the hero reaches any walkable hex within
## `_auto_walk_range` of the target. Returns true if a usable path was found.
func _recompute_auto_walk_path() -> bool:
	if _auto_walk_target_hex == null:
		return false
	var target_hex: Vector2i = _auto_walk_target_hex as Vector2i
	var path: Array[Vector2i] = hex_grid.find_path(current_hex, target_hex, _auto_walk_range)
	if path.is_empty():
		return false
	_auto_walk_path = path
	# path[0] is the current hex; advance to the next hex.
	_auto_walk_path_index = 1 if path.size() > 1 else 0
	return true


## Returns the movement direction the hero stepped this frame (Vector2.ZERO
## when no movement happened) so the caller can update facing.
func _process_auto_walk(delta: float) -> Vector2:
	if _auto_walk_target_hex == null:
		_cancel_auto_walk()
		return Vector2.ZERO

	var target_hex: Vector2i = _auto_walk_target_hex as Vector2i

	# Already in range — done.
	if HexHelper.distance(current_hex, target_hex) <= _auto_walk_range:
		_finish_auto_walk()
		return Vector2.ZERO

	# If we have no usable path step, try to recompute.
	if _auto_walk_path.is_empty() or _auto_walk_path_index >= _auto_walk_path.size():
		if not _recompute_auto_walk_path():
			_cancel_auto_walk()
			return Vector2.ZERO

	# Advance the path index past any hexes we've already entered.
	while _auto_walk_path_index < _auto_walk_path.size() and _auto_walk_path[_auto_walk_path_index] == current_hex:
		_auto_walk_path_index += 1

	if _auto_walk_path_index >= _auto_walk_path.size():
		# Path exhausted but not yet in range — recompute next frame.
		_auto_walk_path.clear()
		return Vector2.ZERO

	# Move toward the next hex on the path.
	var next_hex: Vector2i = _auto_walk_path[_auto_walk_path_index]
	var next_pos: Vector2 = HexHelper.axial_to_pixel(next_hex, hex_grid.hex_size)
	var dir: Vector2 = (next_pos - position).normalized()
	_apply_movement(dir, delta)

	# Stuck detection — recompute path once before giving up.
	_auto_walk_stuck_time += delta
	if _auto_walk_stuck_time >= AUTO_WALK_STUCK_TIMEOUT:
		_auto_walk_stuck_time = 0.0
		if not _recompute_auto_walk_path():
			_cancel_auto_walk()
			return Vector2.ZERO

	# Re-check after movement
	if HexHelper.distance(current_hex, target_hex) <= _auto_walk_range:
		_finish_auto_walk()
	return dir


func _finish_auto_walk() -> void:
	var target := _auto_walk_target_hex as Vector2i
	_auto_walk_target_hex = null
	_auto_walk_path.clear()
	_auto_walk_path_index = 0
	is_auto_walking = false
	_auto_walk_stuck_time = 0.0
	SignalBus.hero_reached_build_range.emit(target)


func _cancel_auto_walk() -> void:
	if not is_auto_walking:
		return
	_auto_walk_target_hex = null
	_auto_walk_path.clear()
	_auto_walk_path_index = 0
	is_auto_walking = false
	_auto_walk_stuck_time = 0.0
	SignalBus.build_walk_cancelled.emit()
