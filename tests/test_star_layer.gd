extends SceneTree


const STAR_LAYER := preload("res://scripts/world/star_layer.gd")
const BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))


func _init() -> void:
	var failures: Array[String] = []

	await _test_stars_fill_sector_not_viewport(failures)
	await _test_same_seed_produces_same_layout(failures)
	await _test_different_seed_produces_different_layout(failures)

	for failure in failures:
		printerr("FAIL: ", failure)

	if failures.is_empty():
		print("ALL STAR LAYER TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("FAILED %d TESTS" % failures.size())
		quit(1)


func _make_layer(count: int) -> Node2D:
	var layer := Node2D.new()
	layer.set_script(STAR_LAYER)
	layer.star_count = count
	return layer


func _positions(layer: Node2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for child in layer.get_children():
		result.append((child as Node2D).position)
	return result


func _test_stars_fill_sector_not_viewport(failures: Array[String]) -> void:
	var layer := _make_layer(300)
	root.add_child(layer)
	await physics_frame

	layer.build_stars(BOUNDS, 1729)

	if layer.get_child_count() != 300:
		failures.append("Star layer: expected 300 stars, got %d" % layer.get_child_count())

	var max_x := 0.0
	for position in _positions(layer):
		if not BOUNDS.has_point(position):
			failures.append("Star layer: star placed outside sector at %s" % str(position))
			break
		max_x = maxf(max_x, position.x)

	# With 300 stars across 8000px, the furthest should be far beyond the old
	# 1152px viewport width. This is what proves stars moved to sector space.
	if max_x < 4000.0:
		failures.append("Star layer: stars are clustered near the origin, max x %f" % max_x)

	layer.queue_free()
	await physics_frame


func _test_same_seed_produces_same_layout(failures: Array[String]) -> void:
	var first := _make_layer(50)
	var second := _make_layer(50)
	root.add_child(first)
	root.add_child(second)
	await physics_frame

	first.build_stars(BOUNDS, 4242)
	second.build_stars(BOUNDS, 4242)

	if _positions(first) != _positions(second):
		failures.append("Star layer: the same seed must produce an identical layout")

	first.queue_free()
	second.queue_free()
	await physics_frame


func _test_different_seed_produces_different_layout(failures: Array[String]) -> void:
	var first := _make_layer(50)
	var second := _make_layer(50)
	root.add_child(first)
	root.add_child(second)
	await physics_frame

	first.build_stars(BOUNDS, 1)
	second.build_stars(BOUNDS, 2)

	if _positions(first) == _positions(second):
		failures.append("Star layer: different seeds must produce different layouts")

	first.queue_free()
	second.queue_free()
	await physics_frame
