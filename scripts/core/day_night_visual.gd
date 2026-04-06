class_name DayNightVisual
extends CanvasModulate
## Controls the visual atmosphere for day/night transitions.
## Uses CanvasModulate to tint the entire scene with smooth tweening.

## Night tint — cool deep blue, cozy moonlit atmosphere.
@export var night_color: Color = Color(0.45, 0.50, 0.75, 1.0)

## Day tint — warm bright, full visibility.
@export var day_color: Color = Color(1.0, 0.98, 0.92, 1.0)

## Duration of the color transition in seconds.
@export var transition_duration: float = 1.5

## Active tween reference.
var _tween: Tween


func _ready() -> void:
	# Start with night color (game begins at Night 0)
	color = night_color

	SignalBus.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: StringName) -> void:
	var target_color: Color = day_color if phase == &"day" else night_color
	_tween_to(target_color)


func _tween_to(target: Color) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "color", target, transition_duration)
