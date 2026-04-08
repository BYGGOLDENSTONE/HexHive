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

## Damage flash timer (>0 = currently flashing red).
var _flash_timer: float = 0.0

## True after death — disables AI and starts fade out.
var _is_dying: bool = false

## -- Sprite & hover state --

## Cached 8-direction texture sets, keyed by sprite_dir StringName.
## Each value is a Dictionary[StringName, Texture2D] keyed by direction name.
static var _TEXTURE_CACHE: Dictionary = {}

## Direction names indexed by 45-degree sector starting at East = 0.
const DIRECTION_BY_SECTOR: Array[StringName] = [
	&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne",
]

## Sprite child node (created in _ready when sprite_dir is set).
var _sprite: Sprite2D

## Currently displayed facing direction.
var _facing: StringName = &"s"

## Hover animation phase (radians).
var _hover_time: float = 0.0

## Hover bobbing frequency (rad/s).
const HOVER_FREQUENCY: float = 5.5

## Hover amplitude in pixels (scaled by visual_size).
const HOVER_AMPLITUDE_FACTOR: float = 0.18

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

	# Sprite is created here (not in _ready) because spawners call setup()
	# AFTER add_child(), so data is already populated by this point.
	_setup_sprite()


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


## Creates the directional Sprite2D child if the data has a sprite_dir set.
## Loads (and caches) the 8-direction texture set on first use per sprite_dir.
func _setup_sprite() -> void:
	if data == null or data.sprite_dir == &"":
		return
	var textures: Dictionary = _get_or_load_textures(data.sprite_dir)
	if textures.is_empty():
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.z_index = -1
	_sprite.texture = textures[_facing]
	# Scale so the sprite roughly spans visual_size * sprite_scale_factor pixels.
	var tex_w: float = float(_sprite.texture.get_width())
	if tex_w > 0.0:
		var target_px: float = data.visual_size * 2.0 * data.sprite_scale_factor
		var s: float = target_px / tex_w
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)


static func _get_or_load_textures(sprite_dir: StringName) -> Dictionary:
	if _TEXTURE_CACHE.has(sprite_dir):
		return _TEXTURE_CACHE[sprite_dir]
	var dirs: Array[StringName] = [&"n", &"ne", &"e", &"se", &"s", &"sw", &"w", &"nw"]
	var tex_set: Dictionary = {}
	for d in dirs:
		var path: String = "res://assets/sprites/%s/%s_%s.png" % [sprite_dir, sprite_dir, d]
		if not ResourceLoader.exists(path):
			push_warning("Enemy sprite missing: %s" % path)
			continue
		tex_set[d] = load(path)
	if tex_set.is_empty():
		return {}
	_TEXTURE_CACHE[sprite_dir] = tex_set
	return tex_set


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)

	# Hover bobbing — applied to sprite local position so the entity origin
	# stays put for hex tracking and combat math.
	_hover_time += delta * HOVER_FREQUENCY
	if _sprite != null:
		var amp: float = (data.visual_size if data != null else 18.0) * HOVER_AMPLITUDE_FACTOR
		_sprite.position = Vector2(0.0, sin(_hover_time) * amp)
		if _flash_timer > 0.0:
			var t: float = _flash_timer / 0.18
			_sprite.modulate = Color(1.0, 1.0 - 0.55 * t, 1.0 - 0.55 * t, 1.0)
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

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
		# Even when attacking, face the target.
		if dist > 0.001:
			_set_facing_from_vector(to_target / dist)
	else:
		var dir: Vector2 = to_target / dist if dist > 0.001 else Vector2.ZERO
		position += dir * data.move_speed * delta
		_set_facing_from_vector(dir)
		_update_hex_tracking()


## Maps a direction vector to one of the 8 sprite directions and updates the
## sprite texture if the facing actually changed.
func _set_facing_from_vector(v: Vector2) -> void:
	if _sprite == null or v.length_squared() < 0.0001:
		return
	var deg: float = rad_to_deg(v.angle())
	deg = fposmod(deg, 360.0)
	var sector: int = int(round(deg / 45.0)) % 8
	var dir_name: StringName = DIRECTION_BY_SECTOR[sector]
	if dir_name == _facing:
		return
	_facing = dir_name
	var textures: Dictionary = _TEXTURE_CACHE.get(data.sprite_dir, {})
	if textures.has(_facing):
		_sprite.texture = textures[_facing]


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
	# Body is rendered by the directional Sprite2D child. Only the HP bar is
	# drawn here so it stays at a fixed position above the bobbing sprite.
	if health and health.current_hp < health.max_hp and not _is_dying:
		_draw_health_bar(data.visual_size)


func _draw_health_bar(size: float) -> void:
	var width: float = size * 2.0
	var height: float = 4.0
	# Place the bar above the sprite (sprite spans ~size * sprite_scale_factor).
	var y: float = -size * (data.sprite_scale_factor + 0.2)
	var bg_rect := Rect2(-width / 2.0, y, width, height)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.85))
	var frac: float = health.get_fraction()
	var fill_rect := Rect2(-width / 2.0 + 1.0, y + 1.0, (width - 2.0) * frac, height - 2.0)
	draw_rect(fill_rect, Color(0.95, 0.25, 0.2, 1.0))
