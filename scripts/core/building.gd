class_name Building
extends Node2D
## A placed building on the hex grid.
## Renders itself using procedural _draw() based on BuildingData and current level.
## Hosts a Health component, can attack enemies (if offensive), and emits damage signals.

const HealthScript = preload("res://scripts/combat/health.gd")
const ProjectileScript = preload("res://scripts/combat/projectile.gd")

## The building type definition.
var data: Resource

## Axial coordinate of the tile this building occupies.
var hex_coord: Vector2i

## Current upgrade level (starts at 1).
var level: int = 1

## Runtime tags copied from data (can be modified by buffs/upgrades).
var tags: Array[StringName] = []

## Health component child.
var health: HealthScript

## Draw size (set during setup based on hex grid size).
var _draw_size: float = 0.0

## Damage flash timer.
var _flash_timer: float = 0.0

## Pulse timer for low-HP Hive warning.
var _pulse_phase: float = 0.0

## Cached attack cooldown (for offensive buildings).
var _attack_cooldown: float = 0.0

## Cached projectile scene.
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

## Reference to the projectiles container (resolved lazily).
var _projectiles_container: Node2D = null

## True after death — disables further updates.
var _is_dying: bool = false

## Optional static Sprite2D child (created when data.sprite_path is set).
var _sprite: Sprite2D


## Initialize the building with its data, coordinate, and position.
func setup(building_data: Resource, coord: Vector2i, world_pos: Vector2, hex_size: float) -> void:
	data = building_data
	hex_coord = coord
	position = world_pos
	tags = data.tags.duplicate()
	_draw_size = hex_size
	z_index = -1

	# Set up health component.
	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = data.get_max_hp(level)
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	# If this building has a static sprite, instantiate it now so the
	# procedural _draw body can be skipped.
	_setup_sprite()


## Creates a static Sprite2D child if data.sprite_path is set.
## Scale and offset are driven by data.sprite_scale and data.sprite_offset,
## editable via the Sprite Placement Editor (tools/sprite_editor.tscn).
func _setup_sprite() -> void:
	if data == null or data.sprite_path == "":
		return
	if not ResourceLoader.exists(data.sprite_path):
		push_warning("Building sprite missing: %s" % data.sprite_path)
		return
	var tex: Texture2D = load(data.sprite_path) as Texture2D
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = tex
	_sprite.z_as_relative = false
	_sprite.z_index = 10
	var tex_w: float = float(tex.get_width())
	if tex_w <= 0.0:
		return
	var hex_width: float = sqrt(3.0) * _draw_size
	var base_s: float = hex_width / tex_w
	_sprite.scale = Vector2(base_s * data.sprite_scale.x, base_s * data.sprite_scale.y)
	_sprite.position = data.sprite_offset
	add_child(_sprite)


func _process(delta: float) -> void:
	if _is_dying:
		return
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		queue_redraw()

	# Sprite-based buildings: tint via modulate so the flash matches the
	# rendered art instead of being a flat hex overlay.
	if _sprite != null:
		if _flash_timer > 0.0:
			var t: float = _flash_timer / 0.18
			_sprite.modulate = Color(1.0, 1.0 - 0.55 * t, 1.0 - 0.55 * t, 1.0)
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Hive low-HP warning pulse.
	if data != null and data.id == &"hive" and health != null and health.get_fraction() < 0.5:
		_pulse_phase += delta * 4.0
		queue_redraw()


func _physics_process(delta: float) -> void:
	if _is_dying or data == null:
		return
	# Offensive turret logic.
	if data.is_offensive() and DayNightManager.is_day():
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
		if _attack_cooldown <= 0.0:
			var target: Node2D = _find_nearest_enemy_in_range()
			if target != null:
				_fire_projectile_at(target)
				_attack_cooldown = 1.0 / maxf(data.get_attack_speed(level), 0.01)


# -- Combat --------------------------------------------------------------------

func _find_nearest_enemy_in_range() -> Node2D:
	var range_px: float = data.get_attack_range(level)
	if range_px <= 0.0:
		return null
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
		if d <= range_px and d < best_d:
			best_d = d
			best = e
	return best


