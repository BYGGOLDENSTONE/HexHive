class_name Building
extends Node3D
## A placed building on the hex grid.
## Loads its 3D model from BuildingData, or uses a procedural placeholder.
## Hosts a Health component, can attack enemies (if offensive).

const HealthScript = preload("res://scripts/combat/health.gd")

var data: Resource
var hex_coord: Vector2i
var level: int = 1
var tags: Array[StringName] = []
var health: HealthScript

var _model: Node3D
var _flash_timer: float = 0.0
var _pulse_phase: float = 0.0
var _attack_cooldown: float = 0.0
var _is_dying: bool = false
var _hex_size: float = 2.0

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")
var _projectiles_container: Node3D = null


func setup(building_data: Resource, coord: Vector2i, world_pos: Vector3, hex_size: float) -> void:
	data = building_data
	hex_coord = coord
	position = world_pos
	tags = data.tags.duplicate()
	_hex_size = hex_size

	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = data.get_max_hp(level)
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	_load_model()


func _load_model() -> void:
	if data == null or data.model_path == "":
		_create_placeholder()
		return
	if not ResourceLoader.exists(data.model_path):
		_create_placeholder()
		return
	var scene: PackedScene = load(data.model_path) as PackedScene
	if scene == null:
		_create_placeholder()
		return
	_model = scene.instantiate()
	_model.scale = data.model_scale
	add_child(_model)
	HexHelper.auto_center_model(_model)


func _create_placeholder() -> void:
	# Simple colored cylinder as placeholder for buildings without models.
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = _hex_size * 0.6
	mesh.bottom_radius = _hex_size * 0.7
	mesh.height = _hex_size * 0.5
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	if data:
		match data.id:
			&"hive":
				mat.albedo_color = Color(0.95, 0.75, 0.2)
				mesh.height = _hex_size * 0.8
			&"wall":
				mat.albedo_color = Color(0.65, 0.5, 0.25)
				mesh.height = _hex_size * 0.6
			&"flower_garden":
				mat.albedo_color = Color(0.4, 0.7, 0.3)
				mesh.height = _hex_size * 0.2
			_:
				mat.albedo_color = Color(0.8, 0.8, 0.8)
	mi.set_surface_override_material(0, mat)
	mi.position.y = mesh.height * 0.5
	_model = mi
	add_child(_model)


func _process(delta: float) -> void:
	if _is_dying:
		return
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	if _model and _flash_timer > 0.0:
		var t: float = _flash_timer / 0.18
		_set_model_emission(Color(1.0, 0.3, 0.2) * t * 0.5)
	elif _model:
		_set_model_emission(Color.BLACK)


func _physics_process(delta: float) -> void:
	if _is_dying or data == null:
		return
	if data.is_offensive() and DayNightManager.is_day():
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
		if _attack_cooldown <= 0.0:
			var target: Node3D = _find_nearest_enemy_in_range()
			if target != null:
				_fire_projectile_at(target)
				_attack_cooldown = 1.0 / maxf(data.get_attack_speed(level), 0.01)


func _find_nearest_enemy_in_range() -> Node3D:
	var range_wu: float = data.get_attack_range(level)
	if range_wu <= 0.0:
		return null
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
		if d <= range_wu and d < best_d:
			best_d = d
			best = e as Node3D
	return best


func _fire_projectile_at(target: Node3D) -> void:
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles") as Node3D
	if _projectiles_container == null:
		return
	var p = PROJECTILE_SCENE.instantiate()
	_projectiles_container.add_child(p)
	p.team = &"player"
	p.setup(global_position + Vector3(0, 0.5, 0), target, data.get_attack_damage(level), 11.0)


func take_damage(amount: float) -> void:
	if health == null or _is_dying:
		return
	health.take_damage(amount)


func _on_damaged(amount: float, current: float, maximum: float) -> void:
	_flash_timer = 0.18
	SignalBus.building_damaged.emit(self, amount)
	if data.id == &"hive":
		SignalBus.hive_damaged.emit(amount, current, maximum)


func _on_died() -> void:
	if _is_dying:
		return
	_is_dying = true
	if data.id == &"hive":
		SignalBus.hive_destroyed.emit()
	else:
		SignalBus.building_destroyed.emit(self, hex_coord)
	_play_death()


func _play_death() -> void:
	var hex_grid_node: HexGrid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	if hex_grid_node:
		hex_grid_node.remove_building(hex_coord)

	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.35)
	if data.id == &"hive":
		await tw.finished
		visible = false
	else:
		await tw.finished
		queue_free()


func upgrade() -> bool:
	if level >= data.max_level:
		return false
	level += 1
	if health:
		health.set_max_hp(data.get_max_hp(level), false)
		health.heal(data.get_max_hp(level))
	_play_upgrade_effect()
	return true


func _play_upgrade_effect() -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector3(1.25, 1.25, 1.25), 0.15)
	tw.tween_property(self, "scale", Vector3.ONE, 0.2)


func play_place_effect() -> void:
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector3.ONE, 0.35)


func refresh_sprite() -> void:
	# Kept for API compat, rebuilds model.
	if _model:
		_model.queue_free()
		_model = null
	_load_model()


# -- Scale editor support --

func update_model_scale(s: Vector3) -> void:
	if _model == null or data == null or data.model_path == "":
		return
	_model.scale = s
	HexHelper.auto_center_model(_model)


func update_model_y_offset(y: float) -> void:
	if _model == null or data == null or data.model_path == "":
		return
	HexHelper.auto_center_model(_model)
	_model.position.y += y


func _set_model_emission(color: Color) -> void:
	if _model == null:
		return
	_traverse_emission(_model, color)


func _traverse_emission(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					if color == Color.BLACK:
						sm.emission_enabled = false
					else:
						sm.emission = color
						sm.emission_enabled = true
	for child in node.get_children():
		_traverse_emission(child, color)
