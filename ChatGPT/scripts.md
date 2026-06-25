worm_player.gd 



class_name WormPlayer
extends CharacterBody2D

# Hunger constants
const MAX_HUNGER: float = 100.0
const STARTING_HUNGER: float = 85.0
const HUNGER_DRAIN_RATE: float = 0.2  # per second
const DIRT_PILE_MEAL_HUNGER_RESTORE: float = 20.0

# Movement constants
const MOVE_SPEED: float = 60.0  # pixels per second
const GRAVITY: float = 200.0  # pixels per second squared
const MAX_FALL_SPEED: float = MOVE_SPEED * 2.0
const STEP_COOLDOWN_SECONDS: float = 0.16

# Placement constants
const DIRT_PILE_PLACE_COST: int = 1

# Inventory
var inventory: Dictionary = {
	"dirt_pile": 0
}

# State
var hunger: float = STARTING_HUNGER
var max_hunger: float = MAX_HUNGER
var is_alive: bool = true
var dirt_dug_count: int = 0  # Number of dirt/soil tiles cleared
var dirt_placed_count: int = 0
var current_tile_type: int = LayeredTestWorld.TileType.EMPTY
var facing_direction: Vector2 = Vector2.RIGHT
var last_action: String = ""
var step_cooldown: float = 0.0
var _raw_place_key_was_down: bool = false

const DIG_REACH_TILES: int = 2

# Reference to the world
var world: LayeredTestWorld

# Signals
signal hunger_changed(new_hunger: float)
signal inventory_changed(inventory: Dictionary)
signal worm_died
signal tile_changed(tile_type: int)

func _ready() -> void:
	# Find the world
	world = get_tree().root.find_child("LayeredTestWorld", true, false)
	if not world:
		# Fallback for old name
		world = get_tree().root.find_child("TestDirtWorld", true, false)
	
	if not InputMap.has_action("place_dirt"):
		push_warning("InputMap action 'place_dirt' is missing. Add it in Project Settings > Input Map and bind it to F.")
	
	# Initialize hunger
	hunger = STARTING_HUNGER
	emit_signal("hunger_changed", hunger)
	emit_signal("inventory_changed", inventory)
	_update_current_tile()

func _process(delta: float) -> void:
	if not is_alive:
		return
	
	# Drain hunger over time
	hunger -= HUNGER_DRAIN_RATE * delta
	hunger = clamp(hunger, 0.0, max_hunger)
	emit_signal("hunger_changed", hunger)
	
	# Check if starved
	if hunger <= 0.0:
		_on_starve()
		return
	
	# Handle digging input
	if Input.is_action_just_pressed("dig"):
		_on_dig_input()
	
	# Handle eating input
	if Input.is_action_just_pressed("eat_food"):
		_on_eat_food_input()
	
	# Handle dirt placement input. Preferred action is place_dirt, bound to F.
	# During prototype development, raw F fallback prevents silent failure if InputMap is missing.
	var place_pressed: bool = false
	if InputMap.has_action("place_dirt"):
		place_pressed = Input.is_action_just_pressed("place_dirt")
	else:
		var raw_f_down: bool = Input.is_key_pressed(KEY_F)
		place_pressed = raw_f_down and not _raw_place_key_was_down
		_raw_place_key_was_down = raw_f_down
		if place_pressed:
			push_warning("Using raw F fallback because InputMap action 'place_dirt' is missing.")
			print("WARNING: InputMap action 'place_dirt' is missing. Add it and bind it to F.")
	
	if place_pressed:
		_on_place_dirt_input()

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	step_cooldown = max(step_cooldown - delta, 0.0)
	var horizontal_direction: Vector2 = Vector2.ZERO
	
	# Handle horizontal movement input
	if Input.is_action_pressed("move_left"):
		horizontal_direction.x -= 1.0
		facing_direction = Vector2.LEFT
	if Input.is_action_pressed("move_right"):
		horizontal_direction.x += 1.0
		facing_direction = Vector2.RIGHT
	
	# Handle facing direction from vertical input, not free vertical movement.
	# W/Up lets the player dig upward. It does not move the worm upward.
	if Input.is_action_pressed("move_up"):
		facing_direction = Vector2.UP
	if Input.is_action_pressed("move_down"):
		facing_direction = Vector2.DOWN
	
	if world:
		var current_grid_pos: Vector2i = world.world_to_grid(global_position)
		
		# Apply horizontal movement. If blocked, try a one-tile step up.
		if horizontal_direction.length() > 0.0:
			var target_x: int = current_grid_pos.x
			if horizontal_direction.x < 0:
				target_x -= 1
			else:
				target_x += 1
			
			var target_pos: Vector2i = Vector2i(target_x, current_grid_pos.y)
			
			if world.is_passable(target_pos):
				velocity.x = horizontal_direction.x * MOVE_SPEED
			else:
				velocity.x = 0.0
				_try_step_up(current_grid_pos, target_x)
		else:
			velocity.x = 0.0
		
		# Down input is allowed to encourage falling/crawling downward if there is already space below.
		# It cannot dig or phase through solid tiles by itself.
		if Input.is_action_pressed("move_down"):
			var below_for_drop: Vector2i = Vector2i(current_grid_pos.x, current_grid_pos.y + 1)
			if world.is_passable(below_for_drop):
				velocity.y = max(velocity.y, MOVE_SPEED)
		
		# Gravity-driven vertical movement.
		# W/Up must never create negative/upward velocity here.
		var below_pos: Vector2i = Vector2i(current_grid_pos.x, current_grid_pos.y + 1)
		if world.is_passable(below_pos):
			velocity.y += GRAVITY * delta
			velocity.y = clamp(velocity.y, 0.0, MAX_FALL_SPEED)
		else:
			if velocity.y > 0.0:
				velocity.y = 0.0
		
		move_and_slide()
		_update_current_tile()

