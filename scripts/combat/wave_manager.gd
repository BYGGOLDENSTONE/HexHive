class_name WaveManager
extends Node2D
## Spawns enemy waves at the start of each day.
## Wave composition scales with the day number.
## Emits SignalBus.day_wave_cleared when all enemies for the wave are dead.

const EnemyScript = preload("res://scripts/combat/enemy.gd")

## Reference to the hex grid (used for spawn positions).
@onready var hex_grid: HexGrid = %HexGrid

## Container under which all enemies are parented.
@onready var enemies_container: Node2D = %Enemies

## Enemy scene to instantiate.
var _enemy_scene: PackedScene = preload("res://scenes/entities/enemy.tscn")

## Spawn queue: list of enemy ids waiting to spawn this wave.
var _spawn_queue: Array[StringName] = []

## Time until next spawn pop.
var _spawn_timer: float = 0.0

## Delay between consecutive spawns within a wave.
const SPAWN_INTERVAL: float = 0.45

## Set of currently alive enemies.
var _alive: Array[Node2D] = []

## Total enemies in the current wave (for progress tracking).
var _wave_total: int = 0

## True while a wave is actively running.
var _wave_active: bool = false


func _ready() -> void:
	SignalBus.day_started.connect(_on_day_started)
	SignalBus.night_started.connect(_on_night_started)
	SignalBus.enemy_died.connect(_on_enemy_died)


func _process(delta: float) -> void:
	if not _wave_active:
		return
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_next()
		_spawn_timer = SPAWN_INTERVAL


# -- Wave lifecycle ------------------------------------------------------------

func _on_day_started(day_number: int) -> void:
	_start_wave(day_number)


func _on_night_started(_night_number: int) -> void:
	# Clean up any leftover enemies if a wave was interrupted (e.g. game over restart).
	_wave_active = false
	_spawn_queue.clear()
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	_wave_total = 0


func _start_wave(day_number: int) -> void:
	_spawn_queue = _build_wave_composition(day_number)
	_wave_total = _spawn_queue.size()
	_wave_active = true
	_spawn_timer = 0.0
	SignalBus.wave_started.emit(day_number, _wave_total)
	SignalBus.wave_progress_changed.emit(_wave_total, _wave_total)


## Build the list of enemy ids for a given day.
func _build_wave_composition(day_number: int) -> Array[StringName]:
	var result: Array[StringName] = []
	# Day 1: 3 wasps (gentle ramp-up). +2 wasps per day. Hornets start day 2 with 1, +1 per day.
	var wasp_count: int = 3 + (day_number - 1) * 2
	var hornet_count: int = maxi(0, day_number - 1)
	for i in range(wasp_count):
		result.append(&"wasp")
	for i in range(hornet_count):
		result.append(&"hornet")
	# Shuffle so wasps and hornets interleave.
	result.shuffle()
	return result


# -- Spawning ------------------------------------------------------------------

func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		return
	var id: StringName = _spawn_queue.pop_front()
	var data := EnemyRegistry.get_enemy(id)
	if data == null:
		push_warning("WaveManager: unknown enemy id %s" % id)
		return

	var spawn_hex: Vector2i = _pick_spawn_hex()
	var spawn_pos: Vector2 = HexHelper.axial_to_pixel(spawn_hex, hex_grid.hex_size)

	var enemy: EnemyScript = _enemy_scene.instantiate() as EnemyScript
	enemies_container.add_child(enemy)
	enemy.setup(data, hex_grid, spawn_pos)
	_alive.append(enemy)

	SignalBus.enemy_spawned.emit(enemy)
	SignalBus.wave_progress_changed.emit(_alive.size() + _spawn_queue.size(), _wave_total)


func _pick_spawn_hex() -> Vector2i:
	# Pick a random walkable hex from the outer ring of the map.
	var ring: Array[Vector2i] = HexHelper.get_hex_ring(Vector2i.ZERO, hex_grid.map_radius)
	# Try up to 12 random picks for a walkable hex.
	for _i in range(12):
		var idx: int = randi() % ring.size()
		var coord: Vector2i = ring[idx]
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile != null and tile.is_walkable():
			return coord
	# Fallback: scan the ring for the first walkable.
	for coord in ring:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile != null and tile.is_walkable():
			return coord
	return ring[0]


# -- Death tracking ------------------------------------------------------------

func _on_enemy_died(enemy: Node2D) -> void:
	if not _wave_active:
		return
	var idx: int = _alive.find(enemy)
	if idx >= 0:
		_alive.remove_at(idx)

	var remaining: int = _alive.size() + _spawn_queue.size()
	SignalBus.wave_progress_changed.emit(remaining, _wave_total)

	if remaining <= 0 and _spawn_queue.is_empty():
		_wave_active = false
		# Brief pause before transitioning to night.
		await get_tree().create_timer(0.6).timeout
		SignalBus.day_wave_cleared.emit()


## How many enemies are still alive or queued.
func get_remaining() -> int:
	return _alive.size() + _spawn_queue.size()


## Total enemies for the current wave.
func get_wave_total() -> int:
	return _wave_total
