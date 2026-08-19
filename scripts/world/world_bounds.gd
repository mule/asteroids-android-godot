extends RefCounted
class_name WorldBounds

## Static bounds math for sector space. Preload as a const, following the
## scripts/material_runtime.gd idiom:
##   const WORLD_BOUNDS := preload("res://scripts/world/world_bounds.gd")


static func wrap_to_bounds(position: Vector2, bounds: Rect2, margin: float) -> Vector2:
	var minimum := bounds.position - Vector2.ONE * margin
	var maximum := bounds.end + Vector2.ONE * margin
	var wrapped := position

	if wrapped.x < minimum.x:
		wrapped.x = maximum.x
	elif wrapped.x > maximum.x:
		wrapped.x = minimum.x

	if wrapped.y < minimum.y:
		wrapped.y = maximum.y
	elif wrapped.y > maximum.y:
		wrapped.y = minimum.y

	return wrapped


static func clamp_to_sector(position: Vector2, bounds: Rect2, radius: float = 0.0) -> Vector2:
	return Vector2(
		clampf(position.x, bounds.position.x + radius, bounds.end.x - radius),
		clampf(position.y, bounds.position.y + radius, bounds.end.y - radius)
	)


static func is_outside(position: Vector2, bounds: Rect2, radius: float = 0.0) -> bool:
	return (
		position.x < bounds.position.x + radius
		or position.x > bounds.end.x - radius
		or position.y < bounds.position.y + radius
		or position.y > bounds.end.y - radius
	)


static func reflect_velocity_at_edge(
	position: Vector2,
	velocity: Vector2,
	bounds: Rect2,
	radius: float = 0.0
) -> Vector2:
	var reflected := velocity

	# Only flip when the entity is actually moving further out. Flipping
	# unconditionally makes an entity resting on the wall jitter every frame.
	if position.x <= bounds.position.x + radius and reflected.x < 0.0:
		reflected.x = -reflected.x
	elif position.x >= bounds.end.x - radius and reflected.x > 0.0:
		reflected.x = -reflected.x

	if position.y <= bounds.position.y + radius and reflected.y < 0.0:
		reflected.y = -reflected.y
	elif position.y >= bounds.end.y - radius and reflected.y > 0.0:
		reflected.y = -reflected.y

	return reflected


static func edge_pressure(position: Vector2, bounds: Rect2, margin: float) -> Vector2:
	## Inward push in the range 0.0 at the inner edge of the margin band to 1.0
	## at the wall. Exactly zero outside the band.
	if margin <= 0.0:
		return Vector2.ZERO

	var pressure := Vector2.ZERO

	var left_depth := (bounds.position.x + margin) - position.x
	if left_depth > 0.0:
		pressure.x += clampf(left_depth / margin, 0.0, 1.0)

	var right_depth := position.x - (bounds.end.x - margin)
	if right_depth > 0.0:
		pressure.x -= clampf(right_depth / margin, 0.0, 1.0)

	var top_depth := (bounds.position.y + margin) - position.y
	if top_depth > 0.0:
		pressure.y += clampf(top_depth / margin, 0.0, 1.0)

	var bottom_depth := position.y - (bounds.end.y - margin)
	if bottom_depth > 0.0:
		pressure.y -= clampf(bottom_depth / margin, 0.0, 1.0)

	return pressure
