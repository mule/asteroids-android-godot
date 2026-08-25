## Distance-based sleep/wake for sector content.
##
## The sector is 8000x6000 and the player sees roughly 1152x648 of it, so
## simulating all of it every frame is about forty times the work the frame
## actually needs. `scripts/asteroid.gd` runs a full overlap resolution pass in
## `_physics_process` per rock; multiplied across five fields plus the planets,
## moons, stations and AI ships the later issues add, that pass is the frame
## budget. This node-less helper is what keeps it bounded: entities far from
## the camera stop processing and stop drawing, and come back untouched when
## the camera returns.
##
## Static rather than an autoload so a test can call it against a bare Node2D
## without standing up the game, and so `game.gd` owns when it runs rather than
## discovering it already running.
class_name Activation
extends RefCounted


## Sleep past `radius * SLEEP_SCALE`, wake within `radius`. The gap between the
## two is the whole point: with a single threshold an entity drifting along it
## flips state every physics frame, and the bookkeeping of each flip -- walking
## the subtree, toggling collision -- costs more than the sleep saves. 1.15 is
## a band of ~180 units at the shipped 1200 radius, wider than anything in the
## sector crosses in one tick.
const SLEEP_SCALE := 1.15

## Fields register themselves here in `AsteroidField._ready()`. Named in one
## place so `game.gd` and the fields cannot drift apart on the spelling.
const GROUP_ASTEROID_FIELDS := &"asteroid_fields"

## Sleep state and the pre-sleep snapshot restored on wake. Metadata rather
## than a dictionary keyed by instance id: it dies with the node, so a freed
## entity cannot leak an entry or, worse, hand its stale snapshot to whatever
## instance id gets reused next.
const ACTIVE_META := &"activation_active"
const PROCESS_MODE_META := &"activation_process_mode"
const VISIBLE_META := &"activation_visible"
const MONITORING_META := &"activation_monitoring"
const MONITORABLE_META := &"activation_monitorable"


## Sleep or wake every entity in `group` against `focus`, and return how many
## came out of it awake. The count is the measurable the issue asks for: it is
## what a later regression in activation would move.
static func update_group(group: StringName, focus: Vector2, radius: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0

	var active_count := 0

	for node in tree.get_nodes_in_group(group):
		var entity := node as Node2D
		if entity == null or not is_instance_valid(entity) or entity.is_queued_for_deletion():
			continue

		# The hysteresis, applied here rather than inside is_within() so that
		# is_within() stays the plain geometric predicate its signature
		# promises: an entity that is already awake is measured against the
		# wider sleep radius, a sleeping one against the narrower wake radius.
		var threshold := radius * SLEEP_SCALE if is_active(entity) else radius
		var active := is_within(entity, focus, threshold)
		set_entity_active(entity, active)

		if active:
			active_count += 1

	return active_count


## Put `entity` to sleep or bring it back. Idempotent, and never destructive:
## the entity keeps its parent, its children, its groups and its position. Only
## processing, visibility and collision are touched, and each is restored to
## the value it had before the entity first slept -- not to a hardcoded
## default, which would quietly un-hide something the game had hidden for its
## own reasons and is how a "restored" entity comes back subtly wrong.
static func set_entity_active(entity: Node, active: bool) -> void:
	if entity == null or not is_instance_valid(entity):
		return

	if is_active(entity) == active:
		# Still stamp the state. An entity that has never been through here
		# reads as active by default; recording that makes the first real
		# transition a transition rather than a no-op.
		entity.set_meta(ACTIVE_META, active)
		return

	if active:
		_wake(entity)
	else:
		_sleep(entity)

	entity.set_meta(ACTIVE_META, active)


## Awake unless we have put it to sleep. Defaulting to awake matters for
## entities spawned mid-run: a rock that has never met the activation pass
## must simulate, not sit frozen waiting to be discovered.
static func is_active(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false

	if not entity.has_meta(ACTIVE_META):
		return true

	return bool(entity.get_meta(ACTIVE_META))


## Does `entity` reach inside the circle of `radius` around `focus`?
##
## Measured to the entity's edge, not its origin. A 560-unit asteroid field
## whose centre sits just outside the radius still has rocks well inside it,
## and waking on the centre alone would pop half a field into existence in
## front of the player. Entities with no declared extent -- a station, an AI
## ship -- are points, which is the correct reading for them.
static func is_within(entity: Node2D, focus: Vector2, radius: float) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false

	var reach := maxf(0.0, radius) + get_extent(entity)
	return entity.global_position.distance_squared_to(focus) <= reach * reach


## How far `entity` reaches from its own origin, asked of the entity so each
## kind answers for itself instead of Activation carrying a table of them.
static func get_extent(entity: Node) -> float:
	if entity != null and is_instance_valid(entity) and entity.has_method("get_activation_extent"):
		return maxf(0.0, float(entity.call("get_activation_extent")))

	return 0.0


static func _sleep(entity: Node) -> void:
	entity.set_meta(PROCESS_MODE_META, entity.process_mode)
	# PROCESS_MODE_DISABLED rather than set_physics_process(false): it stops the
	# whole subtree. The cost being saved is the asteroids' per-frame overlap
	# pass, not the field node's own empty frame -- switching off the parent
	# alone would save nothing at all.
	entity.process_mode = Node.PROCESS_MODE_DISABLED

	var canvas_item := entity as CanvasItem
	if canvas_item != null:
		entity.set_meta(VISIBLE_META, canvas_item.visible)
		canvas_item.visible = false

	for collider in _colliders_in(entity):
		_sleep_collider(collider)


static func _wake(entity: Node) -> void:
	entity.process_mode = (
		entity.get_meta(PROCESS_MODE_META) if entity.has_meta(PROCESS_MODE_META)
		else Node.PROCESS_MODE_INHERIT
	)
	entity.remove_meta(PROCESS_MODE_META)

	var canvas_item := entity as CanvasItem
	if canvas_item != null:
		canvas_item.visible = (
			bool(entity.get_meta(VISIBLE_META)) if entity.has_meta(VISIBLE_META) else true
		)
		entity.remove_meta(VISIBLE_META)

	for collider in _colliders_in(entity):
		_wake_collider(collider)


## Pausing a node does not unregister its shapes from the physics server, so a
## sleeping field would still be shootable and would still kill a ship flying
## through it -- invisible, unmoving, and lethal. Collision goes down with the
## rest of the entity and comes back with it.
static func _sleep_collider(area: Area2D) -> void:
	area.set_meta(MONITORING_META, area.monitoring)
	area.set_meta(MONITORABLE_META, area.monitorable)
	area.monitoring = false
	area.monitorable = false


static func _wake_collider(area: Area2D) -> void:
	area.monitoring = (
		bool(area.get_meta(MONITORING_META)) if area.has_meta(MONITORING_META) else true
	)
	area.monitorable = (
		bool(area.get_meta(MONITORABLE_META)) if area.has_meta(MONITORABLE_META) else true
	)
	area.remove_meta(MONITORING_META)
	area.remove_meta(MONITORABLE_META)


## The entity itself plus its descendants, so activating a field reaches the
## rocks parented under it. Walked on transitions only -- a handful of times a
## minute -- never per frame.
static func _colliders_in(entity: Node) -> Array[Area2D]:
	var colliders: Array[Area2D] = []

	if entity is Area2D:
		colliders.append(entity as Area2D)

	for child in entity.get_children():
		colliders.append_array(_colliders_in(child))

	return colliders