func _try_step_up(current_grid_pos: Vector2i, target_x: int) -> void:
	"""
	Simple one-tile step-up movement.
	This is not wall climbing and not jumping. It only lets the worm negotiate small block ledges.
	"""
	if step_cooldown > 0.0 or not world:
		return
	
	var target_same_level: Vector2i = Vector2i(target_x, current_grid_pos.y)
	var step_target: Vector2i = Vector2i(target_x, current_grid_pos.y - 1)
	var above_current: Vector2i = Vector2i(current_grid_pos.x, current_grid_pos.y - 1)
	var below_current: Vector2i = Vector2i(current_grid_pos.x, current_grid_pos.y + 1)
	
	# Requirements:
	# 1. The same-level target is solid/blocking.
	# 2. The diagonal-up target is passable.
	# 3. The space above the worm is passable, so it does not step through a ceiling.
	# 4. The worm is currently supported by solid ground.
	if world.is_passable(target_same_level):
		return
	if not world.is_passable(step_target):
		return
	if not world.is_passable(above_current):
		return
	if world.is_passable(below_current):
		return
	
	global_position = world.grid_to_world_center(step_target)
	velocity = Vector2.ZERO
	step_cooldown = STEP_COOLDOWN_SECONDS
	last_action = "Stepped up."
	_update_current_tile()

func _get_facing_offset() -> Vector2i:
	if facing_direction == Vector2.LEFT:
		return Vector2i(-1, 0)
	elif facing_direction == Vector2.RIGHT:
		return Vector2i(1, 0)
	elif facing_direction == Vector2.UP:
		return Vector2i(0, -1)
	elif facing_direction == Vector2.DOWN:
		return Vector2i(0, 1)
	return Vector2i(1, 0)

func _get_target_grid_pos() -> Vector2i:
	# Backward-compatible adjacent target. Placement uses this.
	var current_grid_pos: Vector2i = world.world_to_grid(global_position)
	var offset: Vector2i = _get_facing_offset()
	return current_grid_pos + offset

func _get_dig_target_grid_pos() -> Vector2i:
	# Digging is slightly forgiving: if the adjacent tile is empty/air, allow the worm
	# to bite the first solid/diggable tile within a very short reach. This reduces
	# "Nothing to dig" moments caused by the sprite being larger than one tile.
	var current_grid_pos: Vector2i = world.world_to_grid(global_position)
	var offset: Vector2i = _get_facing_offset()
	var first_target: Vector2i = current_grid_pos + offset

	if not world:
		return first_target
	
	for distance in range(1, DIG_REACH_TILES + 1):
		var candidate: Vector2i = current_grid_pos + offset * distance
		if not world.is_in_bounds(candidate):
			return candidate
		if world.is_diggable(candidate):
			return candidate
		# Stop at non-passable but non-diggable tiles such as rock so the player gets
		# the correct failure message instead of digging through it.
		if not world.is_passable(candidate):
			return candidate
	
	return first_target

