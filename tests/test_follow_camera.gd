extends SceneTree


const CAMERA_SCRIPT := preload("res://scripts/world/follow_camera.gd")


func _init() -> void:
	var failures: Array[String] = []

	await _test_limits_come_from_sector_bounds(failures)
	await _test_camera_tracks_target(failures)
	await _test_look_ahead_leads_the_velocity(failures)
	await _test_look_ahead_is_capped(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL FOLLOW CAMERA TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


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
