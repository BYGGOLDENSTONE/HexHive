class_name Enemy
extends Node3D
## Runtime enemy entity. Moves toward the Hive in 3D space, attacks obstacles,
## and opportunistically engages the hero or turrets in range.

const HealthScript = preload("res://scripts/combat/health.gd")

signal died_finished()

var data: Resource
var health: HealthScript
var hex_grid: HexGrid
var current_target: Node3D = null

var _retarget_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _age: float = 0.0
var _flash_timer: float = 0.0
var _is_dying: bool = false

## 3D model child.
var _model: Node3D

## Base Y offset of the model after auto-centering.
var _base_model_y: float = 0.0

## Hover animation.
var _hover_time: float = 0.0
const HOVER_FREQUENCY: float = 5.5
const HOVER_AMPLITUDE: float = 0.12

## Rotation smoothing.
var _target_yaw: float = 0.0
const ROTATION_SPEED: float = 10.0

## Current hex (cached for retarget queries).
var _current_hex: Vector2i = Vector2i.ZERO
var _hive_node: Node3D = null

const OPPORTUNITY_HEX_RANGE: int = 1
const RETARGET_INTERVAL: float = 0.35


func setup(enemy_data: Resource, grid: HexGrid, world_pos: Vector3) -> void:
	data = enemy_data
	hex_grid = grid
	position = world_pos

	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = data.max_hp
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	_load_model()


func _load_model() -> void:
	if data == null or data.model_path == "" or not ResourceLoader.exists(data.model_path):
		return
	var scene: PackedScene = load(data.model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * data.model_scale
	add_child(_model)
	HexHelper.auto_center_model(_model)
	_base_model_y = _model.position.y

	# Apply material tint if specified (e.g. hornet's crimson).
	if data.material_tint != Color.WHITE:
		_apply_material_tint(_model, data.material_tint)


func _apply_material_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var orig: Material = mi.mesh.surface_get_material(i)
				if orig is StandardMaterial3D:
					var mat: StandardMaterial3D = (orig as StandardMaterial3D).duplicate()
					mat.albedo_color = mat.albedo_color * tint
					mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_tint(child, tint)


func _ready() -> void:
	add_to_group(&"enemies")
	# Spawn animation: scale from zero.
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector3.ONE, 0.3)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	_hover_time += delta * HOVER_FREQUENCY
	if _model:
		_model.position.y = _base_model_y + sin(_hover_time) * HOVER_AMPLITUDE
		if _flash_timer > 0.0:
			var t: float = _flash_timer / 0.18
			_set_flash_tint(Color(1.0, 1.0 - 0.55 * t, 1.0 - 0.55 * t))
		else:
			_clear_flash_tint()


func _physics_process(delta: float) -> void:
	if _is_dying or data == null or hex_grid == null:
		return
	_age += delta
	if _age < data.spawn_delay:
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or current_target == null or not is_instance_valid(current_target):
		_retarget()
		_retarget_timer = RETARGET_INTERVAL

	if current_target == null or not is_instance_valid(current_target):
		return

	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()

	if dist <= data.attack_range:
		_try_attack(delta)
		if dist > 0.001:
			_target_yaw = atan2(-to_target.x, -to_target.z)
	else:
		var dir: Vector3 = to_target / dist if dist > 0.001 else Vector3.ZERO
		position += dir * data.move_speed * delta
		# Update Y to match ground.
		var hex: Vector2i = HexHelper.world3d_to_hex(position, hex_grid.hex_size)
		var tile: HexTile = hex_grid.get_tile(hex)
		if tile:
			position.y = float(tile.elevation) * hex_grid.elevation_height
		_target_yaw = atan2(-dir.x, -dir.z)
		_update_hex_tracking()

	if _model:
		_model.rotation.y = lerp_angle(_model.rotation.y, _target_yaw, delta * ROTATION_SPEED)


func _update_hex_tracking() -> void:
	var hex: Vector2i = HexHelper.world3d_to_hex(position, hex_grid.hex_size)
	if hex != _current_hex:
		_current_hex = hex


# -- Targeting --

func _retarget() -> void:
	if hex_grid == null:
		return
	if _hive_node == null:
		_hive_node = hex_grid.get_building_at(Vector2i.ZERO) as Node3D

	_current_hex = HexHelper.world3d_to_hex(position, hex_grid.hex_size)

	# 1) Opportunity threats.
	var hero: Node3D = _get_hero()
	if hero != null and not _hero_is_dead(hero):
		var hero_hex: Vector2i = HexHelper.world3d_to_hex(hero.global_position, hex_grid.hex_size)
		if HexHelper.distance(_current_hex, hero_hex) <= OPPORTUNITY_HEX_RANGE:
			current_target = hero
			return

	# 2) Obstacle in path to Hive.
	var path: Array[Vector2i] = HexHelper.get_line(_current_hex, Vector2i.ZERO)
	for hex in path:
		if hex == _current_hex:
			continue
		var tile: HexTile = hex_grid.get_tile(hex)
		if tile == null:
			continue
		if tile.has_building and tile.building != null:
			current_target = tile.building as Node3D
			return

	# 3) Default — Hive.
	if _hive_node != null and is_instance_valid(_hive_node):
		current_target = _hive_node


func _get_hero() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes: Array = tree.get_nodes_in_group(&"hero")
	if nodes.size() > 0:
		return nodes[0] as Node3D
	return null


func _hero_is_dead(hero: Node3D) -> bool:
	if hero.has_method("is_alive"):
		return not hero.is_alive()
	return false


# -- Combat --

func _try_attack(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	if current_target.has_method("take_damage"):
		current_target.take_damage(data.attack_damage)
		_attack_cooldown = 1.0 / maxf(data.attack_speed, 0.01)


func take_damage(amount: float) -> void:
	if health == null:
		return
	health.take_damage(amount)


func _on_damaged(amount: float, _current: float, _maximum: float) -> void:
	_flash_timer = 0.18
	SignalBus.enemy_damaged.emit(self, amount)


func _on_died() -> void:
	if _is_dying:
		return
	_is_dying = true
	SignalBus.enemy_died.emit(self)
	_play_death()


func _play_death() -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector3(1.4, 1.4, 1.4), 0.18)
	await tw.finished
	died_finished.emit()
	queue_free()


func is_alive() -> bool:
	return not _is_dying and health != null and not health.is_dead


# -- Scale editor support --

func update_model_scale(s: float) -> void:
	if _model:
		_model.scale = Vector3.ONE * s
		HexHelper.auto_center_model(_model)
		_base_model_y = _model.position.y


func update_model_y_offset(y: float) -> void:
	if _model:
		HexHelper.auto_center_model(_model)
		_base_model_y = _model.position.y + y


# -- Flash tinting --

var _flash_overrides: Array[Dictionary] = []

func _set_flash_tint(color: Color) -> void:
	if _model == null:
		return
	_traverse_flash(_model, color)


func _clear_flash_tint() -> void:
	if _model == null:
		return
	_traverse_clear_flash(_model)


func _traverse_flash(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).emission = color * 0.5
					(mat as StandardMaterial3D).emission_enabled = true
	for child in node.get_children():
		_traverse_flash(child, color)


func _traverse_clear_flash(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).emission_enabled = false
	for child in node.get_children():
		_traverse_clear_flash(child)