func _on_dig_input() -> void:
	"""
	Handle digging action. Digs the tile in front of the worm.
	"""
	if not is_alive or not world:
		return
	
	var target_grid_pos: Vector2i = _get_dig_target_grid_pos()
	var result: Dictionary = world.try_dig_tile(target_grid_pos)
	last_action = result["message"]
	
	if result["success"] and result["cleared"]:
		if result["resource_id"] == "dirt_pile":
			inventory["dirt_pile"] += result["resource_amount"]
			dirt_dug_count += 1
			emit_signal("inventory_changed", inventory)
	
	print(result["message"])

func _on_place_dirt_input() -> void:
	"""
	Place one Dirt Pile into the tile in front of the worm as PLACED_DIRT.
	"""
	if not is_alive or not world:
		return
	
	if inventory.get("dirt_pile", 0) < DIRT_PILE_PLACE_COST:
		last_action = "No dirt pile to place."
		print(last_action)
		return
	
	var current_grid_pos: Vector2i = world.world_to_grid(global_position)
	var target_grid_pos: Vector2i = _get_target_grid_pos()
	var result: Dictionary = world.try_place_dirt_tile(target_grid_pos, current_grid_pos)
	last_action = result["message"]
	
	if result["success"]:
		inventory["dirt_pile"] -= DIRT_PILE_PLACE_COST
		dirt_placed_count += 1
		emit_signal("inventory_changed", inventory)
	
	print(result["message"])

func _on_eat_food_input() -> void:
	"""
	Handle eating food from inventory. Consumes dirt pile and restores hunger.
	"""
	if not is_alive:
		return
	
	# Check if hunger is already full
	if hunger >= max_hunger:
		last_action = "Already full."
		print("Already full.")
		return
	
	# Check if there is dirt pile to eat
	if inventory["dirt_pile"] <= 0:
		last_action = "No dirt pile to eat."
		print("No dirt pile to eat.")
		return
	
	# Consume dirt pile and restore hunger
	inventory["dirt_pile"] -= 1
	hunger = clamp(hunger + DIRT_PILE_MEAL_HUNGER_RESTORE, 0.0, max_hunger)
	last_action = "Ate dirt from pile."
	
	emit_signal("inventory_changed", inventory)
	emit_signal("hunger_changed", hunger)
	print("Ate dirt from pile. Hunger: %.0f" % hunger)

func _update_current_tile() -> void:
	if world:
		var grid_pos: Vector2i = world.world_to_grid(global_position)
		current_tile_type = world.get_tile_type(grid_pos)
		emit_signal("tile_changed", current_tile_type)

func _on_starve() -> void:
	is_alive = false
	velocity = Vector2.ZERO
	print("The worm has starved.")
	emit_signal("worm_died")

func get_status_text() -> String:
	if is_alive:
		return "Alive"
	else:
		return "Starved"

func get_facing_direction_name() -> String:
	if facing_direction == Vector2.LEFT:
		return "LEFT"
	elif facing_direction == Vector2.RIGHT:
		return "RIGHT"
	elif facing_direction == Vector2.UP:
		return "UP"
	elif facing_direction == Vector2.DOWN:
		return "DOWN"
	else:
		return "UNKNOWN"

func get_tile_type_name() -> String:
	if world:
		return world.get_tile_type_name(current_tile_type)
	return "UNKNOWN"

func get_inventory_count(item_id: String) -> int:
	"""Get count of an inventory item."""
	return inventory.get(item_id, 0)



-----



debug_HUD.gd 



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



-----



inventory_flyout.gd 



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
	panel_container.size = Vector2(280, 150)
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
	
	var panel_text: String = """INVENTORY

Dirt Pile: %d
""" % [dirt_pile]
	
	label.text = panel_text
	
	# Update panel visibility and position based on is_open
	if is_open:
		panel_container.position = Vector2(10, 320)
	else:
		panel_container.position = Vector2(-300, 10)

func _on_inventory_changed(_inventory: Dictionary) -> void:
	if is_open:
		_update_panel()



-----





