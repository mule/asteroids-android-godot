extends Node2D
class_name StarLayer


@export var star_count: int = 90
@export var layer_seed: int = 404
@export var min_radius: float = 1.0
@export var max_radius: float = 2.4
@export var star_color: Color = Color(0.65, 0.82, 1.0)
@export var min_alpha: float = 0.28
@export var max_alpha: float = 0.7

var random := RandomNumberGenerator.new()


## The band of layer-local space a Parallax2D at `scroll_scale` can ever put on
## screen, anchored at the sector's own origin.
##
## A parallax layer drifts at a *fraction* of the camera's speed, so it does not
## need -- and cannot show -- a full sector's worth of content. Crossing the
## whole 8000x6000 sector slides a 0.15 layer by only 0.15 x the camera's
## travel, which means everything past `scroll_scale x sector + one screen` is
## built and then never drawn: measured on the shipped scene, 91.7% of the far
## layer's stars sat outside this band, leaving about eight of 420 on screen at
## a time. Scattering each layer's stars over its own span instead spends every
## star where a player can see it, at no extra node cost.
##
## `bounds.size` rather than `bounds.size - view_size` for the travel term
## deliberately over-covers by `scroll_scale x view_size`: the span is computed
## once at build time, and a later window resize grows the screen without
## rebuilding the stars. That margin absorbs a widening to
## `view_size / (1 - scroll_scale)` -- about 1355px from the 1152px base for a
## 0.15 layer. Past that a starless strip appears at the far sector edge.
## Android locks landscape so it cannot arise there; on desktop the trade is
## deliberate, because rebuilding on `size_changed` would re-scatter the whole
## sky mid-drag.
##
## The band is anchored at `bounds.position`, which is the true anchor only
## because every sector starts at the origin: `SectorDefinition.get_bounds()`
## returns `Rect2(Vector2.ZERO, world_size)`, and `Sector.get_bounds()` falls
## back to a viewport rect that is also at the origin. A layer's reachable band
## really begins at `scroll_scale x bounds.position`, so an offset sector would
## need that term here -- and would also break the "every star is inside the
## sector" invariant the shipped-game test asserts, since a slower layer's band
## starts *before* an offset sector does. Both would have to be settled
## together; neither is reachable today.
static func parallax_span(bounds: Rect2, scroll_scale: Vector2, view_size: Vector2) -> Rect2:
	var span := (bounds.size * scroll_scale + view_size).min(bounds.size)
	return Rect2(bounds.position, span)


func build_stars(bounds: Rect2, seed_value: int) -> void:
	# remove_child before queue_free, not queue_free alone: queue_free only
	# schedules the deletion for the end of the frame, so a rebuild would leave
	# the previous layout parented and drawn on top of the new one for that
	# frame, and get_child_count() straight after the call would report both.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	random.seed = seed_value

	for index in star_count:
		var star := Polygon2D.new()
		var radius := random.randf_range(min_radius, max_radius)
		star.polygon = PackedVector2Array([
			Vector2(0.0, -radius),
			Vector2(radius, 0.0),
			Vector2(0.0, radius),
			Vector2(-radius, 0.0)
		])
		star.position = Vector2(
			random.randf_range(bounds.position.x, bounds.end.x),
			random.randf_range(bounds.position.y, bounds.end.y)
		)
		star.color = Color(
			star_color.r,
			star_color.g,
			star_color.b,
			random.randf_range(min_alpha, max_alpha)
		)
		add_child(star)
