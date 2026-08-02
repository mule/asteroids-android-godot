extends CanvasLayer


@onready var score_label: Label = $Root/TopBar/ScoreLabel
@onready var lives_label: Label = $Root/TopBar/LivesLabel
@onready var wave_label: Label = $Root/TopBar/WaveLabel
@onready var status_panel: PanelContainer = $Root/StatusPanel
@onready var status_title_label: Label = $Root/StatusPanel/MarginContainer/VBoxContainer/StatusTitleLabel
@onready var status_body_label: Label = $Root/StatusPanel/MarginContainer/VBoxContainer/StatusBodyLabel


func set_score(value: int) -> void:
	score_label.text = "Score %d" % value


func set_lives(value: int) -> void:
	lives_label.text = "Lives %d" % value


func set_wave(value: int) -> void:
	wave_label.text = "Wave %d" % value


func show_game_over(final_score: int, wave: int) -> void:
	status_title_label.text = "Game Over"
	status_body_label.text = "Score %d  Wave %d\nPress R or Enter to restart" % [final_score, wave]
	status_panel.visible = true


func hide_status() -> void:
	status_panel.visible = false