status_flyout.gd 



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
	
	var panel_text: String = """STATUS

Hunger: %s
State: %s
Current Tile: %s
Facing: %s
Dirt Dug: %d
Dirt Pile: %d
Last: %s
""" % [hunger_text, status_text, tile_type_text, facing_text, worm_player.dirt_dug_count, dirt_pile, worm_player.last_action]
	
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



-----



layered_test_world.gd 

class_name LayeredTestWorld
extends Node2D

## Tile type enum
enum TileType {
	AIR,
	SURFACE,
	DIRT,
	EMPTY,
	ROCK,
	PLACED_DIRT
}

const TILE_SIZE: int = 16
const WORLD_WIDTH: int = 96
const WORLD_HEIGHT: int = 54

# Grid of tile types
var tile_grid: Array = []

# Tile durability tracking for partially dug tiles
# tile_durability[Vector2i] = remaining durability
var tile_durability: Dictionary = {}

# Durability values for diggable tiles
const DIRT_MAX_DURABILITY: int = 8
const SURFACE_MAX_DURABILITY: int = 8
const PLACED_DIRT_MAX_DURABILITY: int = 4

# Resource output when tiles are cleared
const DIRT_PILE_PER_DIRT_TILE: int = 5
const DIRT_PILE_PER_SURFACE_TILE: int = 3
const DIRT_PILE_PER_PLACED_DIRT_TILE: int = 1

# Cleared tiles remain cleared - no automatic regrowth in early development
# Future ecology/weather systems may reclaim tunnels, but cleared soil remains cleared during core gameplay.

# Visual colors for each tile type
var tile_colors: Dictionary = {
	TileType.AIR: Color.html("#1a1a2e"),          # Dark blue/black
	TileType.SURFACE: Color.html("#2d5016"),      # Green/brown surface
	TileType.DIRT: Color.html("#8B6914"),         # Brown dirt
	TileType.EMPTY: Color.html("#2C1810"),        # Dark empty
	TileType.ROCK: Color.html("#808080"),         # Gray rock
	TileType.PLACED_DIRT: Color.html("#A67C2D")   # Looser/player-placed dirt
}

var border_color: Color = Color.html("#6B4910")

func _ready() -> void:
	_initialize_layered_world()

func _process(_delta: float) -> void:
	queue_redraw()

func _initialize_layered_world() -> void:
	# Create empty 2D grid
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			row.append(TileType.DIRT)
		tile_grid.append(row)
	
	# Create layered world structure
	# Rows 0-9: AIR
	for y in range(10):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.AIR
	
	# Row 10: SURFACE
	for x in range(WORLD_WIDTH):
		tile_grid[10][x] = TileType.SURFACE
	
	# Rows 11-53: Mostly DIRT with some rocks and empty tunnel pocket
	for y in range(11, WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.DIRT
	
	# Add rocks at strategic locations
	tile_grid[15][20] = TileType.ROCK
	tile_grid[15][50] = TileType.ROCK
	tile_grid[25][30] = TileType.ROCK
	tile_grid[35][15] = TileType.ROCK
	tile_grid[40][60] = TileType.ROCK
	
	# Create initial empty tunnel pocket where worm starts
	var start_x: int = 48
	var start_y: int = 20
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x: int = start_x + dx
			var y: int = start_y + dy
			if is_in_bounds(Vector2i(x, y)):
				tile_grid[y][x] = TileType.EMPTY

func _draw() -> void:
	# Draw all tiles
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var tile_type: int = tile_grid[y][x]
			var tile_color: Color = tile_colors.get(tile_type, Color.WHITE)
			var rect_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), tile_color)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), border_color, false, 1.0)

# World query API
func world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / TILE_SIZE), int(world_position.y / TILE_SIZE))

func grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * TILE_SIZE, grid_position.y * TILE_SIZE)

func grid_to_world_center(grid_position: Vector2i) -> Vector2:
	return grid_to_world(grid_position) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

func is_in_bounds(grid_position: Vector2i) -> bool:
	return grid_position.x >= 0 and grid_position.x < WORLD_WIDTH and grid_position.y >= 0 and grid_position.y < WORLD_HEIGHT

func get_tile_type(grid_position: Vector2i) -> int:
	if not is_in_bounds(grid_position):
		return TileType.AIR
	return tile_grid[grid_position.y][grid_position.x]

func is_passable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	match tile_type:
		TileType.EMPTY, TileType.AIR:
			return true
		TileType.DIRT, TileType.SURFACE, TileType.ROCK, TileType.PLACED_DIRT:
			return false
		_:
			return false

