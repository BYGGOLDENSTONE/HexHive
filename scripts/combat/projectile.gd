class_name Projectile
extends Node3D
## Honey-drop projectile in 3D. Travels toward target with light homing.
## On impact deals damage and disappears.

const DamageTableScript = preload("res://scripts/combat/damage_table.gd")

var team: StringName = &"player"
var target: Node3D = null
var damage: float = 10.0
var speed: float = 22.0
var lifetime: float = 3.0
var homing: bool = true

## Attacker tags used by the tag-based damage pipeline.
## Filled at spawn time by hero/turret callers (e.g. [&"ranged", &"honey"]).
var attacker_tags: Array[StringName] = [&"ranged"]

var _velocity: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _hit: bool = false
var _mesh: MeshInstance3D


func setup(spawn_pos: Vector3, target_node: Node3D, dmg: float, projectile_speed: float = 22.0) -> void:
	position = spawn_pos
	target = target_node
	damage = dmg
	speed = projectile_speed
	if target:
		_direction = (target.global_position - spawn_pos).normalized()
	_velocity = _direction * speed


func _ready() -> void:
	# Create visual — glowing sphere.
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if _hit:
		return

	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	# Light homing.
	if homing and target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		var desired: Vector3 = (target.global_position - global_position).normalized()
		_direction = _direction.lerp(desired, 0.18).normalized()
		_velocity = _direction * speed
	elif target == null or not is_instance_valid(target):
		pass

	position += _velocity * delta

	# Hit detection.
	if target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		var dist: float = global_position.distance_to(target.global_position)
		if dist <= 0.8:
			_apply_hit()


func _apply_hit() -> void:
	if _hit:
		return
	_hit = true
	if target != null and is_instance_valid(target) and target.has_method("take_damage"):
		# Apply tag-based modifiers if the target has tags.
		var final_dmg: float = damage
		var target_tags: Array = []
		if "tags" in target:
			for t in target.tags:
				target_tags.append(String(t))
		elif target.has_method("get") and target.get("data") != null and "tags" in target.data:
			for t in target.data.tags:
				target_tags.append(String(t))
		if not target_tags.is_empty():
			var atk_tags: Array = []
			for t in attacker_tags:
				atk_tags.append(String(t))
			final_dmg = DamageTableScript.compute(damage, atk_tags, target_tags)
		target.take_damage(final_dmg)
	_play_impact()


func _play_impact() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector3(2.5, 2.5, 2.5), 0.18)
	await tw.finished
	queue_free()
