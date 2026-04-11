extends Node
## Global honey economy. Tracks the player's honey balance and exposes
## spend/earn operations. All gameplay systems go through this autoload;
## emits SignalBus.honey_changed so UI and FX can react.

## Starting honey at the beginning of a run.
const STARTING_HONEY: int = 20

## Current honey balance.
var _honey: int = STARTING_HONEY


func _ready() -> void:
	SignalBus.restart_requested.connect(_on_restart_requested)
	# Defer the initial broadcast so other autoloads / HUD nodes are ready.
	call_deferred("_broadcast_initial")


func _broadcast_initial() -> void:
	SignalBus.honey_changed.emit(_honey, 0, &"initial")


## Current honey balance.
func get_honey() -> int:
	return _honey


## True if the player can afford the given amount.
func can_afford(amount: int) -> bool:
	return _honey >= amount


## Try to spend the given amount. Returns true if successful.
## If the player cannot afford, emits not_enough_honey and returns false.
func spend(amount: int, reason: StringName = &"spend") -> bool:
	if amount <= 0:
		return true
	if _honey < amount:
		SignalBus.not_enough_honey.emit(amount, _honey)
		return false
	_honey -= amount
	SignalBus.honey_changed.emit(_honey, -amount, reason)
	return true


## Add honey to the player's balance.
func earn(amount: int, reason: StringName = &"earn") -> void:
	if amount <= 0:
		return
	_honey += amount
	SignalBus.honey_changed.emit(_honey, amount, reason)


## Directly set the balance (dev console / cheat).
func set_honey(amount: int) -> void:
	var delta: int = amount - _honey
	_honey = max(0, amount)
	SignalBus.honey_changed.emit(_honey, delta, &"cheat")


func _on_restart_requested() -> void:
	_honey = STARTING_HONEY
	SignalBus.honey_changed.emit(_honey, 0, &"restart")