func is_placeable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.EMPTY or tile_type == TileType.AIR

func is_diggable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.DIRT or tile_type == TileType.SURFACE or tile_type == TileType.PLACED_DIRT

func is_edible(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.DIRT or tile_type == TileType.SURFACE or tile_type == TileType.PLACED_DIRT

func try_place_dirt_tile(grid_position: Vector2i, actor_grid_position: Vector2i) -> Dictionary:
	"""
	Attempt to place loose/player-made dirt at a grid position.
	The world owns placement legality. The player owns inventory cost.
	"""
	if not is_in_bounds(grid_position):
		return {
			"success": false,
			"message": "Cannot place dirt out of bounds.",
			"tile_type": TileType.AIR
		}
	
	if grid_position == actor_grid_position:
		return {
			"success": false,
			"message": "Cannot place dirt inside yourself.",
			"tile_type": get_tile_type(grid_position)
		}
	
	if not is_placeable(grid_position):
		return {
			"success": false,
			"message": "Cannot place dirt there.",
			"tile_type": get_tile_type(grid_position)
		}
	
	tile_grid[grid_position.y][grid_position.x] = TileType.PLACED_DIRT
	tile_durability.erase(grid_position)
	return {
		"success": true,
		"message": "Placed dirt.",
		"tile_type": TileType.PLACED_DIRT
	}

func try_dig_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Attempt to dig a tile. Returns durability status and resource output.
	"""
	if not is_in_bounds(grid_position):
		return _dig_result(false, false, "Out of bounds.", TileType.AIR, "", 0, 0, 0)
	
	var tile_type: int = get_tile_type(grid_position)
	var current_durability: int = tile_durability.get(grid_position, 0)
	
	match tile_type:
		TileType.EMPTY, TileType.AIR:
			return _dig_result(false, false, "Nothing to dig.", tile_type, "", 0, 0, 0)
		TileType.ROCK:
			return _dig_result(false, false, "Rock is too hard to dig.", tile_type, "", 0, 0, 0)
		TileType.DIRT:
			return _dig_solid_tile(grid_position, tile_type, current_durability, DIRT_MAX_DURABILITY, "dirt", DIRT_PILE_PER_DIRT_TILE)
		TileType.SURFACE:
			return _dig_solid_tile(grid_position, tile_type, current_durability, SURFACE_MAX_DURABILITY, "surface", DIRT_PILE_PER_SURFACE_TILE)
		TileType.PLACED_DIRT:
			return _dig_solid_tile(grid_position, tile_type, current_durability, PLACED_DIRT_MAX_DURABILITY, "placed dirt", DIRT_PILE_PER_PLACED_DIRT_TILE)
		_:
			return _dig_result(false, false, "Cannot dig.", tile_type, "", 0, 0, 0)

func _dig_solid_tile(
	grid_position: Vector2i,
	tile_type: int,
	current_durability: int,
	max_durability: int,
	tile_label: String,
	resource_amount: int
) -> Dictionary:
	if current_durability == 0:
		current_durability = max_durability
	
	current_durability -= 1
	tile_durability[grid_position] = current_durability
	
	if current_durability <= 0:
		tile_grid[grid_position.y][grid_position.x] = TileType.EMPTY
		tile_durability.erase(grid_position)
		return _dig_result(true, true, "Cleared %s tile!" % tile_label, tile_type, "dirt_pile", resource_amount, max_durability, max_durability)
	
	return _dig_result(
		true,
		false,
		"Digging %s: %d / %d" % [tile_label, max_durability - current_durability, max_durability],
		tile_type,
		"",
		0,
		max_durability - current_durability,
		max_durability
	)

func _dig_result(
	success: bool,
	cleared: bool,
	message: String,
	tile_type: int,
	resource_id: String,
	resource_amount: int,
	dig_progress: int,
	dig_required: int
) -> Dictionary:
	return {
		"success": success,
		"cleared": cleared,
		"message": message,
		"tile_type": tile_type,
		"resource_id": resource_id,
		"resource_amount": resource_amount,
		"dig_progress": dig_progress,
		"dig_required": dig_required
	}

func try_eat_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Legacy function - kept for compatibility. Delegates to try_dig_tile.
	"""
	return try_dig_tile(grid_position)

# Regrowth disabled - cleared tiles remain cleared.
# func _update_regrowth_timers(delta: float) -> void:
# 	Cleared soil stays cleared in current implementation.

func get_tile_type_name(tile_type: int) -> String:
	match tile_type:
		TileType.AIR:
			return "AIR"
		TileType.SURFACE:
			return "SURFACE"
		TileType.DIRT:
			return "DIRT"
		TileType.EMPTY:
			return "EMPTY"
		TileType.ROCK:
			return "ROCK"
		TileType.PLACED_DIRT:
			return "PLACED_DIRT"
		_:
			return "UNKNOWN"



-----



test_dirt_world.gd 



class_name TestDirtWorld
extends Node2D

const TILE_SIZE: int = 32
const WORLD_WIDTH: int = 32
const WORLD_HEIGHT: int = 18
const REGROWTH_TIME: float = 20.0

# Grid of dirt tiles: true = has dirt, false = empty
var dirt_grid: Array = []

# Track regrowth timers: position -> remaining time
var regrowth_timers: Dictionary = {}

func _ready() -> void:
	_initialize_dirt_grid()
	_create_visual_representation()

func _process(delta: float) -> void:
	_update_regrowth_timers(delta)
	queue_redraw()

func _initialize_dirt_grid() -> void:
	# Create a 2D array to represent dirt tiles
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			row.append(true)  # All tiles start with dirt
		dirt_grid.append(row)

func _create_visual_representation() -> void:
	# Placeholder - drawing will happen in _draw()
	pass

func _draw() -> void:
	# Draw all tiles
	var dirt_color: Color = Color.html("#8B6914")
	var empty_color: Color = Color.html("#2C1810")
	var border_color: Color = Color.html("#6B4910")
	
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var tile_color: Color = dirt_color if dirt_grid[y][x] else empty_color
			var rect_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), tile_color)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), border_color, false, 1.0)

