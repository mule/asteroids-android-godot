extends Node2D
class_name AsteroidField


signal field_cleared(field: Node2D)

@export var field_name: StringName
@export var field_radius: float = 360.0
@export var asteroid_budget: int = 4

var _active_asteroids: int = 0
var _cleared_emitted: bool = false


func seed_field(rng: RandomNumberGenerator, asteroid_scene: PackedScene, visual_assets: Array[Resource]) -> void:
	_clear_seeded_asteroids()
	_active_asteroids = 0
	_cleared_emitted = false

	if asteroid_scene == null:
		_latch_empty_field()
		return

	for index in maxi(0, asteroid_budget):
		var asteroid := asteroid_scene.instantiate() as Area2D
		var visual_asset := _get_random_asteroid_visual_asset(rng, visual_assets)
		var initial_rotation := rng.randf_range(0.0, TAU)
		var velocity := _get_random_asteroid_velocity(rng)

		if asteroid.has_method("setup"):
			asteroid.setup(0, velocity, visual_asset, initial_rotation)

		add_child(asteroid)
		asteroid.add_to_group("asteroids")
		asteroid.position = _get_random_offset(rng)
		_active_asteroids += 1

		if asteroid.has_signal("destroyed"):
			asteroid.connect("destroyed", _on_asteroid_destroyed)

	_latch_empty_field()


func get_active_asteroid_count() -> int:
	return _active_asteroids


func is_cleared() -> bool:
	return _active_asteroids <= 0


func _on_asteroid_destroyed(
	asteroid: Area2D,
	size_tier: int,
	hit_position: Vector2,
	incoming_velocity: Vector2
) -> void:
	_active_asteroids = maxi(0, _active_asteroids - 1)
	_emit_cleared_if_ready()


## Seeding is not a clear.
##
## `game.gd`'s `_place_sector_content` connects `field_cleared` to the
## field-clear refuel BEFORE it calls `seed_field`, so anything emitted while
## seeding is paid out before the run has started. A field that ends up holding
## nothing -- an `asteroid_budget` of 0, or a null `asteroid_scene`, both legal
## on the exported SectorDefinition -- was never emptied by the player, and
## emitting for it handed out `field_clear_refuel` per field for a sector
## nobody had touched: the shipped five fields at a quarter tank each is more
## than the whole 100-unit tank that refuel is deliberately scoped to stay
## under, collected before the first shot.
##
## Latching `_cleared_emitted` rather than emitting keeps the signal a
## transition -- the beat a destroyed asteroid makes -- and stops a later
## destroy on some other field's rock finding this one still armed.
## `is_cleared()` continues to report the STATE for anything that polls.
func _latch_empty_field() -> void:
	if _active_asteroids <= 0:
		_cleared_emitted = true


func _emit_cleared_if_ready() -> void:
	if _cleared_emitted or not is_cleared():
		return

	_cleared_emitted = true
	field_cleared.emit(self)


func _get_random_offset(rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var distance := sqrt(rng.randf()) * maxf(0.0, field_radius)
	return Vector2.RIGHT.rotated(angle) * distance


func _get_random_asteroid_velocity(rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var speed := rng.randf_range(45.0, 105.0)
	return Vector2.RIGHT.rotated(angle) * speed


func _get_random_asteroid_visual_asset(rng: RandomNumberGenerator, visual_assets: Array[Resource]) -> Resource:
	var valid_assets := _get_valid_asteroid_visual_assets(visual_assets)
	if valid_assets.is_empty():
		return null

	return valid_assets[rng.randi_range(0, valid_assets.size() - 1)]


func _get_valid_asteroid_visual_assets(visual_assets: Array[Resource]) -> Array[Resource]:
	var valid_assets: Array[Resource] = []
	for asset: Resource in visual_assets:
		if (
			asset != null
			and asset.has_method("is_primary_polygon_valid")
			and asset.is_primary_polygon_valid()
		):
			valid_assets.append(asset)
	return valid_assets


func _clear_seeded_asteroids() -> void:
	for child in get_children():
		if child.is_in_group("asteroids"):
			child.queue_free()
