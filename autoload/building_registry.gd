extends Node
## Loads and indexes all BuildingData resources at startup.
## Provides O(1) lookup by building id.

const BUILDINGS_PATH: String = "res://resources/buildings/"

## All building data indexed by id.
var _buildings: Dictionary = {}  # Dictionary[StringName, Resource]


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_buildings.clear()
	var dir := DirAccess.open(BUILDINGS_PATH)
	if dir == null:
		push_warning("BuildingRegistry: cannot open %s" % BUILDINGS_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := BUILDINGS_PATH + file_name
			var res := load(path)
			if res and res.get("id") != null:
				_buildings[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()


## Get a building data by its id, or null if not found.
func get_building(id: StringName) -> Resource:
	return _buildings.get(id)


## Get all building data entries that the player can build.
func get_all_buildable() -> Array:
	var result: Array = []
	for data in _buildings.values():
		if data.player_buildable:
			result.append(data)
	return result


## Check if a building id exists.
func has_building(id: StringName) -> bool:
	return _buildings.has(id)


## Get all registered building data entries.
func get_all() -> Array:
	var result: Array = []
	for data in _buildings.values():
		result.append(data)
	return result
