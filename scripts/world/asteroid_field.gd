extends Node2D
class_name AsteroidField


signal field_cleared(field: Node2D)

@export var field_name: StringName
@export var field_radius: float = 360.0
@export var asteroid_budget: int = 4

var _active_asteroids: int = 0
var _cleared_emitted: bool = false


## A field is the unit of activation, not the rock: one distance check per
## field instead of one per rock, and the rocks a field owns are exactly the
## subtree `Activation` puts to sleep with it. Registered here rather than by
## `Sector.place_content()` so a field instanced anywhere -- including straight
## from the scene in a test -- is activatable without the caller knowing to
## enrol it.
func _ready() -> void:
	add_to_group(Activation.GROUP_ASTEROID_FIELDS)


## The radius the field's rocks are scattered over, so `Activation` wakes the
## field when its edge comes into range rather than when its centre does. A
## 560-unit field woken on its centre would have rocks appearing well inside
## the player's view.
func get_activation_extent() -> float:
	return maxf(0.0, field_radius)


func seed_field(rng: RandomNumberGenerator, asteroid_scene: PackedScene, visual_assets: Array[Resource]) -> void:
	_clear_seeded_asteroids()
	_active_asteroids = 0
	_cleared_emitted = false

	if asteroid_scene == null:
		_emit_cleared_if_ready()
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

	_emit_cleared_if_ready()


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