func eat_dirt_at(world_position: Vector2) -> bool:
	# Convert world position to grid coordinates
	var grid_x: int = int(world_position.x / TILE_SIZE)
	var grid_y: int = int(world_position.y / TILE_SIZE)
	
	# Bounds check
	if grid_x < 0 or grid_x >= WORLD_WIDTH or grid_y < 0 or grid_y >= WORLD_HEIGHT:
		return false
	
	# Check if dirt exists
	if not dirt_grid[grid_y][grid_x]:
		return false
	
	# Remove dirt
	dirt_grid[grid_y][grid_x] = false
	_update_tile_visual(grid_x, grid_y)
	
	# Start regrowth timer
	regrowth_timers[Vector2i(grid_x, grid_y)] = REGROWTH_TIME
	
	return true

func _update_tile_visual(grid_x: int, grid_y: int) -> void:
	var tile_name: String = "Tile_%d_%d" % [grid_x, grid_y]
	var colored_rect: ColorRect = get_node_or_null(tile_name)
	
	if colored_rect:
		if dirt_grid[grid_y][grid_x]:
			colored_rect.color = Color.html("#8B6914")  # Brown dirt
		else:
			colored_rect.color = Color.html("#2C1810")  # Dark empty

func _update_regrowth_timers(delta: float) -> void:
	var positions_to_remove: Array[Vector2i] = []
	
	for pos in regrowth_timers:
		regrowth_timers[pos] -= delta
		
		if regrowth_timers[pos] <= 0.0:
			# Regrow dirt
			dirt_grid[pos.y][pos.x] = true
			_update_tile_visual(pos.x, pos.y)
			positions_to_remove.append(pos)
	
	# Remove completed timers
	for pos in positions_to_remove:
		regrowth_timers.erase(pos)

func get_world_bounds() -> Rect2:
	return Rect2(0, 0, WORLD_WIDTH * TILE_SIZE, WORLD_HEIGHT * TILE_SIZE)



-------



main.gd



class_name Main
extends Node2D

var worm_player: CharacterBody2D
var camera: Camera2D

func _ready() -> void:
	worm_player = find_child("WormPlayer", true, false)
	camera = find_child("Camera2D", true, false)
	
	if not worm_player:
		print("ERROR: WormPlayer not found!")
	if not camera:
		print("ERROR: Camera2D not found!")

func _process(_delta: float) -> void:
	if worm_player and camera:
		camera.global_position = worm_player.global_position



-----





