extends SceneTree


const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")
const SECTOR_DEFINITION := preload("res://assets/sectors/sector_default.tres")
const GAME_SCENE := "res://scenes/game/Game.tscn"


func _init() -> void:
	var failures: Array[String] = []

	_test_wrap_matches_legacy_behavior(failures)
	_test_clamp_keeps_position_inside(failures)
	_test_is_outside_respects_radius(failures)
	_test_reflect_only_when_moving_outward(failures)
	_test_edge_pressure_ramps_inward(failures)
	await _test_sector_is_never_smaller_than_the_viewport(failures)
	await _test_entities_track_a_viewport_resize(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL WORLD BOUNDS TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _test_wrap_matches_legacy_behavior(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(1152.0, 648.0))
	var margin := 32.0

	# Exiting the left edge reappears at the right, exactly as the old
	# _wrap_to_visible_viewport did.
	var wrapped := WORLD_BOUNDS.wrap_to_bounds(Vector2(-40.0, 300.0), bounds, margin)
	if not is_equal_approx(wrapped.x, 1184.0):
		failures.append("Wrap: expected x 1184.0 crossing left edge, got %f" % wrapped.x)

	wrapped = WORLD_BOUNDS.wrap_to_bounds(Vector2(1200.0, 300.0), bounds, margin)
	if not is_equal_approx(wrapped.x, -32.0):
		failures.append("Wrap: expected x -32.0 crossing right edge, got %f" % wrapped.x)

	# A position well inside is untouched.
	var inside := Vector2(500.0, 300.0)
	if WORLD_BOUNDS.wrap_to_bounds(inside, bounds, margin) != inside:
		failures.append("Wrap: interior position must not move")


func _test_clamp_keeps_position_inside(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	var clamped := WORLD_BOUNDS.clamp_to_sector(Vector2(-500.0, 9999.0), bounds, 40.0)

	if not is_equal_approx(clamped.x, 40.0):
		failures.append("Clamp: expected x 40.0, got %f" % clamped.x)
	if not is_equal_approx(clamped.y, 5960.0):
		failures.append("Clamp: expected y 5960.0, got %f" % clamped.y)


func _test_is_outside_respects_radius(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))

	if WORLD_BOUNDS.is_outside(Vector2(4000.0, 3000.0), bounds, 40.0):
		failures.append("is_outside: sector centre reported outside")
	if not WORLD_BOUNDS.is_outside(Vector2(10.0, 3000.0), bounds, 40.0):
		failures.append("is_outside: position within radius of the wall must count as outside")


func _test_reflect_only_when_moving_outward(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))

	# At the left wall, moving left: reflect.
	var reflected := WORLD_BOUNDS.reflect_velocity_at_edge(
		Vector2(0.0, 3000.0), Vector2(-120.0, 40.0), bounds, 0.0
	)
	if reflected.x <= 0.0:
		failures.append("Reflect: outward x velocity must flip, got %f" % reflected.x)
	if not is_equal_approx(reflected.y, 40.0):
		failures.append("Reflect: tangential y velocity must be preserved, got %f" % reflected.y)

	# At the left wall, already moving right: leave alone. Without this guard an
	# entity resting on the wall flips every frame and jitters in place.
	reflected = WORLD_BOUNDS.reflect_velocity_at_edge(
		Vector2(0.0, 3000.0), Vector2(120.0, 0.0), bounds, 0.0
	)
	if not is_equal_approx(reflected.x, 120.0):
		failures.append("Reflect: inward velocity must not flip, got %f" % reflected.x)


func _test_edge_pressure_ramps_inward(failures: Array[String]) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	var margin := 600.0

	if WORLD_BOUNDS.edge_pressure(Vector2(4000.0, 3000.0), bounds, margin) != Vector2.ZERO:
		failures.append("Edge pressure: sector interior must be zero")

	var at_inner_edge := WORLD_BOUNDS.edge_pressure(Vector2(600.0, 3000.0), bounds, margin)
	if absf(at_inner_edge.x) > 0.001:
		failures.append("Edge pressure: must be zero at the inner edge of the band, got %f" % at_inner_edge.x)

	var at_wall := WORLD_BOUNDS.edge_pressure(Vector2(0.0, 3000.0), bounds, margin)
	if not is_equal_approx(at_wall.x, 1.0):
		failures.append("Edge pressure: must be 1.0 pointing inward at the wall, got %f" % at_wall.x)

	var half_way := WORLD_BOUNDS.edge_pressure(Vector2(300.0, 3000.0), bounds, margin)
	if absf(half_way.x - 0.5) > 0.01:
		failures.append("Edge pressure: must ramp linearly, expected 0.5, got %f" % half_way.x)

	var right_wall := WORLD_BOUNDS.edge_pressure(Vector2(8000.0, 3000.0), bounds, margin)
	if not is_equal_approx(right_wall.x, -1.0):
		failures.append("Edge pressure: right wall must push left, got %f" % right_wall.x)


func _test_sector_is_never_smaller_than_the_viewport(failures: Array[String]) -> void:
	# project.godot stretches with aspect "expand", so the visible rect is only
	# 1152x648 at exactly 16:9 and grows on every other window shape. The
	# default sector is viewport-sized, so it must track that growth or
	# entities wrap in the middle of the screen. See scripts/world/sector.gd.
	var sector := Sector.new()
	if sector == null:
		# A parse error in sector.gd makes .new() return null. Without this the
		# suite would sail past every assertion below and still report green.
		failures.append("Sector: could not instantiate scripts/world/sector.gd")
		return

	sector.definition = SECTOR_DEFINITION
	root.add_child(sector)
	await process_frame

	var visible_rect := sector.get_viewport_rect()
	var bounds: Rect2 = sector.get_bounds()

	if not bounds.encloses(visible_rect):
		failures.append(
			"Sector: bounds %s must cover the visible rect %s" % [bounds, visible_rect]
		)

	if not bounds.encloses(SECTOR_DEFINITION.get_bounds()):
		failures.append("Sector: bounds %s must cover the sector definition" % bounds)

	sector.queue_free()
	await process_frame


func _test_entities_track_a_viewport_resize(failures: Array[String]) -> void:
	# Before #44 every entity re-read get_viewport_rect() each physics frame, so
	# wrapping followed a window resize for free. Bounds are now handed out once
	# at spawn, so game.gd has to re-push them or the ship keeps wrapping
	# against the size the window had when it was created.
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var original_size := root.size
	root.size = Vector2i(1400, 500)
	await process_frame
	await process_frame

	var visible_size := root.get_visible_rect().size
	if visible_size == Vector2(original_size):
		failures.append("Resize: the harness did not actually resize the viewport")

	var ship_bounds: Rect2 = game.player_ship.sector_bounds
	if ship_bounds.size != visible_size:
		failures.append(
			"Resize: player bounds %s must follow the visible rect %s"
			% [ship_bounds.size, visible_size]
		)

	root.size = original_size
	game.queue_free()
	await process_frame
