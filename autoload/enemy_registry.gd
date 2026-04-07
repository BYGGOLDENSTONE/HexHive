extends Node
## Loads and indexes all EnemyData resources at startup.
## Provides O(1) lookup by enemy id.

const ENEMIES_PATH: String = "res://resources/enemies/"

## All enemy data indexed by id.
var _enemies: Dictionary = {}  # Dictionary[StringName, Resource]


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_enemies.clear()
	var dir := DirAccess.open(ENEMIES_PATH)
	if dir == null:
		push_warning("EnemyRegistry: cannot open %s" % ENEMIES_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := ENEMIES_PATH + file_name
			var res := load(path)
			if res and res.get("id") != null:
				_enemies[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()


## Get an enemy data by its id, or null if not found.
func get_enemy(id: StringName) -> Resource:
	return _enemies.get(id)


## Check if an enemy id exists.
func has_enemy(id: StringName) -> bool:
	return _enemies.has(id)


## Get all registered enemy data entries.
func get_all() -> Array:
	var result: Array = []
	for data in _enemies.values():
		result.append(data)
	return result
