class_name Hero
extends Node3D
## Player-controlled hero bee. Moves freely with WASD/arrow keys on the XZ plane.
## Auto-attacks the nearest enemy in range with honey projectiles.

const HealthScript = preload("res://scripts/combat/health.gd")

signal hex_changed(old_hex: Vector2i, new_hex: Vector2i)

## Movement speed in world units per second.
@export var move_speed: float = 4.0

## Speed multiplier during night phase.
@export var night_speed_multiplier: float = 1.5

## Active speed multiplier.
var _speed_multiplier: float = 1.5

## -- Combat stats --
@export var max_hp: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_range: float = 3.5
@export var attack_speed: float = 1.5
@export var respawn_delay: float = 3.0

## -- Model --
@export var model_path: String = "res://assets/models/characters/hero/friendlybee.glb"
@export var model_scale_factor: float = 0.5
@export var model_y_offset: float = 0.15

## Hover bobbing.
@export var hover_frequency: float = 5.0
@export var hover_amplitude: float = 0.08

## Rotation smoothing speed.
@export var rotation_speed: float = 12.0

@onready var hex_grid: HexGrid = %HexGrid

var current_hex: Vector2i = Vector2i.ZERO
var health: HealthScript
var _model: Node3D
var _attack_cooldown: float = 0.0
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO
var _hover_time: float = 0.0
var _target_yaw: float = 0.0

## Auto-walk state.
var _auto_walk_target_hex: Variant = null
var _auto_walk_range: int = 1
var is_auto_walking: bool = false
var _auto_walk_path: Array[Vector2i] = []
var _auto_walk_path_index: int = 0
var _auto_walk_stuck_time: float = 0.0
const AUTO_WALK_STUCK_TIMEOUT: float = 3.0

## Projectile scene.
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")
var _projectiles_container: Node3D = null

## Flash state.
var _flash_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"hero")

	_spawn_position = hex_grid.hex_to_world(Vector2i(1, 0))
	_spawn_position.y += model_y_offset
	position = _spawn_position
	current_hex = HexHelper.world3d_to_hex(position, hex_grid.hex_size)

	# Health component.
	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = max_hp
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	# Load 3D model.
	_load_model()

	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.build_walk_requested.connect(_on_build_walk_requested)
	SignalBus.restart_requested.connect(_on_restart_requested)


func _load_model() -> void:
	if model_path == "" or not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * model_scale_factor
	add_child(_model)
	HexHelper.auto_center_model(_model)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	_hover_time += delta * hover_frequency

	if _is_dead:
		if _model:
			_model.visible = false
		_respawn_timer = maxf(0.0, _respawn_timer - delta)
		if _respawn_timer <= 0.0:
			_respawn()
		return

	if _model and not _model.visible:
		_model.visible = true

	var moved_dir: Vector3 = Vector3.ZERO

	if is_auto_walking:
		var input_dir := _get_input_direction()
		if input_dir != Vector3.ZERO:
			_cancel_auto_walk()
			_apply_movement(input_dir, delta)
			moved_dir = input_dir
		else:
			moved_dir = _process_auto_walk(delta)
	else:
		var input_dir := _get_input_direction()
		if input_dir != Vector3.ZERO:
			_apply_movement(input_dir, delta)
			moved_dir = input_dir
	_update_hex_tracking()

	# Rotate model to face movement direction.
	if moved_dir.length_squared() > 0.0001:
		_target_yaw = atan2(moved_dir.x, moved_dir.z)
	if _model:
		_model.rotation.y = lerp_angle(_model.rotation.y, _target_yaw, delta * rotation_speed)
		# Hover bobbing.
		_model.position.y = sin(_hover_time) * hover_amplitude

	# Flash effect via model tint.
	if _model and _flash_timer > 0.0:
		var t: float = _flash_timer / 0.18
		_set_model_tint(Color(1.0, 1.0 - 0.55 * t, 1.0 - 0.55 * t))
	elif _model and _flash_timer <= 0.0:
		_set_model_tint(Color.WHITE)

	# Auto-attack during day.
	if DayNightManager.is_day():
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
		if _attack_cooldown <= 0.0:
			var target: Node3D = _find_nearest_enemy()
			if target != null:
				_fire_at(target)
				_attack_cooldown = 1.0 / maxf(attack_speed, 0.01)


func _get_input_direction() -> Vector3:
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.z -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.z += 1.0
	return dir.normalized()


func _apply_movement(input_dir: Vector3, delta: float) -> void:
	var move_vec := input_dir * move_speed * _speed_multiplier * delta

	var desired := position + move_vec
	desired.y = _get_ground_height(desired)
	if _is_position_walkable(desired):
		position = desired
		return

	# Wall slide: horizontal only (X).
	var h_pos := position + Vector3(move_vec.x, 0.0, 0.0)
	h_pos.y = _get_ground_height(h_pos)
	if move_vec.x != 0.0 and _is_position_walkable(h_pos):
		position = h_pos
		return

	# Wall slide: depth only (Z).
	var v_pos := position + Vector3(0.0, 0.0, move_vec.z)
	v_pos.y = _get_ground_height(v_pos)
	if move_vec.z != 0.0 and _is_position_walkable(v_pos):
		position = v_pos


func _get_ground_height(pos: Vector3) -> float:
	var hex: Vector2i = HexHelper.world3d_to_hex(pos, hex_grid.hex_size)
	var tile: HexTile = hex_grid.get_tile(hex)
	if tile:
		return float(tile.elevation) * hex_grid.elevation_height + model_y_offset
	return model_y_offset


