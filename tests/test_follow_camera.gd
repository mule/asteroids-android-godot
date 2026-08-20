extends SceneTree


const CAMERA_SCRIPT := preload("res://scripts/world/follow_camera.gd")


func _init() -> void:
	var failures: Array[String] = []

	await _test_limits_come_from_sector_bounds(failures)
	await _test_camera_tracks_target(failures)
	await _test_look_ahead_leads_the_velocity(failures)
	await _test_look_ahead_is_capped(failures)
	await _test_look_ahead_moves_the_camera_while_flying(failures)
	await _test_retarget_clears_the_previous_look_ahead(failures)
	await _test_view_never_leaves_the_sector(failures)
	await _test_a_wrapping_ship_stays_on_screen(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL FOLLOW CAMERA TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


class Mover:
	extends Node2D

	var velocity: Vector2 = Vector2.ZERO


func _make_camera() -> Camera2D:
	var camera := Camera2D.new()
	camera.set_script(CAMERA_SCRIPT)
	return camera


func _test_limits_come_from_sector_bounds(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	camera.apply_sector_limits(Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0)))

	if camera.limit_left != 0:
		failures.append("Camera limits: expected limit_left 0, got %d" % camera.limit_left)
	if camera.limit_top != 0:
		failures.append("Camera limits: expected limit_top 0, got %d" % camera.limit_top)
	if camera.limit_right != 8000:
		failures.append("Camera limits: expected limit_right 8000, got %d" % camera.limit_right)
	if camera.limit_bottom != 6000:
		failures.append("Camera limits: expected limit_bottom 6000, got %d" % camera.limit_bottom)

	camera.queue_free()
	await physics_frame


func _test_camera_tracks_target(failures: Array[String]) -> void:
	var camera := _make_camera()
	var target := Node2D.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	camera.set_target(target)
	target.global_position = Vector2(4000.0, 3000.0)

	for _step in 10:
		await physics_frame

	var distance := camera.global_position.distance_to(target.global_position)
	if distance > 400.0:
		failures.append("Camera tracking: camera did not converge on target, distance %f" % distance)

	camera.queue_free()
	target.queue_free()
	await physics_frame


