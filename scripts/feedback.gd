extends Node


@export var spark_lifetime: float = 0.28
@export var respawn_lifetime: float = 0.45
@export var impact_flash_lifetime: float = 0.18
@export var sfx_volume_db: float = -12.0
@export var muzzle_sound: AudioStream
@export var asteroid_impact_sound: AudioStream
@export var impact_flash_texture: Texture2D

@onready var effects_root: Node2D = $"../Effects"
@onready var flash_rect: ColorRect = $"../ScreenEffects/Flash"


func spawn_muzzle_flash(spawn_position: Vector2, direction: Vector2) -> void:
	_spawn_sparks(spawn_position, direction.angle(), 3, Color(1.0, 0.92, 0.35, 1.0), 18.0)
	_play_sound(muzzle_sound)


func spawn_asteroid_burst(spawn_position: Vector2, size_tier: int) -> void:
	var spark_count: int = 10 - mini(size_tier * 2, 4)
	var spark_length: float = 34.0 - float(size_tier) * 7.0
	_spawn_sparks(spawn_position, 0.0, spark_count, Color(0.95, 0.78, 0.48, 1.0), spark_length)
	_spawn_impact_flash(spawn_position, size_tier)
	_play_sound(asteroid_impact_sound)


func spawn_player_hit(spawn_position: Vector2) -> void:
	_spawn_sparks(spawn_position, 0.0, 14, Color(0.45, 0.88, 1.0, 1.0), 42.0)
	_flash(Color(0.45, 0.88, 1.0, 0.28), 0.18)


func spawn_respawn_ring(spawn_position: Vector2) -> void:
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = Color(0.45, 0.88, 1.0, 0.8)
	ring.closed = true

	for index in 24:
		var angle := TAU * float(index) / 24.0
		ring.add_point(Vector2.RIGHT.rotated(angle) * 24.0)

	ring.position = spawn_position
	effects_root.add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE * 2.4, respawn_lifetime)
	tween.tween_property(ring, "modulate:a", 0.0, respawn_lifetime)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)


func spawn_wave_flash() -> void:
	_flash(Color(0.9, 0.95, 1.0, 0.16), 0.16)


func clear_effects() -> void:
	for child in effects_root.get_children():
		child.queue_free()
	flash_rect.color = Color.TRANSPARENT


func _spawn_sparks(
	spawn_position: Vector2,
	base_angle: float,
	spark_count: int,
	color: Color,
	spark_length: float
) -> void:
	for index in spark_count:
		var spread := TAU * float(index) / maxf(1.0, float(spark_count))
		var angle := base_angle + spread
		var spark := Line2D.new()
		spark.width = 2.0
		spark.default_color = color
		spark.add_point(Vector2.ZERO)
		spark.add_point(Vector2.RIGHT.rotated(angle) * spark_length)
		spark.position = spawn_position
		effects_root.add_child(spark)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "scale", Vector2.ONE * 1.55, spark_lifetime)
		tween.tween_property(spark, "modulate:a", 0.0, spark_lifetime)
		tween.set_parallel(false)
		tween.tween_callback(spark.queue_free)


func _spawn_impact_flash(spawn_position: Vector2, size_tier: int) -> void:
	if impact_flash_texture == null:
		return

	var flash := Sprite2D.new()
	flash.texture = impact_flash_texture
	flash.centered = true
	flash.position = spawn_position
	flash.modulate = Color(1.0, 1.0, 1.0, 0.82)
	flash.scale = Vector2.ONE * (0.42 + float(size_tier) * 0.18)
	effects_root.add_child(flash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", flash.scale * 1.85, impact_flash_lifetime)
	tween.tween_property(flash, "modulate:a", 0.0, impact_flash_lifetime)
	tween.set_parallel(false)
	tween.tween_callback(flash.queue_free)


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = sfx_volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _flash(color: Color, duration: float) -> void:
	flash_rect.color = color
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, duration)
