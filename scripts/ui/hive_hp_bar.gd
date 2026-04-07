class_name HiveHpBar
extends CanvasLayer
## Top-center Hive HP display. Always visible during gameplay.
## Pulses red when HP drops below 50%.

@onready var bar: ProgressBar = %HiveBar
@onready var label: Label = %HiveLabel
@onready var container: PanelContainer = %HiveContainer

var _max_hp: float = 0.0
var _current_hp: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	layer = 9
	SignalBus.hive_damaged.connect(_on_hive_damaged)
	SignalBus.hive_destroyed.connect(_on_hive_destroyed)
	SignalBus.restart_requested.connect(_on_restart_requested)
	# Initial fill — query the Hive after first frame.
	call_deferred("_initialize_from_hive")


func _initialize_from_hive() -> void:
	var grid: HexGrid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	if grid == null:
		return
	var hive: Variant = grid.get_building_at(Vector2i.ZERO)
	if hive == null:
		return
	if hive.health != null:
		_max_hp = hive.health.max_hp
		_current_hp = hive.health.current_hp
		_apply()


func _process(delta: float) -> void:
	if _current_hp / maxf(_max_hp, 1.0) < 0.5:
		_pulse += delta * 5.0
		var t: float = (sin(_pulse) + 1.0) * 0.5
		container.modulate = Color(1.0, 0.6 + t * 0.4, 0.6 + t * 0.4, 1.0)
	else:
		container.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_hive_damaged(_amount: float, current: float, maximum: float) -> void:
	_current_hp = current
	_max_hp = maximum
	_apply()


func _on_hive_destroyed() -> void:
	_current_hp = 0.0
	_apply()


func _on_restart_requested() -> void:
	call_deferred("_initialize_from_hive")


func _apply() -> void:
	if bar == null or label == null:
		return
	bar.max_value = _max_hp
	bar.value = _current_hp
	label.text = "Hive  %d / %d" % [int(round(_current_hp)), int(round(_max_hp))]
