class_name HoneyHud
extends CanvasLayer
## Displays the current honey balance. Flashes green on earn, red on spend.
## Listens to SignalBus.honey_changed and SignalBus.not_enough_honey.

@onready var panel: PanelContainer = %HoneyPanel
@onready var amount_label: Label = %HoneyAmount
@onready var delta_label: Label = %HoneyDelta

var _tween: Tween
var _delta_tween: Tween


func _ready() -> void:
	layer = 10
	SignalBus.honey_changed.connect(_on_honey_changed)
	SignalBus.not_enough_honey.connect(_on_not_enough_honey)
	delta_label.modulate.a = 0.0
	_set_amount(EconomyManager.get_honey())


func _set_amount(value: int) -> void:
	amount_label.text = "🍯 %d" % value


func _on_honey_changed(new_amount: int, delta: int, _reason: StringName) -> void:
	_set_amount(new_amount)

	if delta == 0:
		return

	# Flash the panel for positive/negative feedback.
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)

	var flash_color: Color
	var sign_str: String
	if delta > 0:
		flash_color = Color(0.55, 1.0, 0.45)
		sign_str = "+"
	else:
		flash_color = Color(1.0, 0.55, 0.45)
		sign_str = ""

	amount_label.add_theme_color_override("font_color", flash_color)
	_tween.tween_method(_lerp_label_color, flash_color, Color(1.0, 0.9, 0.45), 0.6)

	# Show the delta above the amount briefly.
	delta_label.text = "%s%d" % [sign_str, delta]
	delta_label.add_theme_color_override("font_color", flash_color)
	delta_label.modulate.a = 1.0
	delta_label.position.y = -4.0
	if _delta_tween and _delta_tween.is_valid():
		_delta_tween.kill()
	_delta_tween = create_tween()
	_delta_tween.set_parallel(true)
	_delta_tween.tween_property(delta_label, "position:y", -20.0, 0.8).set_ease(Tween.EASE_OUT)
	_delta_tween.tween_property(delta_label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)


func _lerp_label_color(color: Color) -> void:
	amount_label.add_theme_color_override("font_color", color)


func _on_not_enough_honey(_required: int, _current: int) -> void:
	# Shake the panel for negative feedback when the player tries to overspend.
	if _tween and _tween.is_valid():
		_tween.kill()
	var start_pos: Vector2 = panel.position
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.tween_property(panel, "position:x", start_pos.x + 8, 0.05)
	_tween.tween_property(panel, "position:x", start_pos.x - 8, 0.1)
	_tween.tween_property(panel, "position:x", start_pos.x + 6, 0.08)
	_tween.tween_property(panel, "position:x", start_pos.x, 0.08)

	amount_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	var back_tw := create_tween()
	back_tw.tween_interval(0.25)
	back_tw.tween_method(_lerp_label_color, Color(1.0, 0.35, 0.25), Color(1.0, 0.9, 0.45), 0.4)