func _fire_projectile_at(target: Node2D) -> void:
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles") as Node2D
	if _projectiles_container == null:
		return
	var p: ProjectileScript = PROJECTILE_SCENE.instantiate() as ProjectileScript
	_projectiles_container.add_child(p)
	p.team = &"player"
	p.setup(global_position + Vector2(0.0, -_draw_size * 0.55), target, data.get_attack_damage(level), 540.0)


## External damage entry-point used by enemies.
func take_damage(amount: float) -> void:
	if health == null or _is_dying:
		return
	health.take_damage(amount)


func _on_damaged(amount: float, current: float, maximum: float) -> void:
	_flash_timer = 0.18
	queue_redraw()
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
	var hex_grid: HexGrid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	if hex_grid != null:
		hex_grid.remove_building(hex_coord)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_property(self, "rotation", randf_range(-0.4, 0.4), 0.35)
	# Hive lingers for game over screen — others queue free.
	if data.id == &"hive":
		await tw.finished
		visible = false
	else:
		await tw.finished
		queue_free()


## Upgrade the building to the next level. Returns true if successful.
func upgrade() -> bool:
	if level >= data.max_level:
		return false
	level += 1
	# Heal to new max on upgrade.
	if health != null:
		health.set_max_hp(data.get_max_hp(level), false)
		health.heal(data.get_max_hp(level))
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

	# Hive low-HP red pulse modifier.
	if data.id == &"hive" and health != null and health.get_fraction() < 0.5:
		var t: float = (sin(_pulse_phase) + 1.0) * 0.5
		base_color = base_color.lerp(Color(1.0, 0.3, 0.2), t * 0.45)

	# When a static sprite is in use, skip the procedural body — only the
	# overlays (flash, HP bar) are drawn here. Sprite flash is applied via
	# modulate in _process.
	if _sprite == null:
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

		# Damage flash overlay (procedural buildings only).
		if _flash_timer > 0.0:
			var alpha: float = (_flash_timer / 0.18) * 0.5
			var corners := HexHelper.get_hex_corners(Vector2.ZERO, _draw_size)
			draw_colored_polygon(corners, Color(1.0, 0.4, 0.3, alpha))

	# Damaged buildings show a small HP bar (Hive uses dedicated HUD bar instead).
	if health != null and health.current_hp < health.max_hp and not _is_dying and data.id != &"hive":
		_draw_hp_bar()


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

	# Damage cracks based on HP fraction.
	if health != null:
		var frac: float = health.get_fraction()
		if frac < 0.66:
			_draw_crack(Vector2(-s * 0.3, -s * 0.4), Vector2(s * 0.1, s * 0.1), accent.darkened(0.5))
		if frac < 0.33:
			_draw_crack(Vector2(s * 0.4, -s * 0.2), Vector2(-s * 0.1, s * 0.4), accent.darkened(0.6))
			_draw_crack(Vector2(-s * 0.1, s * 0.3), Vector2(s * 0.3, -s * 0.1), accent.darkened(0.6))

	# Outline
	_draw_hex_outline(outer, accent.darkened(0.3), 3.0)


func _draw_crack(start: Vector2, end: Vector2, color: Color) -> void:
	var mid: Vector2 = start.lerp(end, 0.5) + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	draw_line(start, mid, color, 2.0, true)
	draw_line(mid, end, color, 2.0, true)


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


func _draw_hp_bar() -> void:
	var width: float = _draw_size * 1.2
	var height: float = 4.5
	var y: float = -_draw_size * 1.05
	var bg_rect := Rect2(-width / 2.0, y, width, height)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.85))
	var frac: float = health.get_fraction()
	var fill_rect := Rect2(-width / 2.0 + 1.0, y + 1.0, (width - 2.0) * frac, height - 2.0)
	var col: Color = Color(0.3, 0.85, 0.35, 1.0) if frac > 0.5 else (Color(0.95, 0.85, 0.3, 1.0) if frac > 0.25 else Color(0.95, 0.3, 0.25, 1.0))
	draw_rect(fill_rect, col)


func _play_upgrade_effect() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.15)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)


## Rebuild the Sprite2D child using current data.sprite_scale / sprite_offset.
## Called by the Sprite Editor to apply live changes.
func refresh_sprite() -> void:
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null
	_setup_sprite()
	queue_redraw()


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
