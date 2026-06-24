class_name DebugHUD
extends CanvasLayer

var worm_player: Node2D
var label: Label

func _ready() -> void:
	# Find the worm player
	worm_player = get_tree().root.find_child("WormPlayer", true, false)
	
	# Create label
	label = Label.new()
	label.text = "Initializing HUD..."
	label.add_theme_font_size_override("font_size", 16)
	label.position = Vector2(10, 10)
	label.modulate = Color.WHITE
	add_child(label)
	
	# Connect to worm signals
	if worm_player:
		worm_player.hunger_changed.connect(_on_hunger_changed)
		worm_player.dirt_eaten.connect(_on_dirt_eaten)
		worm_player.worm_died.connect(_on_worm_died)
	
	_update_hud()

func _process(_delta: float) -> void:
	_update_hud()

func _update_hud() -> void:
	if not worm_player:
		label.text = "ERROR: Worm player not found!"
		return
	
	var hunger_text: String = "%.0f / %.0f" % [worm_player.hunger, worm_player.max_hunger]
	var status_text: String = worm_player.get_status_text()
	
	label.text = "Hunger: %s\nDirt Eaten: %d\nStatus: %s" % [hunger_text, worm_player.dirt_eaten_count, status_text]

func _on_hunger_changed(_new_hunger: float) -> void:
	_update_hud()

func _on_dirt_eaten() -> void:
	_update_hud()

func _on_worm_died() -> void:
	_update_hud()
