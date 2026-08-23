extends SceneTree


const GAME_SCENE := "res://scenes/game/Game.tscn"
const ASTEROID_SCENE := "res://scenes/entities/Asteroid.tscn"
const ASTEROID_MEDIUM := 1


func _init() -> void:
	var failures: Array[String] = []
	var first := await _capture_game_snapshot()
	var second := await _capture_game_snapshot()

	if first != second:
		failures.append("same seed produced different asteroid snapshots")

	var visual_ids := {}
	for entry: Dictionary in first:
		visual_ids[entry["visual_asset_id"]] = true
	if visual_ids.size() < 2:
		failures.append("seeded asteroid fields did not contain multiple asteroid visuals")

	var split_snapshot := await _capture_split_snapshot()
	if split_snapshot.size() != 2:
		failures.append("split smoke expected two child asteroids")
	for entry: Dictionary in split_snapshot:
		if entry["size_tier"] != ASTEROID_MEDIUM:
			failures.append("split child had unexpected size tier")
		if str(entry["visual_asset_id"]).is_empty():
			failures.append("split child had no visual asset id")

	if not await _fallback_asteroid_has_visual():
		failures.append("empty visual pool fallback did not keep a valid asteroid visual")

	for failure: String in failures:
		printerr(failure)
	if failures.is_empty():
		print("OK runtime asteroid variants are deterministic")
		quit(0)
	else:
		quit(1)


func _capture_game_snapshot() -> Array:
	var game := _instantiate_game()
	root.add_child(game)
	await process_frame
	game._start_new_game()
	var snapshot := _stable_snapshot(game.get_active_asteroid_debug_snapshot())
	root.remove_child(game)
	game.free()
	return snapshot


func _capture_split_snapshot() -> Array:
	var game := _instantiate_game()
	root.add_child(game)
	await process_frame
	game._start_new_game()
	# Starting a run seeds the sector's asteroid fields, and the debug snapshot
	# reports every rock in the `asteroids` group. This check is about the split
	# children alone, so clear the field rocks before splitting -- freed outright
	# rather than queued, because the snapshot is taken in this same frame.
	for asteroid in game.get_tree().get_nodes_in_group("asteroids"):
		asteroid.get_parent().remove_child(asteroid)
		asteroid.free()
	game._spawn_split_asteroids(ASTEROID_MEDIUM, Vector2(200, 200), Vector2(80, 0))
	var snapshot := _stable_snapshot(game.get_active_asteroid_debug_snapshot())
	root.remove_child(game)
	game.free()
	return snapshot


func _fallback_asteroid_has_visual() -> bool:
	var packed_scene := load(ASTEROID_SCENE) as PackedScene
	if packed_scene == null:
		return false
	var asteroid := packed_scene.instantiate()
	root.add_child(asteroid)
	asteroid.setup(0, Vector2.ZERO, null, 0.0)
	await process_frame
	var has_visual := not str(asteroid.get_visual_asset_id()).is_empty()
	asteroid.queue_free()
	await process_frame
	return has_visual


func _instantiate_game() -> Node:
	var packed_scene := load(GAME_SCENE) as PackedScene
	var game := packed_scene.instantiate()
	game.random_seed = 1729
	game.starting_wave = 1
	game.auto_start = false
	return game


func _stable_snapshot(snapshot: Array[Dictionary]) -> Array:
	var stable := []
	for entry: Dictionary in snapshot:
		stable.append({
			"position": _stable_vector(entry["position"]),
			"velocity": _stable_vector(entry["velocity"]),
			"size_tier": entry["size_tier"],
			"visual_asset_id": str(entry["visual_asset_id"]),
			"rotation": snappedf(entry["rotation"], 0.0001),
		})
	return stable


func _stable_vector(value: Vector2) -> Vector2:
	return Vector2(snappedf(value.x, 0.0001), snappedf(value.y, 0.0001))
