class_name BuildManager
extends Node2D
## Central build mode state machine. Coordinates building placement flow:
## IDLE → PREVIEWING → WALKING_TO_BUILD → BUILDING → IDLE
## Communicates exclusively through SignalBus signals.

enum BuildState { IDLE, PREVIEWING, WALKING_TO_BUILD, BUILDING }

## Reference to the hex grid.
@onready var hex_grid: HexGrid = %HexGrid

## Container node for building instances.
@onready var buildings_container: Node2D = %Buildings

## Building scene to instantiate.
var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")

## Current state.
var _state: BuildState = BuildState.IDLE

## Currently selected building data (during PREVIEWING/WALKING/BUILDING).
var _selected_data: Resource = null

## Target hex coordinate for placement.
var _target_coord: Variant = null  # Vector2i or null

## Whether the current hover position is valid for placement.
var _hover_valid: bool = false

## Current hover coordinate.
var _hover_coord: Variant = null  # Vector2i or null


func _ready() -> void:
	SignalBus.build_requested.connect(_on_build_requested)
	SignalBus.hero_reached_build_range.connect(_on_hero_reached_build_range)
	SignalBus.build_walk_cancelled.connect(_on_build_walk_cancelled)
	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.upgrade_requested.connect(_on_upgrade_requested)
	hex_grid.tile_clicked.connect(_on_tile_clicked)

	# Place the starting Hive at map center
	call_deferred("_place_starting_hive")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _state != BuildState.IDLE:
				_cancel_build()
				get_viewport().set_input_as_handled()
			elif DayNightManager.is_night():
				_try_remove_building_at_mouse()
				get_viewport().set_input_as_handled()
			return

	if _state == BuildState.IDLE:
		return

	if event.is_action_pressed("cancel_build"):
		_cancel_build()
		get_viewport().set_input_as_handled()


func _on_build_requested(building_id: StringName) -> void:
	if not DayNightManager.is_night():
		return

	var data := BuildingRegistry.get_building(building_id)
	if data == null:
		return

	# If already previewing the same type, cancel instead (toggle)
	if _state == BuildState.PREVIEWING and _selected_data and _selected_data.id == building_id:
		_cancel_build()
		return

	# Cancel any active build before starting new one
	if _state != BuildState.IDLE:
		_cancel_build_silent()

	_selected_data = data
	_state = BuildState.PREVIEWING
	SignalBus.build_preview_started.emit(data)


func _on_tile_clicked(coord: Vector2i) -> void:
	if _state != BuildState.PREVIEWING:
		return
	if _selected_data == null:
		return
	if not hex_grid.can_place_building(coord, _selected_data):
		return

	_target_coord = coord
	_hover_coord = null

	# Check hero distance
	var hero: Hero = %Hero
	var dist := HexHelper.distance(hero.current_hex, coord)
	if dist <= 1:
		# Already in range — build immediately
		_state = BuildState.BUILDING
		_execute_build()
	else:
		# Need to walk closer
		_state = BuildState.WALKING_TO_BUILD
		SignalBus.build_walk_requested.emit(coord)


func _on_hero_reached_build_range(target_coord: Vector2i) -> void:
	if _state != BuildState.WALKING_TO_BUILD:
		return
	if _target_coord == null or (target_coord as Vector2i) != (_target_coord as Vector2i):
		return
	_state = BuildState.BUILDING
	_execute_build()


func _on_build_walk_cancelled() -> void:
	if _state != BuildState.WALKING_TO_BUILD:
		return
	# Return to previewing — player can try another tile
	_state = BuildState.PREVIEWING
	_target_coord = null


func _on_phase_changed(phase: StringName) -> void:
	if phase == &"day" and _state != BuildState.IDLE:
		_cancel_build()


func _on_upgrade_requested(coord: Vector2i) -> void:
	if not DayNightManager.is_night():
		return
	var building: Variant = hex_grid.get_building_at(coord)
	if building == null or not building.has_method("upgrade"):
		return
	if building.upgrade():
		SignalBus.building_upgraded.emit(coord, building.level)


func _execute_build() -> void:
	if _selected_data == null or _target_coord == null:
		_state = BuildState.IDLE
		return

	var coord: Vector2i = _target_coord as Vector2i
	var world_pos: Vector2 = hex_grid.hex_to_world(coord)

	# Instantiate building
	var building: Node2D = _building_scene.instantiate() as Node2D
	building.setup(_selected_data, coord, world_pos, hex_grid.get_effective_hex_size(coord))
	buildings_container.add_child(building)

	# Register on grid
	hex_grid.place_building(coord, building)

	# Placement animation
	building.play_place_effect()

	# Notify systems
	SignalBus.building_placed.emit(_selected_data.id, coord, building.level)

	# Stay in preview mode for multi-placement
	_target_coord = null
	_state = BuildState.PREVIEWING


func _cancel_build() -> void:
	_cancel_build_silent()
	SignalBus.build_preview_ended.emit()


func _cancel_build_silent() -> void:
	if _state == BuildState.WALKING_TO_BUILD:
		SignalBus.build_walk_cancelled.emit()
	_state = BuildState.IDLE
	_selected_data = null
	_target_coord = null
	_hover_coord = null
	_hover_valid = false


## Get current build state (for external queries).
func get_state() -> BuildState:
	return _state


## Get currently selected building data (or null).
func get_selected_data() -> Resource:
	return _selected_data


## Try to remove a building at the mouse position (right-click in IDLE + night).
## Hive cannot be removed.
func _try_remove_building_at_mouse() -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	var coord: Vector2i = hex_grid.world_to_hex(mouse_world)
	var tile: HexTile = hex_grid.get_tile(coord)
	if tile == null or not tile.has_building:
		return
	var building: Node2D = tile.building as Node2D
	if building == null:
		return
	# Never allow removing the Hive
	if building.data != null and building.data.id == &"hive":
		return
	# Remove from grid
	hex_grid.remove_building(coord)
	# Destroy the building node
	building.queue_free()


## Place the starting Hive at the center of the map.
func _place_starting_hive() -> void:
	var hive_data := BuildingRegistry.get_building(&"hive")
	if hive_data == null:
		push_warning("BuildManager: Hive building data not found in registry")
		return

	var coord := Vector2i.ZERO
	var tile := hex_grid.get_tile(coord)
	if tile == null:
		return

	# Set terrain to HIVE
	tile.terrain = HexTile.TerrainType.HIVE

	var world_pos := hex_grid.hex_to_world(coord)
	var building: Node2D = _building_scene.instantiate() as Node2D
	building.setup(hive_data, coord, world_pos, hex_grid.get_effective_hex_size(coord))
	buildings_container.add_child(building)
	hex_grid.place_building(coord, building)
