class_name InventoryFlyout
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
	panel_container.size = Vector2(280, 170)
	panel_container.position = Vector2(-300, 10)  # Start off-screen to the right
	
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
	label.custom_minimum_size = Vector2(260, 120)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel_container.add_child(label)
	
	add_child(panel_container)
	
	# Connect to worm signals
	if worm_player:
		worm_player.inventory_changed.connect(_on_inventory_changed)
	
	# Force closed state on startup
	_update_panel()

func _process(_delta: float) -> void:
	# Toggle inventory panel using the toggle_inventory input action (bound to I)
	if Input.is_action_just_pressed("toggle_inventory"):
		toggle_panel()
	
	if is_open:
		_update_panel()

func toggle_panel() -> void:
	is_open = !is_open
	_update_panel()
	if is_open:
		print("Inventory panel opened.")
	else:
		print("Inventory panel closed.")

func _update_panel() -> void:
	if not worm_player:
		label.text = "ERROR: Worm player not found!"
		return
	
	var dirt_pile: int = worm_player.get_inventory_count("dirt_pile")
	var dirt_capacity: int = worm_player.get_inventory_capacity("dirt_pile")
	var spider_silk: int = worm_player.get_inventory_count("spider_silk_sample")
	var prototype_text: String = "Not Built"
	if worm_player.has_method("get_prototype_status"):
		var proto_status: String = worm_player.get_prototype_status()
		if proto_status != "None":
			prototype_text = "Built"
	
	var panel_text: String = """INVENTORY

Quantum Space Folder
Dirt Pile: %d / %d
Spider Silk Sample: %d
Silk Grip Pads MK0: %s
""" % [dirt_pile, dirt_capacity, spider_silk, prototype_text]
	
	label.text = panel_text
	
	# Update panel visibility and position based on is_open
	if is_open:
		panel_container.position = Vector2(10, 320)
	else:
		panel_container.position = Vector2(-300, 10)

func _on_inventory_changed(_inventory: Dictionary) -> void:
	if is_open:
		_update_panel()
