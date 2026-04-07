class_name Enemy
extends Node2D
## Runtime enemy entity. Moves toward the Hive, attacks obstacles in its path,
## and opportunistically engages the hero or turrets that come into range.

const HealthScript = preload("res://scripts/combat/health.gd")

## Emitted when the enemy dies (after death animation finishes).
signal died_finished()

## Enemy data resource (stats, visuals, tags).
var data: Resource

## Health component child.
var health: HealthScript

## Reference to the hex grid (set by spawner).
var hex_grid: HexGrid

## Current target Node2D (Hive, wall, turret, or hero).
var current_target: Node2D = null

## Time until next retarget evaluation.
var _retarget_timer: float = 0.0

## Cooldown until next attack.
var _attack_cooldown: float = 0.0

## Time alive — used to delay AI start so the spawn animation can play.
var _age: float = 0.0

## Wing flap phase for visual animation.
var _wing_phase: float = 0.0

## Damage flash timer (>0 = currently flashing red).
var _flash_timer: float = 0.0

## Recent attack lunge offset (decays each frame, drives a small forward jab).
var _attack_lunge: float = 0.0

## True after death — disables AI and starts fade out.
var _is_dying: bool = false

## Current axial coordinate (cached for retarget queries).
var _current_hex: Vector2i = Vector2i.ZERO

## Cached Hive node — found on first retarget.
var _hive_node: Node2D = null

## Hex distance at which the enemy notices opportunity threats.
const OPPORTUNITY_HEX_RANGE: int = 1

## Retarget interval in seconds.
const RETARGET_INTERVAL: float = 0.35


## Initialise the enemy with its data and the hex grid reference.
func setup(enemy_data: Resource, grid: HexGrid, world_pos: Vector2) -> void:
	data = enemy_data
	hex_grid = grid
	position = world_pos
	z_index = 5

	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = data.max_hp
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _ready() -> void:
	add_to_group(&"enemies")
	# Spawn animation: pop in
	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)


func _process(delta: float) -> void:
	_wing_phase += delta * 22.0
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
	if _attack_lunge > 0.0:
		_attack_lunge = maxf(0.0, _attack_lunge - delta * 6.0)
	queue_redraw()


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

	var to_target: Vector2 = current_target.global_position - global_position
	var dist: float = to_target.length()

	if dist <= data.attack_range:
		_try_attack(delta)
	else:
		var dir: Vector2 = to_target / dist if dist > 0.001 else Vector2.ZERO
		position += dir * data.move_speed * delta
		_update_hex_tracking()


func _update_hex_tracking() -> void:
	var hex: Vector2i = HexHelper.pixel_to_hex(position, hex_grid.hex_size)
	if hex != _current_hex:
		_current_hex = hex


# -- Targeting -----------------------------------------------------------------

func _retarget() -> void:
	if hex_grid == null:
		return

	# Cache the Hive once.
	if _hive_node == null:
		_hive_node = hex_grid.get_building_at(Vector2i.ZERO) as Node2D

	_current_hex = HexHelper.pixel_to_hex(position, hex_grid.hex_size)

	# 1) Opportunity threats — hero or any building within OPPORTUNITY_HEX_RANGE.
	var best_threat: Node2D = null
	var best_threat_dist: float = INF

	var hero: Node2D = _get_hero()
	if hero != null and not _hero_is_dead(hero):
		var hero_hex: Vector2i = HexHelper.pixel_to_hex(hero.global_position, hex_grid.hex_size)
		if HexHelper.distance(_current_hex, hero_hex) <= OPPORTUNITY_HEX_RANGE:
			var d: float = global_position.distance_to(hero.global_position)
			if d < best_threat_dist:
				best_threat_dist = d
				best_threat = hero

	if best_threat != null:
		current_target = best_threat
		return

	# 2) Obstacle directly in path to the Hive.
	var path: Array[Vector2i] = HexHelper.get_line(_current_hex, Vector2i.ZERO)
	for hex in path:
		if hex == _current_hex:
			continue
		var tile: HexTile = hex_grid.get_tile(hex)
		if tile == null:
			continue
		if tile.has_building and tile.building != null:
			current_target = tile.building as Node2D
			return

	# 3) Default — head straight for the Hive.
	if _hive_node != null and is_instance_valid(_hive_node):
		current_target = _hive_node


