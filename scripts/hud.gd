extends CanvasLayer


signal pause_requested
signal resume_requested
signal restart_requested
signal touch_action_changed(action: StringName, pressed: bool)

@onready var score_label: Label = $Root/TopBar/ScoreLabel
@onready var lives_label: Label = $Root/TopBar/LivesLabel
@onready var wave_label: Label = $Root/TopBar/WaveLabel
@onready var pause_button: Button = $Root/TopBar/PauseButton
@onready var restart_button: Button = $Root/TopBar/RestartButton
@onready var status_panel: PanelContainer = $Root/StatusPanel
@onready var status_title_label: Label = $Root/StatusPanel/MarginContainer/VBoxContainer/StatusTitleLabel
@onready var status_body_label: Label = $Root/StatusPanel/MarginContainer/VBoxContainer/StatusBodyLabel
@onready var resume_button: Button = $Root/StatusPanel/MarginContainer/VBoxContainer/OverlayActions/ResumeButton
@onready var overlay_restart_button: Button = $Root/StatusPanel/MarginContainer/VBoxContainer/OverlayActions/OverlayRestartButton
@onready var touch_controls: Control = $Root/TouchControls
@onready var touch_left_button: Button = $Root/TouchControls/LeftCluster/RotateLeftButton
@onready var touch_right_button: Button = $Root/TouchControls/LeftCluster/RotateRightButton
@onready var touch_thrust_button: Button = $Root/TouchControls/RightCluster/ThrustButton
@onready var touch_shoot_button: Button = $Root/TouchControls/RightCluster/ShootButton

var current_score: int = 0
var current_wave: int = 1


func _ready() -> void:
	pause_button.pressed.connect(pause_requested.emit)
	restart_button.pressed.connect(restart_requested.emit)
	resume_button.pressed.connect(resume_requested.emit)
	overlay_restart_button.pressed.connect(restart_requested.emit)
	_connect_touch_button(touch_left_button, &"rotate_left")
	_connect_touch_button(touch_right_button, &"rotate_right")
	_connect_touch_button(touch_thrust_button, &"thrust")
	_connect_touch_button(touch_shoot_button, &"shoot")
	touch_controls.visible = OS.has_feature("android") or DisplayServer.is_touchscreen_available()


func set_score(value: int) -> void:
	current_score = value
	score_label.text = "Score %d" % value


func set_lives(value: int) -> void:
	lives_label.text = "Lives %d" % value


func set_wave(value: int) -> void:
	current_wave = value
	wave_label.text = "Wave %d" % value


func show_paused() -> void:
	status_title_label.text = "Paused"
	status_body_label.text = "Score %d  Wave %d" % [current_score, current_wave]
	resume_button.visible = true
	overlay_restart_button.visible = true
	status_panel.visible = true
	pause_button.disabled = true


func show_game_over(final_score: int, wave: int) -> void:
	status_title_label.text = "Game Over"
	status_body_label.text = "Score %d  Wave %d" % [final_score, wave]
	resume_button.visible = false
	overlay_restart_button.visible = true
	status_panel.visible = true
	pause_button.disabled = true


func hide_status() -> void:
	status_panel.visible = false
	pause_button.disabled = false
	_clear_touch_actions()


func set_pause_available(value: bool) -> void:
	pause_button.disabled = not value


func set_touch_controls_visible(value: bool) -> void:
	touch_controls.visible = value


func _connect_touch_button(button: Button, action: StringName) -> void:
	button.button_down.connect(func() -> void: touch_action_changed.emit(action, true))
	button.button_up.connect(func() -> void: touch_action_changed.emit(action, false))
	button.focus_exited.connect(func() -> void: touch_action_changed.emit(action, false))


func _clear_touch_actions() -> void:
	touch_action_changed.emit(&"rotate_left", false)
	touch_action_changed.emit(&"rotate_right", false)
	touch_action_changed.emit(&"thrust", false)
	touch_action_changed.emit(&"shoot", false)
