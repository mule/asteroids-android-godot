extends SceneTree


const STAR_LAYER := preload("res://scripts/world/star_layer.gd")
const GAME_SCENE := "res://scenes/game/Game.tscn"
const BOUNDS := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))

## The pre-epic starfield put 90 stars on every screen. A layer scattered over
## the whole sector instead of over the band its parallax can reach drops that
## to about eleven, which reads as an empty void rather than as depth. This is
## the floor below which the background has silently gone missing again.
const MIN_STARS_ON_SCREEN := 25


func _init() -> void:
	var failures: Array[String] = []

	await _test_stars_fill_sector_not_viewport(failures)
	await _test_same_seed_produces_same_layout(failures)
	await _test_different_seed_produces_different_layout(failures)
	await _test_rebuilding_replaces_the_previous_layout(failures)
	_test_parallax_span_is_the_band_a_layer_can_draw(failures)
	await _test_the_shipped_game_never_shows_an_empty_sky(failures)
	await _test_far_stars_drift_slower_than_near_stars(failures)

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


func _test_rebuilding_replaces_the_previous_layout(failures: Array[String]) -> void:
	var layer := _make_layer(20)
	root.add_child(layer)
	await physics_frame

	layer.build_stars(BOUNDS, 7)
	var first := _positions(layer)
	layer.build_stars(BOUNDS, 8)

	# Straight after the second call, not a frame later: queue_free() alone
	# would leave the first 20 stars parented and drawn over the new layout.
	if layer.get_child_count() != 20:
		failures.append(
			"Star layer: a rebuild must replace the layout, got %d stars" % layer.get_child_count()
		)

	if _positions(layer) == first:
		failures.append("Star layer: a rebuild must use the new seed")

	layer.queue_free()
	await physics_frame


func _test_parallax_span_is_the_band_a_layer_can_draw(failures: Array[String]) -> void:
	var view := Vector2(1152.0, 648.0)

	# A layer pinned to the screen never scrolls, so one screen is all of it.
	var pinned := STAR_LAYER.parallax_span(BOUNDS, Vector2.ZERO, view)
	if not pinned.size.is_equal_approx(view):
		failures.append("Parallax span: a 0.0 layer should span one screen, got %s" % str(pinned.size))

	# A layer that scrolls with the world needs the sector and no more.
	var world := STAR_LAYER.parallax_span(BOUNDS, Vector2.ONE, view)
	if not world.size.is_equal_approx(BOUNDS.size):
		failures.append("Parallax span: a 1.0 layer should span the sector, got %s" % str(world.size))

	var far := STAR_LAYER.parallax_span(BOUNDS, Vector2(0.15, 0.15), view)
	var expected := Vector2(0.15 * 8000.0 + 1152.0, 0.15 * 6000.0 + 648.0)
	if not far.size.is_equal_approx(expected):
		failures.append("Parallax span: expected %s for a 0.15 layer, got %s" % [str(expected), str(far.size)])

	if not far.position.is_equal_approx(BOUNDS.position):
		failures.append("Parallax span: the band starts where the sector starts")

	# Anything a scroll_scale would ask for past the sector is still capped.
	var huge := STAR_LAYER.parallax_span(BOUNDS, Vector2(4.0, 4.0), view)
	if not huge.size.is_equal_approx(BOUNDS.size):
		failures.append("Parallax span: must never exceed the sector, got %s" % str(huge.size))


func _boot_game() -> Node:
	root.size = Vector2i(1152, 648)
	await process_frame

	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame

	# Take the camera off the ship so a test can put it where it likes.
	var camera: Camera2D = game.get_node("FollowCamera")
	camera.set_target(null)
	camera.position_smoothing_enabled = false
	return game


func _stars_on_screen(layer: Node2D, view: Vector2) -> int:
	var count := 0
	for child in layer.get_children():
		var screen: Vector2 = (child as Node2D).get_global_transform_with_canvas().origin
		if screen.x >= 0.0 and screen.x <= view.x and screen.y >= 0.0 and screen.y <= view.y:
			count += 1
	return count