func _test_look_ahead_leads_the_velocity(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	var lead: Vector2 = camera.compute_look_ahead(Vector2(500.0, 0.0))
	if lead.x <= 0.0:
		failures.append("Look-ahead: rightward velocity must lead right, got %f" % lead.x)
	if absf(lead.y) > 0.001:
		failures.append("Look-ahead: zero y velocity must not lead vertically, got %f" % lead.y)

	var still: Vector2 = camera.compute_look_ahead(Vector2.ZERO)
	if still != Vector2.ZERO:
		failures.append("Look-ahead: a stationary ship must have no lead")

	camera.queue_free()
	await physics_frame


func _test_look_ahead_is_capped(failures: Array[String]) -> void:
	var camera := _make_camera()
	root.add_child(camera)
	await physics_frame

	# A very fast ship must not push the camera arbitrarily far ahead, or the
	# ship leaves the screen entirely.
	var lead: Vector2 = camera.compute_look_ahead(Vector2(100000.0, 0.0))
	if lead.length() > camera.max_look_ahead + 0.001:
		failures.append("Look-ahead: must be capped at max_look_ahead, got %f" % lead.length())

	camera.queue_free()
	await physics_frame


func _test_look_ahead_moves_the_camera_while_flying(failures: Array[String]) -> void:
	# A bare Node2D has no "velocity" property, so a target without one only ever
	# exercises the zero-velocity shortcut in _physics_process. Use a target that
	# actually carries velocity or the whole look-ahead path goes untested.
	var camera := _make_camera()
	var target := Mover.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	camera.set_target(target)
	target.velocity = Vector2(2000.0, 0.0)
	target.global_position = Vector2(4000.0, 3000.0)

	for _step in 60:
		await physics_frame

	var offset := camera.global_position - target.global_position
	if offset.x <= 0.0:
		failures.append("Look-ahead: camera must lead a rightward flight, offset %s" % offset)
	if offset.length() > camera.max_look_ahead + 0.001:
		failures.append("Look-ahead: camera lead %f exceeded the cap" % offset.length())

	camera.queue_free()
	target.queue_free()
	await physics_frame


func _test_retarget_clears_the_previous_look_ahead(failures: Array[String]) -> void:
	# Respawning re-targets the camera so the view does not slide across the
	# sector. reset_smoothing() only clears Camera2D's own state, so a look-ahead
	# left over from the flight before death would teleport the camera back off
	# the ship on the very next physics frame.
	var camera := _make_camera()
	var target := Mover.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	camera.set_target(target)
	target.velocity = Vector2(2000.0, 0.0)
	target.global_position = Vector2(4000.0, 3000.0)

	for _step in 60:
		await physics_frame

	# Respawn: the ship is placed at the sector centre with no velocity.
	target.velocity = Vector2.ZERO
	target.global_position = Vector2(4000.0, 3000.0)
	camera.set_target(target)

	if camera.global_position != target.global_position:
		failures.append(
			"Respawn: camera must snap onto the ship, got %s" % camera.global_position
		)

	await physics_frame

	var drift := camera.global_position.distance_to(target.global_position)
	if drift > 0.001:
		failures.append("Respawn: camera drifted %f px off the ship after re-targeting" % drift)

	camera.queue_free()
	target.queue_free()
	await physics_frame


func _test_view_never_leaves_the_sector(failures: Array[String]) -> void:
	# "The camera never shows outside the sector" is an acceptance criterion of
	# #45 and the one that has to hold at every wall the ship can reach. The
	# camera *node* is allowed outside -- it sits on the ship, and look-ahead
	# pushes it further -- so assert on the rendered view instead:
	# get_screen_center_position() is where Camera2D's limits actually bite.
	var camera := _make_camera()
	var target := Node2D.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	camera.apply_sector_limits(bounds)

	var half_view: Vector2 = root.get_visible_rect().size * 0.5
	var overshoots: Array[Vector2] = [
		bounds.position - Vector2(4000.0, 4000.0),
		Vector2(bounds.end.x + 4000.0, bounds.position.y - 4000.0),
		bounds.end + Vector2(4000.0, 4000.0),
		Vector2(bounds.position.x - 4000.0, bounds.end.y + 4000.0),
	]

	for overshoot in overshoots:
		target.global_position = overshoot
		camera.set_target(target)

		for _step in 20:
			await physics_frame

		var view := Rect2(camera.get_screen_center_position() - half_view, half_view * 2.0)
		if not bounds.encloses(view):
			failures.append(
				"Sector limits: view %s left the sector %s with the ship at %s"
				% [view, bounds, overshoot]
			)

	camera.queue_free()
	target.queue_free()
	await physics_frame


func _test_a_wrapping_ship_stays_on_screen(failures: Array[String]) -> void:
	# player_ship wraps at the sector edge until #46 replaces wrapping with
	# containment, and a wrap moves the ship the full width of the world in one
	# frame. Smoothing across that pans the view over the whole sector for about
	# a second with the ship off-screen the entire way. The camera has to cut.
	var camera := _make_camera()
	var target := Mover.new()
	root.add_child(camera)
	root.add_child(target)
	await physics_frame

	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	camera.apply_sector_limits(bounds)
	target.velocity = Vector2(500.0, 0.0)
	target.global_position = Vector2(bounds.end.x - 40.0, bounds.get_center().y)
	camera.set_target(target)

	# Fly at the right wall long enough for the look-ahead to build up.
	for _step in 30:
		await physics_frame

	# The wrap itself: the far right edge becomes the far left edge.
	target.global_position = Vector2(bounds.position.x + 40.0, bounds.get_center().y)
	await physics_frame

	var half_view: Vector2 = root.get_visible_rect().size * 0.5
	var view := Rect2(camera.get_screen_center_position() - half_view, half_view * 2.0)
	if not view.has_point(target.global_position):
		failures.append(
			"Wrap: ship at %s must still be on screen the frame after wrapping, view %s"
			% [target.global_position, view]
		)

	camera.queue_free()
	target.queue_free()
	await physics_frame