func _is_position_walkable(pos: Vector3) -> bool:
	var hex := HexHelper.world3d_to_hex(pos, hex_grid.hex_size)
	var tile := hex_grid.get_tile(hex)
	return tile != null and tile.is_walkable()


func _update_hex_tracking() -> void:
	var position_hex := HexHelper.world3d_to_hex(position, hex_grid.hex_size)
	if position_hex != current_hex:
		var old_hex := current_hex
		current_hex = position_hex
		if is_auto_walking:
			_auto_walk_stuck_time = 0.0
		hex_changed.emit(old_hex, current_hex)


# -- Combat --

func _find_nearest_enemy() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var enemies: Array = tree.get_nodes_in_group(&"enemies")
	var best: Node3D = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var d: float = HexHelper.xz_distance(global_position, e.global_position)
		if d <= attack_range and d < best_d:
			best_d = d
			best = e as Node3D
	return best


func _fire_at(target: Node3D) -> void:
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles") as Node3D
	if _projectiles_container == null:
		return
	var p = PROJECTILE_SCENE.instantiate()
	_projectiles_container.add_child(p)
	p.team = &"player"
	p.setup(global_position + Vector3(0, 0.3, 0), target, attack_damage, 12.0)


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
	current_hex = HexHelper.world3d_to_hex(position, hex_grid.hex_size)
	if health:
		health.revive(max_hp)
	_flash_timer = 0.0
	_attack_cooldown = 0.0
	scale = Vector3(0.4, 0.4, 0.4)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector3.ONE, 0.35)
	SignalBus.hero_respawned.emit()


func _on_restart_requested() -> void:
	_is_dead = false
	_respawn_timer = 0.0
	position = _spawn_position
	current_hex = HexHelper.world3d_to_hex(position, hex_grid.hex_size)
	if health:
		health.revive(max_hp)
	scale = Vector3.ONE
	_flash_timer = 0.0
	_attack_cooldown = 0.0


func is_alive() -> bool:
	return not _is_dead


func _on_phase_changed(phase: StringName) -> void:
	_speed_multiplier = night_speed_multiplier if phase == &"night" else 1.0
	if phase == &"day" and is_auto_walking:
		_cancel_auto_walk()


# -- Auto-walk --

func _on_build_walk_requested(target_coord: Vector2i) -> void:
	if HexHelper.distance(current_hex, target_coord) <= _auto_walk_range:
		SignalBus.hero_reached_build_range.emit(target_coord)
		return
	_auto_walk_target_hex = target_coord
	is_auto_walking = true
	_auto_walk_stuck_time = 0.0
	if not _recompute_auto_walk_path():
		_cancel_auto_walk()


func _recompute_auto_walk_path() -> bool:
	if _auto_walk_target_hex == null:
		return false
	var target_hex: Vector2i = _auto_walk_target_hex as Vector2i
	var path: Array[Vector2i] = hex_grid.find_path(current_hex, target_hex, _auto_walk_range)
	if path.is_empty():
		return false
	_auto_walk_path = path
	_auto_walk_path_index = 1 if path.size() > 1 else 0
	return true


func _process_auto_walk(delta: float) -> Vector3:
	if _auto_walk_target_hex == null:
		_cancel_auto_walk()
		return Vector3.ZERO

	var target_hex: Vector2i = _auto_walk_target_hex as Vector2i

	if HexHelper.distance(current_hex, target_hex) <= _auto_walk_range:
		_finish_auto_walk()
		return Vector3.ZERO

	if _auto_walk_path.is_empty() or _auto_walk_path_index >= _auto_walk_path.size():
		if not _recompute_auto_walk_path():
			_cancel_auto_walk()
			return Vector3.ZERO

	while _auto_walk_path_index < _auto_walk_path.size() and _auto_walk_path[_auto_walk_path_index] == current_hex:
		_auto_walk_path_index += 1

	if _auto_walk_path_index >= _auto_walk_path.size():
		_auto_walk_path.clear()
		return Vector3.ZERO

	var next_hex: Vector2i = _auto_walk_path[_auto_walk_path_index]
	var next_pos: Vector3 = hex_grid.hex_to_world(next_hex)
	next_pos.y = position.y
	var dir: Vector3 = (next_pos - position)
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	_apply_movement(dir, delta)

	_auto_walk_stuck_time += delta
	if _auto_walk_stuck_time >= AUTO_WALK_STUCK_TIMEOUT:
		_auto_walk_stuck_time = 0.0
		if not _recompute_auto_walk_path():
			_cancel_auto_walk()
			return Vector3.ZERO

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


# -- Model tinting utility --

func _set_model_tint(color: Color) -> void:
	if _model == null:
		return
	_traverse_set_tint(_model, color)


func _traverse_set_tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(i)
				if mat == null:
					var orig: Material = mi.mesh.surface_get_material(i)
					if orig is StandardMaterial3D:
						mat = (orig as StandardMaterial3D).duplicate()
						mi.set_surface_override_material(i, mat)
				if mat is StandardMaterial3D:
					if color == Color.WHITE:
						mi.set_surface_override_material(i, null)
					else:
						(mat as StandardMaterial3D).albedo_color = color
	for child in node.get_children():
		_traverse_set_tint(child, color)
