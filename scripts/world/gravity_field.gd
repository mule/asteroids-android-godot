extends RefCounted
class_name GravityField


const SURFACE_ACCELERATION_CAP_RATIO := 0.7
const PLAYER_MAX_THRUST_ACCELERATION := 360.0
const DEFAULT_INFLUENCE_MULTIPLIER := 4.0

## The authored `gravity_strength` that fills the cap exactly. #51 committed
## 1400 for planets and 350 for moons -- a deliberate 4:1 -- and nothing read
## it, so a 76px moon pulled as hard as a 220px planet and a body authored with
## no gravity still pulled at the full cap.
##
## #52 is read as a CEILING here, which is what its safety rule says
## ("capped at 0.7x thrust") rather than what its implementation plan says
## ("normalized so the surface value equals the cap"). The equality reading
## leaves #51's data dead and makes a gravity-free body unauthorable; the
## ceiling reading keeps the safety guarantee and gives the authored number
## something to do.
const GRAVITY_STRENGTH_AT_CAP := 1400.0


## `ship_acceleration` is the thrust the ship can ACTUALLY produce right now,
## not the thrust it has at a full tank. See acceleration_from().
static func accumulate(
	position: Vector2,
	sources: Array[Node],
	ship_acceleration: float = PLAYER_MAX_THRUST_ACCELERATION
) -> Vector2:
	var total := Vector2.ZERO
	for source in sources:
		if source is Node2D:
			total += acceleration_from(position, source as Node2D, ship_acceleration)
	return total


## Gravity is capped against the thrust the ship can produce at this moment.
##
## Capping against FULL thrust left a fuel-dry ship trapped: surface gravity
## 0.7 x 360 = 252 against reserve thrust 0.25 x 360 = 90, so gravity won
## everywhere inside 1.673 x body_radius -- 18% of every influence disc -- and
## the player could not die out of it either, because PlayerShip's mask
## excludes CelestialBody's layer and nothing connects area_entered. That is
## the unwinnable soft-lock ship_systems.gd's reserve thrust exists to prevent
## and that #52 set out to avoid ("without ever creating a trap the player
## cannot escape").
##
## Scaling the cap with available thrust is a no-op at a full tank, so the
## shipped feel is unchanged; a dry ship feels the well weaken as it fails,
## which is odd physics but keeps both contracts -- reserve thrust stays a
## "survivable limp home", and gravity stays non-lethal.
##
## The default exists for callers that legitimately mean "at full thrust" --
## the escapability tests, and any caller with no ship in hand. Production
## passes the live value.
static func acceleration_from(
	position: Vector2,
	source: Node2D,
	ship_acceleration: float = PLAYER_MAX_THRUST_ACCELERATION
) -> Vector2:
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
	var strength := max_surface_acceleration(ship_acceleration) * _get_strength_ratio(source) * falloff
	return offset / distance * strength


static func max_surface_acceleration(ship_acceleration: float) -> float:
	return maxf(0.0, ship_acceleration) * SURFACE_ACCELERATION_CAP_RATIO


## How much of the cap this body fills, from its authored `gravity_strength`.
##
## A source carrying no definition is a plain gravity source and fills the cap,
## which is what the pre-#51 tests build and expect. A source that DOES carry a
## definition is authored content and is held to the number it declares --
## including 0.0, so a body with no gravity can be authored at all.
static func _get_strength_ratio(source: Node2D) -> float:
	if source.has_method("get_gravity_strength"):
		return clampf(source.get_gravity_strength() / GRAVITY_STRENGTH_AT_CAP, 0.0, 1.0)

	var definition = source.get("definition")
	if definition != null and "gravity_strength" in definition:
		return clampf(definition.gravity_strength / GRAVITY_STRENGTH_AT_CAP, 0.0, 1.0)

	return 1.0


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
