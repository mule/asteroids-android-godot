extends Camera2D


@export var look_ahead_seconds: float = 0.45
@export var max_look_ahead: float = 260.0
@export var smoothing_speed: float = 5.0
@export var look_ahead_smoothing: float = 3.0

var target: Node2D
var current_look_ahead: Vector2 = Vector2.ZERO
var last_target_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	# Drag margins keep small corrections from shaking the whole view.
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = 0.15
	drag_right_margin = 0.15
	drag_top_margin = 0.15
	drag_bottom_margin = 0.15
	make_current()


func set_target(node: Node2D) -> void:
	target = node

	if target != null:
		# Drop the look-ahead the previous target had built up before snapping.
		# reset_smoothing() only clears Camera2D's own interpolation state, so a
		# stale lead would teleport the camera straight back off the ship on the
		# next physics frame and slide home over a second -- exactly the respawn
		# slide re-targeting exists to prevent.
		current_look_ahead = Vector2.ZERO
		last_target_position = target.global_position
		global_position = target.global_position
		reset_smoothing()


func apply_sector_limits(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


func compute_look_ahead(velocity: Vector2) -> Vector2:
	return (velocity * look_ahead_seconds).limit_length(max_look_ahead)


## A single-frame displacement of more than one screen is a teleport, not
## flight: the ship would have to cross the whole viewport in one physics tick.
func _target_teleported() -> bool:
	var screen_size := get_viewport_rect().size
	var step := last_target_position.distance_squared_to(target.global_position)
	return step > screen_size.length_squared()


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	# Nothing wraps since #46, so the routine sector-edge teleport this guard
	# was written for is gone; it stays as the safety net for any other
	# single-frame jump of the target that does not come through set_target().
	# position_smoothing_enabled would interpolate across such a jump, panning
	# the view over the entire sector for about a second with the ship
	# off-screen the whole way -- the player flies blind and can be killed
	# without seeing what hit them. Cut instead. The look-ahead is deliberately
	# kept rather than cleared: clearing it here would make the lead pop back in
	# over the next third of a second.
	var teleported := _target_teleported()

	var target_velocity: Vector2 = Vector2.ZERO
	if "velocity" in target:
		target_velocity = target.velocity

	var desired_look_ahead := compute_look_ahead(target_velocity)
	current_look_ahead = current_look_ahead.lerp(
		desired_look_ahead,
		clampf(look_ahead_smoothing * delta, 0.0, 1.0)
	)

	last_target_position = target.global_position
	global_position = target.global_position + current_look_ahead

	if teleported:
		reset_smoothing()
