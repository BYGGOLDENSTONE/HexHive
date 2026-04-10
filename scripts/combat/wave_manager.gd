class_name WaveManager
extends Node3D
## Spawns enemy waves at the start of each day.
## Wave composition scales with the day number.

const EnemyScript = preload("res://scripts/combat/enemy.gd")

@onready var hex_grid: HexGrid = %HexGrid
@onready var enemies_container: Node3D = %Enemies

var _enemy_scene: PackedScene = preload("res://scenes/entities/enemy.tscn")
var _spawn_queue: Array[StringName] = []
var _spawn_timer: float = 0.0
var spawn_interval: float = 0.45
var _alive: Array[Node3D] = []
var _wave_total: int = 0
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
		_spawn_timer = spawn_interval


func _on_day_started(day_number: int) -> void:
	_start_wave(day_number)


func _on_night_started(_night_number: int) -> void:
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


func _build_wave_composition(day_number: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var wasp_count: int = 3 + (day_number - 1) * 2
	var hornet_count: int = maxi(0, day_number - 1)
	for i in range(wasp_count):
		result.append(&"wasp")
	for i in range(hornet_count):
		result.append(&"hornet")
	result.shuffle()
	return result


func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		return
	var id: StringName = _spawn_queue.pop_front()
	var data := EnemyRegistry.get_enemy(id)
	if data == null:
		push_warning("WaveManager: unknown enemy id %s" % id)
		return

	var spawn_hex: Vector2i = _pick_spawn_hex()
	var spawn_pos: Vector3 = hex_grid.hex_to_world(spawn_hex)

	var enemy: EnemyScript = _enemy_scene.instantiate() as EnemyScript
	enemies_container.add_child(enemy)
	enemy.setup(data, hex_grid, spawn_pos)
	_alive.append(enemy)

	SignalBus.enemy_spawned.emit(enemy)
	SignalBus.wave_progress_changed.emit(_alive.size() + _spawn_queue.size(), _wave_total)


func _pick_spawn_hex() -> Vector2i:
	var ring: Array[Vector2i] = HexHelper.get_hex_ring(Vector2i.ZERO, hex_grid.map_radius)
	for _i in range(12):
		var idx: int = randi() % ring.size()
		var coord: Vector2i = ring[idx]
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile != null and tile.is_walkable():
			return coord
	for coord in ring:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile != null and tile.is_walkable():
			return coord
	return ring[0]


func _on_enemy_died(enemy: Node3D) -> void:
	if not _wave_active:
		return
	var idx: int = _alive.find(enemy)
	if idx >= 0:
		_alive.remove_at(idx)

	var remaining: int = _alive.size() + _spawn_queue.size()
	SignalBus.wave_progress_changed.emit(remaining, _wave_total)

	if remaining <= 0 and _spawn_queue.is_empty():
		_wave_active = false
		await get_tree().create_timer(0.6).timeout
		SignalBus.day_wave_cleared.emit()


func get_remaining() -> int:
	return _alive.size() + _spawn_queue.size()


func get_wave_total() -> int:
	return _wave_total
