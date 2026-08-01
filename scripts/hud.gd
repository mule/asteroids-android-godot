extends CanvasLayer


@onready var score_label: Label = $Root/TopBar/ScoreLabel
@onready var lives_label: Label = $Root/TopBar/LivesLabel
@onready var wave_label: Label = $Root/TopBar/WaveLabel


func set_score(value: int) -> void:
	score_label.text = "Score %d" % value


func set_lives(value: int) -> void:
	lives_label.text = "Lives %d" % value


func set_wave(value: int) -> void:
	wave_label.text = "Wave %d" % value
