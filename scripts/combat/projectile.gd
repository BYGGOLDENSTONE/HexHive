class_name Projectile
extends Node2D
## Honey-drop projectile fired by hero or turrets at enemies.
## Travels in a straight line toward the target's last known position.
## On impact (or distance threshold) deals damage and dies with a splash effect.

## Owner team (&"player" hits enemies; &"enemy" reserved for future enemy projectiles).
var team: StringName = &"player"

## Target node — projectile updates aim each frame for light homing feel.
var target: Node2D = null

## Damage applied on hit.
var damage: float = 10.0

## Travel speed in pixels per second.
var speed: float = 520.0

## Maximum lifetime in seconds.
var lifetime: float = 2.0

## Visual radius (drives glow size).
var visual_size: float = 6.0

## Whether to lightly track the target each frame (slight homing).
var homing: bool = true

## Cached velocity vector when target is lost.
var _velocity: Vector2 = Vector2.ZERO

## Time since spawn.
var _age: float = 0.0

## True after impact — drives the splash fade-out.
var _hit: bool = false

## Trail points for the comet-like glow tail.
var _trail: PackedVector2Array = PackedVector2Array()

## Cached travel direction for visuals.
var _direction: Vector2 = Vector2.UP


## Initialise and aim the projectile.
func setup(spawn_pos: Vector2, target_node: Node2D, dmg: float, projectile_speed: float = 520.0) -> void:
	position = spawn_pos
	target = target_node
	damage = dmg
	speed = projectile_speed
	z_index = 6
	if target:
		_direction = (target.global_position - spawn_pos).normalized()
	_velocity = _direction * speed


func _physics_process(delta: float) -> void:
	if _hit:
		return

	_age += delta
	if _age >= lifetime:
		_destroy()
		return

	# Light homing — re-aim toward target if still alive.
	if homing and target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		var desired: Vector2 = (target.global_position - global_position).normalized()
		_direction = _direction.lerp(desired, 0.18).normalized()
		_velocity = _direction * speed
	elif target == null or not is_instance_valid(target):
		# Target gone — keep flying straight.
		pass

	position += _velocity * delta

	# Trail capture
	_trail.append(position)
	if _trail.size() > 8:
		_trail.remove_at(0)

	# Hit detection — circle around current position.
	if target != null and is_instance_valid(target) and target.has_method("is_alive") and target.is_alive():
		var dist: float = global_position.distance_to(target.global_position)
		if dist <= visual_size * 2.0 + 8.0:
			_apply_hit()


func _process(_delta: float) -> void:
	queue_redraw()


func _apply_hit() -> void:
	if _hit:
		return
	_hit = true
	if target != null and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(damage)
	_play_impact()


func _play_impact() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector2(2.2, 2.2), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.22)
	await tw.finished
	queue_free()


func _destroy() -> void:
	queue_free()


func _draw() -> void:
	# Trail — soft glow line.
	if _trail.size() >= 2:
		for i in range(_trail.size() - 1):
			var t: float = float(i) / float(_trail.size())
			var alpha: float = t * 0.55
			var thickness: float = visual_size * (0.4 + t * 1.0)
			var p1: Vector2 = _trail[i] - global_position
			var p2: Vector2 = _trail[i + 1] - global_position
			draw_line(p1, p2, Color(1.0, 0.85, 0.3, alpha), thickness, true)

	# Outer glow
	draw_circle(Vector2.ZERO, visual_size * 1.8, Color(1.0, 0.85, 0.3, 0.25))
	# Mid glow
	draw_circle(Vector2.ZERO, visual_size * 1.2, Color(1.0, 0.9, 0.4, 0.55))
	# Core honey drop
	draw_circle(Vector2.ZERO, visual_size, Color(1.0, 0.95, 0.6, 1.0))
	# Bright highlight
	draw_circle(Vector2(-visual_size * 0.25, -visual_size * 0.3), visual_size * 0.35, Color(1.0, 1.0, 0.85, 0.9))