func _look_at(camera: Camera2D, where: Vector2) -> void:
	camera.global_position = where
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame


## The one test that would have caught the sparse sky: it counts what the real
## Game.tscn actually renders through its real Parallax2D nodes, rather than
## re-deriving the span formula the implementation already used.
func _test_the_shipped_game_never_shows_an_empty_sky(failures: Array[String]) -> void:
	var game := await _boot_game()
	var view := root.get_visible_rect().size
	var camera: Camera2D = game.get_node("FollowCamera")

	if view.x < 1000.0 or view.y < 600.0:
		failures.append("Shipped game: the test viewport is %s, too small to judge star density" % str(view))
		game.queue_free()
		await process_frame
		return

	var layers: Array[Node2D] = []
	for path in ["StarsFar/Layer", "StarsMid/Layer"]:
		var layer := game.get_node_or_null(path)
		if layer == null or not (layer is StarLayer):
			failures.append("Shipped game: %s is missing or is not a StarLayer" % path)
			game.queue_free()
			await process_frame
			return
		if not (layer.get_parent() is Parallax2D):
			failures.append("Shipped game: %s must hang off a Parallax2D to scroll at all" % path)
		if layer.get_child_count() != layer.star_count:
			failures.append(
				"Shipped game: %s built %d of its %d stars" % [path, layer.get_child_count(), layer.star_count]
			)
		layers.append(layer)

	if (layers[0].get_parent() as Parallax2D).scroll_scale.x >= (layers[1].get_parent() as Parallax2D).scroll_scale.x:
		failures.append("Shipped game: the far layer must scroll slower than the mid layer")

	var sector_bounds: Rect2 = game.get_node("Sector").get_bounds()
	for layer in layers:
		for child in layer.get_children():
			if not sector_bounds.has_point((child as Node2D).position):
				failures.append("Shipped game: %s placed a star outside the sector" % layer.name)
				break

	var worst := 1 << 30
	var worst_where := Vector2.ZERO
	var x := sector_bounds.position.x
	while x <= sector_bounds.end.x:
		var y := sector_bounds.position.y
		while y <= sector_bounds.end.y:
			await _look_at(camera, Vector2(x, y))
			var visible := 0
			for layer in layers:
				visible += _stars_on_screen(layer, view)
			if visible < worst:
				worst = visible
				worst_where = Vector2(x, y)
			y += 800.0
		x += 800.0

	if worst < MIN_STARS_ON_SCREEN:
		failures.append(
			"Shipped game: only %d stars on screen with the camera at %s, below the %d floor"
			% [worst, str(worst_where), MIN_STARS_ON_SCREEN]
		)

	game.queue_free()
	await process_frame


## The issue's own acceptance criterion: far stars drift slower than near ones.
func _test_far_stars_drift_slower_than_near_stars(failures: Array[String]) -> void:
	var game := await _boot_game()
	var camera: Camera2D = game.get_node("FollowCamera")
	var far: Node2D = game.get_node("StarsFar/Layer").get_child(0)
	var mid: Node2D = game.get_node("StarsMid/Layer").get_child(0)
	var world: Node2D = game.get_node("Entities/PlayerShip")

	var pan := 1000.0
	await _look_at(camera, Vector2(2000.0, 3000.0))
	var before := [
		far.get_global_transform_with_canvas().origin,
		mid.get_global_transform_with_canvas().origin,
		world.get_global_transform_with_canvas().origin,
	]
	await _look_at(camera, Vector2(2000.0 + pan, 3000.0))
	var drift_far: float = absf(far.get_global_transform_with_canvas().origin.x - before[0].x)
	var drift_mid: float = absf(mid.get_global_transform_with_canvas().origin.x - before[1].x)
	var drift_world: float = absf(world.get_global_transform_with_canvas().origin.x - before[2].x)

	if not (drift_far > 0.0 and drift_far < drift_mid and drift_mid < drift_world):
		failures.append(
			"Parallax: panning %fpx should drift far < mid < world, got %f / %f / %f"
			% [pan, drift_far, drift_mid, drift_world]
		)

	game.queue_free()
	await process_frame
