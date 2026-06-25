class_name DeathScreen
extends CanvasLayer

var label: Label

func _ready() -> void:
	visible = false

	var background := ColorRect.new()
	background.color = Color.html("#050000")
	background.anchor_left = 0.0
	background.anchor_top = 0.0
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.offset_left = 0.0
	background.offset_top = 0.0
	background.offset_right = 0.0
	background.offset_bottom = 0.0
	add_child(background)

	label = Label.new()
	label.text = "You were one of a kind.\nAnd now you're dead."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.modulate = Color.html("#ff2222")
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0
	background.add_child(label)

	# Connect to worm death signal
	var worm_player = get_tree().root.find_child("WormPlayer", true, false)
	if worm_player and worm_player.has_signal("worm_died"):
		worm_player.worm_died.connect(show_death_screen)

func show_death_screen() -> void:
	visible = true
