class_name Damage
extends RefCounted
## Data container for a damage event.
## Tags describe the source attack (e.g. &"ranged", &"melee", &"piercing").
## DamageTable.compute() consumes this + target tags to produce the final amount.

## Raw damage amount before modifiers.
var base_amount: float = 0.0

## Tags describing the attacker / ability (e.g. &"ranged", &"piercing", &"honey").
var tags: Array[StringName] = []

## Optional source node reference (attacker).
var source: Node = null


func _init(amount: float = 0.0, attack_tags: Array[StringName] = [], src: Node = null) -> void:
	base_amount = amount
	tags = attack_tags
	source = src


## Create a lightweight copy for safe mutation.
func duplicate_damage() -> Damage:
	return Damage.new(base_amount, tags.duplicate(), source)
