extends Node
## Validates all .tres resource files at startup.
## Reports inconsistencies to DevConsole and Godot output.

var _issues: Array[String] = []
var _warnings: Array[String] = []


func _ready() -> void:
	# Defer validation so other autoloads (registries) are loaded first.
	call_deferred("_validate_all")


func _validate_all() -> void:
	_issues.clear()
	_warnings.clear()

	_validate_buildings()
	_validate_enemies()
	_validate_model_files()

	_report()


func _validate_buildings() -> void:
	var all_buildings: Array = BuildingRegistry.get_all()
	var seen_ids: Dictionary = {}

	for data in all_buildings:
		# Duplicate ID check.
		if seen_ids.has(data.id):
			_issues.append("Duplicate building ID: '%s'" % data.id)
		seen_ids[data.id] = true

		# Empty ID.
		if data.id == &"":
			_issues.append("Building with empty ID found (display: '%s')" % data.display_name)

		# Per-level array length consistency.
		var expected: int = data.max_level
		if data.max_hp_per_level.size() != expected:
			_warnings.append("Building '%s': max_hp_per_level has %d entries, expected %d (max_level)" % [data.id, data.max_hp_per_level.size(), expected])

		if data.is_offensive():
			if data.attack_damage_per_level.size() != expected:
				_warnings.append("Building '%s': attack_damage_per_level has %d entries, expected %d" % [data.id, data.attack_damage_per_level.size(), expected])
			if data.attack_range_per_level.size() != expected:
				_warnings.append("Building '%s': attack_range_per_level has %d entries, expected %d" % [data.id, data.attack_range_per_level.size(), expected])
			if data.attack_speed_per_level.size() != expected:
				_warnings.append("Building '%s': attack_speed_per_level has %d entries, expected %d" % [data.id, data.attack_speed_per_level.size(), expected])

		# Economy arrays.
		if data.cost_per_level.size() != expected:
			_warnings.append("Building '%s': cost_per_level has %d entries, expected %d" % [data.id, data.cost_per_level.size(), expected])
		for i in range(data.cost_per_level.size()):
			if data.cost_per_level[i] < 0:
				_issues.append("Building '%s' L%d has negative cost: %d" % [data.id, i + 1, data.cost_per_level[i]])

		if data.honey_per_round_per_level.size() != expected:
			_warnings.append("Building '%s': honey_per_round_per_level has %d entries, expected %d" % [data.id, data.honey_per_round_per_level.size(), expected])
		for i in range(data.honey_per_round_per_level.size()):
			if data.honey_per_round_per_level[i] < 0:
				_issues.append("Building '%s' L%d has negative honey income: %d" % [data.id, i + 1, data.honey_per_round_per_level[i]])

		# Economy tag consistency.
		var has_economy_tag: bool = &"economy" in data.tags or &"production" in data.tags
		if data.is_economy() and not has_economy_tag:
			_warnings.append("Building '%s' produces honey but has no economy/production tag" % data.id)

		# Offensive tag check.
		var has_offense_tag: bool = &"defense" in data.tags or &"ranged" in data.tags
		if data.is_offensive() and not has_offense_tag:
			_warnings.append("Building '%s' has attack stats but no defense/ranged tag" % data.id)

		# HP sanity.
		for i in range(data.max_hp_per_level.size()):
			if data.max_hp_per_level[i] <= 0.0:
				_issues.append("Building '%s' L%d has non-positive HP: %.0f" % [data.id, i + 1, data.max_hp_per_level[i]])

		# Buildable_on sanity (0=GRASS, 1=MOUNTAIN, 2=WATER, 3=HIVE, 4=FOREST, 5=FLOWER).
		for terrain in data.buildable_on:
			if terrain < 0 or terrain > 5:
				_warnings.append("Building '%s': invalid buildable_on terrain type: %d" % [data.id, terrain])


func _validate_enemies() -> void:
	var all_enemies: Array = EnemyRegistry.get_all()
	var seen_ids: Dictionary = {}

	for data in all_enemies:
		# Duplicate ID check.
		if seen_ids.has(data.id):
			_issues.append("Duplicate enemy ID: '%s'" % data.id)
		seen_ids[data.id] = true

		# Empty ID.
		if data.id == &"":
			_issues.append("Enemy with empty ID found (display: '%s')" % data.display_name)

		# Stat sanity.
		if data.max_hp <= 0.0:
			_issues.append("Enemy '%s' has non-positive max_hp: %.0f" % [data.id, data.max_hp])
		if data.move_speed <= 0.0:
			_warnings.append("Enemy '%s' has non-positive move_speed: %.2f" % [data.id, data.move_speed])
		if data.attack_damage <= 0.0:
			_warnings.append("Enemy '%s' has non-positive attack_damage: %.0f" % [data.id, data.attack_damage])
		if data.attack_speed <= 0.0:
			_warnings.append("Enemy '%s' has non-positive attack_speed: %.2f" % [data.id, data.attack_speed])
		if data.attack_range <= 0.0:
			_warnings.append("Enemy '%s' has non-positive attack_range: %.2f" % [data.id, data.attack_range])
		if data.honey_drop < 0:
			_issues.append("Enemy '%s' has negative honey_drop: %d" % [data.id, data.honey_drop])


func _validate_model_files() -> void:
	# Check building models.
	var all_buildings: Array = BuildingRegistry.get_all()
	for data in all_buildings:
		if data.model_path != "" and not ResourceLoader.exists(data.model_path):
			_issues.append("Building '%s' model not found: %s" % [data.id, data.model_path])

	# Check enemy models.
	var all_enemies: Array = EnemyRegistry.get_all()
	for data in all_enemies:
		if data.model_path != "" and not ResourceLoader.exists(data.model_path):
			_issues.append("Enemy '%s' model not found: %s" % [data.id, data.model_path])


func _report() -> void:
	var total: int = _issues.size() + _warnings.size()
	if total == 0:
		if DevConsole:
			DevConsole.log_system("Resource validation: All resources OK.")
		print("[ResourceValidator] All resources validated successfully.")
		return

	# Report issues.
	for issue in _issues:
		push_error("[ResourceValidator] ERROR: " + issue)
		if DevConsole:
			DevConsole.log_error("Validation: " + issue)

	for warning in _warnings:
		push_warning("[ResourceValidator] WARNING: " + warning)
		if DevConsole:
			DevConsole.log_warning("Validation: " + warning)

	var summary: String = "Resource validation: %d errors, %d warnings" % [_issues.size(), _warnings.size()]
	print("[ResourceValidator] " + summary)
	if DevConsole:
		DevConsole.log_system(summary)


## Returns all issues found during validation.
func get_issues() -> Array[String]:
	return _issues


## Returns all warnings found during validation.
func get_warnings() -> Array[String]:
	return _warnings