func _get_hero() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes: Array = tree.get_nodes_in_group(&"hero")
	if nodes.size() > 0:
		return nodes[0] as Node2D
	return null


func _hero_is_dead(hero: Node2D) -> bool:
	if hero.has_method("is_alive"):
		return not hero.is_alive()
	return false


# -- Combat --------------------------------------------------------------------

func _try_attack(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	if current_target.has_method("take_damage"):
		current_target.take_damage(data.attack_damage)
		_attack_lunge = 1.0
		_attack_cooldown = 1.0 / maxf(data.attack_speed, 0.01)


## Public damage entry-point used by hero/turret projectiles.
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
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector2(1.4, 1.4), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.tween_property(self, "rotation", randf_range(-0.6, 0.6), 0.28)
	await tw.finished
	died_finished.emit()
	queue_free()


## Used by hero/turrets to know whether to shoot at this enemy.
func is_alive() -> bool:
	return not _is_dying and health != null and not health.is_dead


# -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return

	var size: float = data.visual_size
	var lunge: Vector2 = Vector2(0.0, -size * 0.18 * _attack_lunge)
	var flap: float = sin(_wing_phase) * 0.35

	# Wings — two semi-transparent ellipses behind the body.
	_draw_wing(Vector2(-size * 0.55, -size * 0.1) + lunge, size * 0.85, size * 0.45, flap, true)
	_draw_wing(Vector2(size * 0.55, -size * 0.1) + lunge, size * 0.85, size * 0.45, -flap, false)

	# Body composed of 3 ellipsoid segments: abdomen, thorax, head.
	var abdomen_pos: Vector2 = Vector2(0.0, size * 0.55) + lunge
	var thorax_pos: Vector2 = Vector2(0.0, size * 0.05) + lunge
	var head_pos: Vector2 = Vector2(0.0, -size * 0.5) + lunge

	# Abdomen with stripes.
	_draw_ellipse(abdomen_pos, size * 0.55, size * 0.7, data.body_color)
	_draw_ellipse_outline(abdomen_pos, size * 0.55, size * 0.7, data.accent_color.darkened(0.1), 2.0)
	# Stripes on abdomen
	for i in range(3):
		var stripe_y: float = abdomen_pos.y - size * 0.35 + i * size * 0.32
		var stripe_w: float = size * 0.5 - i * size * 0.05
		draw_rect(Rect2(-stripe_w, stripe_y, stripe_w * 2.0, size * 0.13), data.accent_color)

	# Stinger — sharp triangle at the bottom.
	var stinger_base: Vector2 = abdomen_pos + Vector2(0.0, size * 0.65)
	var stinger_tip: Vector2 = stinger_base + Vector2(0.0, size * 0.4)
	var stinger_l: Vector2 = stinger_base + Vector2(-size * 0.12, 0.0)
	var stinger_r: Vector2 = stinger_base + Vector2(size * 0.12, 0.0)
	draw_colored_polygon(PackedVector2Array([stinger_tip, stinger_l, stinger_r]), data.accent_color.darkened(0.2))
	draw_line(stinger_l, stinger_tip, data.accent_color.darkened(0.5), 1.5, true)
	draw_line(stinger_r, stinger_tip, data.accent_color.darkened(0.5), 1.5, true)

	# Thorax — smaller fuzzy ellipse.
	_draw_ellipse(thorax_pos, size * 0.5, size * 0.45, data.body_color.darkened(0.05))
	_draw_ellipse_outline(thorax_pos, size * 0.5, size * 0.45, data.accent_color.darkened(0.1), 1.8)

	# Head — round, with eyes and antennae.
	_draw_ellipse(head_pos, size * 0.4, size * 0.4, data.body_color.darkened(0.1))
	_draw_ellipse_outline(head_pos, size * 0.4, size * 0.4, data.accent_color.darkened(0.1), 1.6)

	# Eyes — two glowing circles.
	var eye_off: float = size * 0.18
	var eye_r: float = size * 0.11
	draw_circle(head_pos + Vector2(-eye_off, -size * 0.05), eye_r, data.accent_color.darkened(0.4))
	draw_circle(head_pos + Vector2(eye_off, -size * 0.05), eye_r, data.accent_color.darkened(0.4))
	draw_circle(head_pos + Vector2(-eye_off, -size * 0.05), eye_r * 0.55, data.eye_color)
	draw_circle(head_pos + Vector2(eye_off, -size * 0.05), eye_r * 0.55, data.eye_color)
	# Eye highlights
	draw_circle(head_pos + Vector2(-eye_off + size * 0.03, -size * 0.08), eye_r * 0.18, Color(1.0, 1.0, 1.0, 0.85))
	draw_circle(head_pos + Vector2(eye_off + size * 0.03, -size * 0.08), eye_r * 0.18, Color(1.0, 1.0, 1.0, 0.85))

	# Antennae.
	var ant_base_l: Vector2 = head_pos + Vector2(-size * 0.18, -size * 0.32)
	var ant_base_r: Vector2 = head_pos + Vector2(size * 0.18, -size * 0.32)
	var ant_tip_l: Vector2 = ant_base_l + Vector2(-size * 0.25, -size * 0.4)
	var ant_tip_r: Vector2 = ant_base_r + Vector2(size * 0.25, -size * 0.4)
	draw_line(ant_base_l, ant_tip_l, data.accent_color, 2.0, true)
	draw_line(ant_base_r, ant_tip_r, data.accent_color, 2.0, true)
	draw_circle(ant_tip_l, size * 0.07, data.accent_color)
	draw_circle(ant_tip_r, size * 0.07, data.accent_color)

	# Damage flash overlay — bright red wash.
	if _flash_timer > 0.0:
		var alpha: float = (_flash_timer / 0.18) * 0.55
		var flash_color := Color(1.0, 0.3, 0.2, alpha)
		_draw_ellipse(thorax_pos, size * 0.7, size * 0.95, flash_color)

	# Health bar (only when damaged).
	if health and health.current_hp < health.max_hp and not _is_dying:
		_draw_health_bar(size)


func _draw_wing(center: Vector2, w: float, h: float, tilt: float, left_side: bool) -> void:
	var pts := PackedVector2Array()
	var seg: int = 16
	var side_sign: float = -1.0 if left_side else 1.0
	for i in range(seg):
		var t: float = TAU * i / seg
		var x: float = cos(t) * w + side_sign * h * tilt * 0.5
		var y: float = sin(t) * h + (cos(t) * tilt * h * 0.6)
		pts.append(center + Vector2(x, y))
	draw_colored_polygon(pts, data.wing_color)
	# Wing veins
	var vein_color := Color(data.accent_color.r, data.accent_color.g, data.accent_color.b, 0.4)
	for i in range(seg):
		var next: int = (i + 1) % seg
		draw_line(pts[i], pts[next], vein_color, 1.0, true)


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var seg: int = 18
	for i in range(seg):
		var t: float = TAU * i / seg
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	draw_colored_polygon(pts, color)


func _draw_ellipse_outline(center: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var seg: int = 18
	for i in range(seg):
		var t1: float = TAU * i / seg
		var t2: float = TAU * (i + 1) / seg
		var p1: Vector2 = center + Vector2(cos(t1) * rx, sin(t1) * ry)
		var p2: Vector2 = center + Vector2(cos(t2) * rx, sin(t2) * ry)
		draw_line(p1, p2, color, width, true)


func _draw_health_bar(size: float) -> void:
	var width: float = size * 1.6
	var height: float = 4.0
	var y: float = -size * 1.4
	var bg_rect := Rect2(-width / 2.0, y, width, height)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.85))
	var frac: float = health.get_fraction()
	var fill_rect := Rect2(-width / 2.0 + 1.0, y + 1.0, (width - 2.0) * frac, height - 2.0)
	draw_rect(fill_rect, Color(0.95, 0.25, 0.2, 1.0))
