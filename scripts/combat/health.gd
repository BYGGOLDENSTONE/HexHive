class_name Health
extends Node
## Reusable health component. Attach as a child of any damageable entity.
## Tracks HP, exposes take_damage()/heal(), and emits signals on changes.

## Emitted when this entity takes damage. amount > 0.
signal damaged(amount: float, current: float, maximum: float)

## Emitted when this entity is healed. amount > 0.
signal healed(amount: float, current: float, maximum: float)

## Emitted when HP reaches zero. Fires exactly once per life.
signal died()

## Maximum HP. Set this on creation; modify via set_max_hp() to scale.
@export var max_hp: float = 100.0

## Whether this entity can take damage right now (immune when false).
@export var invulnerable: bool = false

## Current HP. Initialised to max_hp in _ready.
var current_hp: float = -1.0

## True after died() has fired. Prevents duplicate death handling.
var is_dead: bool = false


func _ready() -> void:
	if current_hp < 0.0:
		current_hp = max_hp


## Apply damage. Returns the actual damage dealt (after invulnerability/clamp).
func take_damage(amount: float) -> float:
	if is_dead or invulnerable or amount <= 0.0:
		return 0.0
	var actual: float = minf(amount, current_hp)
	current_hp -= actual
	damaged.emit(actual, current_hp, max_hp)
	if current_hp <= 0.0:
		is_dead = true
		died.emit()
	return actual


## Restore HP up to max_hp. Returns the actual amount healed.
func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before: float = current_hp
	current_hp = minf(current_hp + amount, max_hp)
	var actual: float = current_hp - before
	if actual > 0.0:
		healed.emit(actual, current_hp, max_hp)
	return actual


## Reset HP to full and clear death state.
func revive(to_hp: float = -1.0) -> void:
	is_dead = false
	current_hp = to_hp if to_hp > 0.0 else max_hp


## Update max_hp. If clamp is true, current_hp is reduced to fit.
func set_max_hp(value: float, clamp_current: bool = true) -> void:
	max_hp = maxf(value, 1.0)
	if clamp_current and current_hp > max_hp:
		current_hp = max_hp


## Returns HP as a 0-1 fraction.
func get_fraction() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(current_hp / max_hp, 0.0, 1.0)
