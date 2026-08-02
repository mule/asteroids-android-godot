extends Node2D


@export var bullet_scene: PackedScene
@export var starting_score: int = 0
@export var starting_lives: int = 3
@export var starting_wave: int = 1

@onready var entities: Node2D = $Entities
@onready var player_ship: Area2D = $Entities/PlayerShip


func _ready() -> void:
	player_ship.shoot_requested.connect(_on_player_ship_shoot_requested)


func _on_player_ship_shoot_requested(
	muzzle_position: Vector2,
	direction: Vector2,
	inherited_velocity: Vector2
) -> void:
	var bullet := bullet_scene.instantiate()
	entities.add_child(bullet)
	bullet.global_position = muzzle_position

	if bullet.has_method("launch"):
		bullet.launch(direction, inherited_velocity)
