extends CanvasLayer


signal pause_requested
signal resume_requested
signal restart_requested

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

var current_score: int = 0
var current_wave: int = 1


func _ready() -> void:
	pause_button.pressed.connect(pause_requested.emit)
	restart_button.pressed.connect(restart_requested.emit)
	resume_button.pressed.connect(resume_requested.emit)
	overlay_restart_button.pressed.connect(restart_requested.emit)


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


func set_pause_available(value: bool) -> void:
	pause_button.disabled = not value
