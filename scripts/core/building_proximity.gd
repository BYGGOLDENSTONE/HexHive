class_name BuildingProximity
extends Node
## Detects all buildings within range of the hero.
## On each hero hex change, clears and re-emits nearby buildings.

@onready var hex_grid: HexGrid = %HexGrid
@onready var hero: Node3D = %Hero

const RANGE: int = 1
var _prev_coords: Array[Vector2i] = []


func _ready() -> void:
	hero.hex_changed.connect(_on_hero_hex_changed)
	SignalBus.building_placed.connect(_on_building_placed)
	SignalBus.phase_changed.connect(_on_phase_changed)


func _on_hero_hex_changed(_old_hex: Vector2i, new_hex: Vector2i) -> void:
	_check_proximity(new_hex)


func _on_building_placed(_id: StringName, _coord: Vector2i, _level: int) -> void:
	_check_proximity(hero.current_hex)


func _on_phase_changed(phase: StringName) -> void:
	if phase == &"day":
		if _prev_coords.size() > 0:
			SignalBus.hero_left_building.emit()
			_prev_coords.clear()


func _check_proximity(hero_hex: Vector2i) -> void:
	if not DayNightManager.is_night():
		return

	var current_coords: Array[Vector2i] = []
	var building_coords := hex_grid.get_all_building_coords()
	for coord in building_coords:
		var dist := HexHelper.distance(hero_hex, coord)
		if dist <= RANGE:
			current_coords.append(coord)

	var changed := current_coords.size() != _prev_coords.size()
	if not changed:
		for coord in current_coords:
			if coord not in _prev_coords:
				changed = true
				break

	if not changed:
		return

	if _prev_coords.size() > 0:
		SignalBus.hero_left_building.emit()

	for coord in current_coords:
		var b: Variant = hex_grid.get_building_at(coord)
		if b != null:
			SignalBus.hero_near_building.emit(b as Node3D, coord)

	_prev_coords = current_coords
