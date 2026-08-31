extends RefCounted
class_name GravityField


const SURFACE_ACCELERATION_CAP_RATIO := 0.7
const PLAYER_MAX_THRUST_ACCELERATION := 360.0
const DEFAULT_INFLUENCE_MULTIPLIER := 4.0


static func accumulate(position: Vector2, sources: Array[Node]) -> Vector2:
	var total := Vector2.ZERO
	for source in sources:
		if source is Node2D:
			total += acceleration_from(position, source as Node2D)
	return total


static func acceleration_from(position: Vector2, source: Node2D) -> Vector2:
	if source == null or not is_instance_valid(source) or source.is_queued_for_deletion():
		return Vector2.ZERO

	var body_radius := _get_body_radius(source)
	var influence_radius := _get_influence_radius(source, body_radius)
	if body_radius <= 0.0 or influence_radius <= 0.0:
		return Vector2.ZERO

	var offset := source.global_position - position
	var distance := offset.length()
	if distance <= 0.0 or distance > influence_radius:
		return Vector2.ZERO

	var clamped_distance := maxf(distance, body_radius)
	var falloff := (body_radius / clamped_distance) * (body_radius / clamped_distance)
	var strength := max_surface_acceleration(PLAYER_MAX_THRUST_ACCELERATION) * falloff
	return offset / distance * strength


static func max_surface_acceleration(ship_acceleration: float) -> float:
	return maxf(0.0, ship_acceleration) * SURFACE_ACCELERATION_CAP_RATIO


static func _get_body_radius(source: Node2D) -> float:
	if source.has_method("get_body_radius"):
		return maxf(0.0, source.get_body_radius())

	var definition = source.get("definition")
	if definition != null and "body_radius" in definition:
		return maxf(0.0, definition.body_radius)

	return 0.0


static func _get_influence_radius(source: Node2D, body_radius: float) -> float:
	if source.has_method("get_influence_radius"):
		return maxf(0.0, source.get_influence_radius())

	var definition = source.get("definition")
	var multiplier := DEFAULT_INFLUENCE_MULTIPLIER
	if definition != null and "influence_multiplier" in definition:
		multiplier = definition.influence_multiplier

	return body_radius * maxf(0.0, multiplier)
