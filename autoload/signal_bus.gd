extends Node
## Central signal bus for cross-system communication.
## All game-wide signals live here so modules never reference each other directly.

# -- Day/Night Cycle --

## Emitted when the game phase changes. phase is "day" or "night".
signal phase_changed(phase: StringName)

## Emitted at the start of a new day. day_number starts at 1.
signal day_started(day_number: int)

## Emitted at the start of a new night. night_number starts at 0.
signal night_started(night_number: int)

## Emitted when all enemies in a day wave are cleared (triggers night transition).
signal day_wave_cleared()

## Emitted when the player requests to start the next day.
signal start_day_requested()
