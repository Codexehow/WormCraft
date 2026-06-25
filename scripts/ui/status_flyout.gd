class_name StatusFlyout
extends CanvasLayer

var worm_player: Node2D
var panel_container: PanelContainer
var label: Label
var is_open: bool = false  # Start closed

func _ready() -> void:
	# Find the worm player
	worm_player = get_tree().root.find_child("WormPlayer", true, false)
	
	# Create panel
	panel_container = PanelContainer.new()
	panel_container.size = Vector2(320, 280)
	panel_container.position = Vector2(-340, 10)  # Start off-screen to the left
	
	# Create stylebox for panel
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.html("#2a2a3e")
	style.border_color = Color.html("#888888")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_top = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 12
	panel_container.add_theme_stylebox_override("panel", style)
	
	# Create label for text
	label = Label.new()
	label.text = "Initializing..."
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color.WHITE
	label.custom_minimum_size = Vector2(300, 250)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel_container.add_child(label)
	
	add_child(panel_container)
	
	# Connect to worm signals
	if worm_player:
		worm_player.hunger_changed.connect(_on_hunger_changed)
		worm_player.inventory_changed.connect(_on_inventory_changed)
		worm_player.worm_died.connect(_on_worm_died)
		worm_player.tile_changed.connect(_on_tile_changed)
	
	# Force closed state on startup
	_update_panel()

func _process(_delta: float) -> void:
	# Toggle status panel using the toggle_status input action (bound to Tab)
	if Input.is_action_just_pressed("toggle_status"):
		toggle_panel()
	
	if is_open:
		_update_panel()

func toggle_panel() -> void:
	is_open = !is_open
	_update_panel()
	if is_open:
		print("Status panel opened.")
	else:
		print("Status panel closed.")

func _update_panel() -> void:
	if not worm_player:
		label.text = "ERROR: Worm player not found!"
		return
	
	var hunger_text: String = "%.0f / %.0f" % [worm_player.hunger, worm_player.max_hunger]
	var status_text: String = worm_player.get_status_text()
	var tile_type_text: String = worm_player.get_tile_type_name()
	var facing_text: String = worm_player.get_facing_direction_name()
	var dirt_pile: int = worm_player.get_inventory_count("dirt_pile")
	var dirt_capacity: int = worm_player.get_inventory_capacity("dirt_pile")
	var last_fall: int = 0
	if worm_player.has_method("get_last_fall_distance_tiles"):
		last_fall = worm_player.get_last_fall_distance_tiles()
	
	var panel_text: String = """STATUS

Hunger: %s
State: %s
Current Tile: %s
Facing: %s
Dirt Dug: %d
Dirt Pile: %d / %d
Last Fall: %d tiles
Last: %s
""" % [hunger_text, status_text, tile_type_text, facing_text, worm_player.dirt_dug_count, dirt_pile, dirt_capacity, last_fall, worm_player.last_action]
	
	label.text = panel_text
	
	# Update panel visibility and position based on is_open
	if is_open:
		panel_container.position = Vector2(10, 10)
	else:
		panel_container.position = Vector2(-340, 10)

func _on_hunger_changed(_new_hunger: float) -> void:
	if is_open:
		_update_panel()

func _on_inventory_changed(_inventory: Dictionary) -> void:
	if is_open:
		_update_panel()

func _on_worm_died() -> void:
	if is_open:
		_update_panel()

func _on_tile_changed(_tile_type: int) -> void:
	if is_open:
		_update_panel()
