class_name BuildManager
extends Node3D
## Central build mode state machine. Coordinates building placement flow.
## IDLE -> PREVIEWING -> WALKING_TO_BUILD -> BUILDING -> IDLE

enum BuildState { IDLE, PREVIEWING, WALKING_TO_BUILD, BUILDING }

@onready var hex_grid: HexGrid = %HexGrid
@onready var buildings_container: Node3D = %Buildings

var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")
var _state: BuildState = BuildState.IDLE
var _selected_data: Resource = null
var _target_coord: Variant = null
var _hover_valid: bool = false
var _hover_coord: Variant = null


func _ready() -> void:
	SignalBus.build_requested.connect(_on_build_requested)
	SignalBus.hero_reached_build_range.connect(_on_hero_reached_build_range)
	SignalBus.build_walk_cancelled.connect(_on_build_walk_cancelled)
	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.upgrade_requested.connect(_on_upgrade_requested)
	hex_grid.tile_clicked.connect(_on_tile_clicked)
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
	if _state == BuildState.PREVIEWING and _selected_data and _selected_data.id == building_id:
		_cancel_build()
		return
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

	var hero: Node3D = %Hero
	var dist := HexHelper.distance(hero.current_hex, coord)
	if dist <= 1:
		_state = BuildState.BUILDING
		_execute_build()
	else:
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
	var world_pos: Vector3 = hex_grid.hex_to_world(coord)

	var building: Node3D = _building_scene.instantiate() as Node3D
	building.setup(_selected_data, coord, world_pos, hex_grid.hex_size)
	buildings_container.add_child(building)
	hex_grid.place_building(coord, building)
	building.play_place_effect()
	SignalBus.building_placed.emit(_selected_data.id, coord, building.level)

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


func get_state() -> BuildState:
	return _state


func get_selected_data() -> Resource:
	return _selected_data


func _try_remove_building_at_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	var coord: Vector2i = hex_grid.world_to_hex(world_pos)
	var tile: HexTile = hex_grid.get_tile(coord)
	if tile == null or not tile.has_building:
		return
	var building: Node3D = tile.building as Node3D
	if building == null:
		return
	if building.data != null and building.data.id == &"hive":
		return
	hex_grid.remove_building(coord)
	building.queue_free()


func _place_starting_hive() -> void:
	var hive_data := BuildingRegistry.get_building(&"hive")
	if hive_data == null:
		push_warning("BuildManager: Hive building data not found")
		return
	var coord := Vector2i.ZERO
	var tile := hex_grid.get_tile(coord)
	if tile == null:
		return
	tile.terrain = HexTile.TerrainType.HIVE

	var world_pos := hex_grid.hex_to_world(coord)
	var building: Node3D = _building_scene.instantiate() as Node3D
	building.setup(hive_data, coord, world_pos, hex_grid.hex_size)
	buildings_container.add_child(building)
	hex_grid.place_building(coord, building)
