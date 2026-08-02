extends Node


var touch_rotate_left: bool = false
var touch_rotate_right: bool = false
var touch_thrust: bool = false
var touch_shoot: bool = false


func get_turn_axis() -> float:
	var keyboard_axis := Input.get_axis("rotate_left", "rotate_right")
	var touch_axis := float(touch_rotate_right) - float(touch_rotate_left)
	return clampf(keyboard_axis + touch_axis, -1.0, 1.0)


func is_thrust_pressed() -> bool:
	return Input.is_action_pressed("thrust") or touch_thrust


func is_shoot_pressed() -> bool:
	return Input.is_action_pressed("shoot") or touch_shoot


func set_touch_action(action: StringName, pressed: bool) -> void:
	match action:
		&"rotate_left":
			touch_rotate_left = pressed
		&"rotate_right":
			touch_rotate_right = pressed
		&"thrust":
			touch_thrust = pressed
		&"shoot":
			touch_shoot = pressed


func clear_touch_actions() -> void:
	touch_rotate_left = false
	touch_rotate_right = false
	touch_thrust = false
	touch_shoot = false
