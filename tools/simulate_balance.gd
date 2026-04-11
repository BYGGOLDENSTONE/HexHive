@tool
extends EditorScript
## Headless balance simulator.
##
## Run via Godot editor: File → Run (or Ctrl+Shift+X while this script is open).
## Reads building + enemy .tres files and prints a day-by-day projection of:
##   - wave composition
##   - total enemy HP per wave
##   - hero DPS ratio
##   - time-to-kill each enemy type with each tower level
##   - honey income/spending projection (based on flower garden count)
##
## Use this to sanity-check balance changes before running the game.
## This is NOT a test — it's a design tool. Tune BALANCE_HERO_DPS etc. at the top
## to match Constants.gd if you change them.

const BALANCE_HERO_DPS: float = 10.0 * 1.5  # attack_damage * attack_speed
const BALANCE_STARTING_HONEY: int = 20
const BALANCE_MAX_DAYS: int = 10
const BALANCE_WAVE_BASE_WASPS: int = 3
const BALANCE_WAVE_WASPS_PER_DAY: int = 2
const BALANCE_WAVE_HORNET_START_DAY: int = 2


func _run() -> void:
	print("")
	print("=== HexHive Balance Simulation ===")
	print("")

	# Load all building + enemy data.
	var buildings: Dictionary = _load_building_data()
	var enemies: Dictionary = _load_enemy_data()

	_report_buildings(buildings)
	_report_enemies(enemies)
	_report_hero_vs_enemies(enemies)
	_report_tower_time_to_kill(buildings, enemies)
	_report_wave_schedule(enemies)
	_report_economy(buildings, enemies)

	print("")
	print("=== End of simulation ===")


func _load_building_data() -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open("res://resources/buildings")
	if dir == null:
		push_error("Cannot open res://resources/buildings")
		return result
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.ends_with(".tres"):
			var path: String = "res://resources/buildings/" + name
			var data: Resource = load(path)
			if data != null and "id" in data:
				result[String(data.id)] = data
		name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_enemy_data() -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open("res://resources/enemies")
	if dir == null:
		push_error("Cannot open res://resources/enemies")
		return result
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.ends_with(".tres"):
			var path: String = "res://resources/enemies/" + name
			var data: Resource = load(path)
			if data != null and "id" in data:
				result[String(data.id)] = data
		name = dir.get_next()
	dir.list_dir_end()
	return result


func _report_buildings(buildings: Dictionary) -> void:
	print("-- Buildings --")
	for id: String in buildings.keys():
		var d: Resource = buildings[id]
		var cost_str: String = "free"
		if "cost_per_level" in d and d.cost_per_level.size() > 0:
			cost_str = str(d.cost_per_level)
		var income_str: String = "none"
		if "honey_per_round_per_level" in d and d.honey_per_round_per_level.size() > 0:
			var has_income: bool = false
			for v in d.honey_per_round_per_level:
				if v > 0:
					has_income = true
					break
			if has_income:
				income_str = str(d.honey_per_round_per_level) + "/round"
		print("  %-14s | cost %s | income %s | HP %s" % [d.display_name, cost_str, income_str, str(d.max_hp_per_level)])
	print("")


func _report_enemies(enemies: Dictionary) -> void:
	print("-- Enemies --")
	for id: String in enemies.keys():
		var d: Resource = enemies[id]
		var drop: int = d.honey_drop if "honey_drop" in d else 0
		print("  %-10s | HP %d | dmg %d | spd %.2f | honey_drop %d" % [d.display_name, int(d.max_hp), int(d.attack_damage), d.move_speed, drop])
	print("")


func _report_hero_vs_enemies(enemies: Dictionary) -> void:
	print("-- Hero vs Enemies (hero DPS %.1f) --" % BALANCE_HERO_DPS)
	for id: String in enemies.keys():
		var d: Resource = enemies[id]
		var ttk: float = d.max_hp / BALANCE_HERO_DPS
		print("  %-10s: %.2f sec to kill (HP %d / DPS %.1f)" % [d.display_name, ttk, int(d.max_hp), BALANCE_HERO_DPS])
	print("")


func _report_tower_time_to_kill(buildings: Dictionary, enemies: Dictionary) -> void:
	print("-- Honey Turret DPS vs Enemies --")
	if not buildings.has("honey_turret"):
		print("  (honey_turret not found)")
		print("")
		return
	var turret: Resource = buildings["honey_turret"]
	for lvl in range(1, turret.max_level + 1):
		var dps: float = turret.get_attack_damage(lvl) * turret.get_attack_speed(lvl)
		print("  L%d: %.1f DPS (dmg %d × speed %.1f/s)" % [lvl, dps, int(turret.get_attack_damage(lvl)), turret.get_attack_speed(lvl)])
		for id: String in enemies.keys():
			var e: Resource = enemies[id]
			var ttk: float = e.max_hp / dps
			print("    vs %-10s: %.2fs" % [e.display_name, ttk])
	print("")


func _report_wave_schedule(enemies: Dictionary) -> void:
	print("-- Wave Schedule (%d days) --" % BALANCE_MAX_DAYS)
	var wasp: Resource = enemies.get("wasp")
	var hornet: Resource = enemies.get("hornet")
	var total_hp_all: int = 0
	for day in range(1, BALANCE_MAX_DAYS + 1):
		var wasp_count: int = BALANCE_WAVE_BASE_WASPS + (day - 1) * BALANCE_WAVE_WASPS_PER_DAY
		var hornet_count: int = max(0, day - BALANCE_WAVE_HORNET_START_DAY + 1)
		var day_hp: int = int(wasp_count * wasp.max_hp) + int(hornet_count * hornet.max_hp)
		total_hp_all += day_hp
		var wave_str: String = "Day %2d: %2d wasps + %2d hornets = %4d HP total" % [day, wasp_count, hornet_count, day_hp]
		print("  " + wave_str)
	print("  Total HP across all days: %d" % total_hp_all)
	print("")


func _report_economy(buildings: Dictionary, enemies: Dictionary) -> void:
	print("-- Economy Projection (assumes: 1 flower L1 at start, survive every day) --")
	if not buildings.has("flower_garden"):
		print("  (flower_garden not found)")
		print("")
		return
	var flower: Resource = buildings["flower_garden"]
	var wasp: Resource = enemies.get("wasp")
	var hornet: Resource = enemies.get("hornet")
	var honey: int = BALANCE_STARTING_HONEY - flower.get_cost(1)  # bought 1 flower on Night 0
	print("  Start: %d honey (after buying 1 L1 flower)" % honey)
	for day in range(1, BALANCE_MAX_DAYS + 1):
		var wasp_count: int = BALANCE_WAVE_BASE_WASPS + (day - 1) * BALANCE_WAVE_WASPS_PER_DAY
		var hornet_count: int = max(0, day - BALANCE_WAVE_HORNET_START_DAY + 1)
		var drops: int = wasp_count * int(wasp.honey_drop if "honey_drop" in wasp else 0)
		drops += hornet_count * int(hornet.honey_drop if "honey_drop" in hornet else 0)
		var flower_yield: int = flower.get_honey_per_round(1)
		honey += drops + flower_yield
		print("  Day %2d end: +%d drops, +%d flower, total honey = %d" % [day, drops, flower_yield, honey])
	print("")
