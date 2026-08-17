extends Node
## Global game state singleton.
##
## Tracks things that multiple systems care about:
##  - whether the player is on the wall or walking on the ground
##  - which quickdraw the rope is currently running through (for falls)
##  - simple event signals so decoupled systems can talk to each other
##
## Keep this tiny - per-entity logic lives on the entity's own script.

signal state_changed(new_state: State)
signal clipped_to_draw(draw_index: int)
signal fell(travelled_distance: float)
signal landed_back_on_ground
signal grip_pumped(hand: String)

enum State { ON_GROUND, CLIMBING, FALLING, RESTING }

var state: State = State.ON_GROUND:
	set(value):
		if value != state:
			state = value
			state_changed.emit(value)

## Highest draw index the rope has been clipped through (0 = first draw, -1 = none).
var last_clipped_draw: int = -1

## Total slack the belayer has paid out in meters. Updated by RopeSystem.
var rope_slack_m: float = 0.0

## Best height the climber has reached (for stats / restart logic).
var max_height_m: float = 0.0

func reset() -> void:
	state = State.ON_GROUND
	last_clipped_draw = -1
	rope_slack_m = 0.0
	max_height_m = 0.0
