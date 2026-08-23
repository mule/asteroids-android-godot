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
## rebuilding the stars.
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
