class_name BuildGhost
extends Node3D
## Renders a ghost preview of the building being placed in 3D.
## Follows mouse on the ground plane, snaps to hex grid, shows green/red validity.

@onready var hex_grid: HexGrid = %HexGrid

var _active: bool = false
var _building_data: Resource = null
var _current_coord: Variant = null
var _is_valid: bool = false
var _ghost_mesh: MeshInstance3D
var _ghost_mat: StandardMaterial3D


func _ready() -> void:
	visible = false
	SignalBus.build_preview_started.connect(_on_preview_started)
	SignalBus.build_preview_ended.connect(_on_preview_ended)
	SignalBus.building_placed.connect(_on_building_placed)
	SignalBus.honey_changed.connect(_on_honey_changed)

	# Create ghost mesh — a simple hex disc that changes color.
	_ghost_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = hex_grid.hex_size * 0.9 if hex_grid else 1.8
	mesh.bottom_radius = hex_grid.hex_size * 0.9 if hex_grid else 1.8
	mesh.height = 0.08
	mesh.radial_segments = 6
	_ghost_mesh.mesh = mesh
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.35)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.no_depth_test = true
	_ghost_mesh.set_surface_override_material(0, _ghost_mat)
	add_child(_ghost_mesh)


func _process(_delta: float) -> void:
	if not _active:
		return

	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		return

	var coord: Vector2i = hex_grid.world_to_hex(world_pos)

	if hex_grid.has_tile(coord):
		if _current_coord == null or coord != (_current_coord as Vector2i):
			_current_coord = coord
			position = hex_grid.hex_to_world(coord) + Vector3(0, 0.08, 0)
			_is_valid = hex_grid.can_place_building(coord, _building_data)
			SignalBus.build_preview_moved.emit(coord, _is_valid)
		_update_color()
	else:
		if _current_coord != null:
			_current_coord = null
			_is_valid = false
			_update_color()


func _can_afford() -> bool:
	if _building_data == null:
		return true
	var cost: int = _building_data.get_cost(1)
	return EconomyManager.can_afford(cost)


func _update_color() -> void:
	# Green = valid + affordable, amber = valid but too expensive, red = invalid placement.
	if _is_valid:
		if _can_afford():
			_ghost_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.35)
		else:
			_ghost_mat.albedo_color = Color(1.0, 0.75, 0.2, 0.4)
	else:
		_ghost_mat.albedo_color = Color(1.0, 0.3, 0.3, 0.35)


func _on_honey_changed(_new: int, _delta: int, _reason: StringName) -> void:
	if _active:
		_update_color()


func _on_preview_started(building_data: Resource) -> void:
	_building_data = building_data
	_current_coord = null
	_is_valid = false
	_active = true
	visible = true


func _on_preview_ended() -> void:
	_active = false
	visible = false
	_building_data = null
	_current_coord = null


func _on_building_placed(_building_id: StringName, _coord: Vector2i, _level: int) -> void:
	_current_coord = null
