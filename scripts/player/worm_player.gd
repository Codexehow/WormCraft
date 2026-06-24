class_name WormPlayer
extends CharacterBody2D

# Hunger constants
const MAX_HUNGER: float = 100.0
const STARTING_HUNGER: float = 85.0
const HUNGER_DRAIN_RATE: float = 0.2  # per second (much slower than before)
const DIRT_PILE_MEAL_HUNGER_RESTORE: float = 20.0

# Movement constants
const MOVE_SPEED: float = 60.0  # pixels per second (adjusted for 16px tiles)
const GRAVITY: float = 200.0  # pixels per second squared

# Inventory
var inventory: Dictionary = {
	"dirt_pile": 0
}

# State
var hunger: float = STARTING_HUNGER
var max_hunger: float = MAX_HUNGER
var is_alive: bool = true
var dirt_dug_count: int = 0  # Number of dirt tiles cleared
var current_tile_type: int = LayeredTestWorld.TileType.EMPTY
var facing_direction: Vector2 = Vector2.RIGHT
var last_action: String = ""

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
	
	# Initialize hunger
	hunger = STARTING_HUNGER
	emit_signal("hunger_changed", hunger)
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

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	var horizontal_direction: Vector2 = Vector2.ZERO
	
	# Handle horizontal movement input
	if Input.is_action_pressed("move_left"):
		horizontal_direction.x -= 1.0
		facing_direction = Vector2.LEFT
	if Input.is_action_pressed("move_right"):
		horizontal_direction.x += 1.0
		facing_direction = Vector2.RIGHT
	
	# Handle facing direction from vertical input (but not movement)
	# W/Up and S/Down primarily change facing direction, not apply vertical movement
	if Input.is_action_pressed("move_up"):
		facing_direction = Vector2.UP
	if Input.is_action_pressed("move_down"):
		facing_direction = Vector2.DOWN
	
	if world:
		var current_grid_pos: Vector2i = world.world_to_grid(global_position)
		
		# Apply horizontal movement
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
		else:
			velocity.x = 0.0
		
		# Gravity-driven vertical movement
		# The worm does not freely move upward via input.
		# W/S change facing direction only, allowing upward/downward digging.
		# Gravity always pulls downward when unsupported.
		var next_grid_y: int = current_grid_pos.y + 1
		var below_pos: Vector2i = Vector2i(current_grid_pos.x, next_grid_y)
		
		# Check if there's solid ground below
		if world.is_passable(below_pos):
			# Space below is passable (air/empty), so worm falls
			velocity.y += GRAVITY * delta
			velocity.y = clamp(velocity.y, -MOVE_SPEED, MOVE_SPEED * 2)
		else:
			# Space below is solid, worm is on ground
			velocity.y = 0.0
		
		move_and_slide()
		_update_current_tile()

func _on_dig_input() -> void:
	"""
	Handle digging action. Digs the tile in front of the worm.
	"""
	if not is_alive or not world:
		return
	
	# Get current grid position
	var current_grid_pos: Vector2i = world.world_to_grid(global_position)
	
	# Calculate target grid position based on facing direction
	var target_grid_pos: Vector2i = current_grid_pos
	if facing_direction == Vector2.LEFT:
		target_grid_pos.x -= 1
	elif facing_direction == Vector2.RIGHT:
		target_grid_pos.x += 1
	elif facing_direction == Vector2.UP:
		target_grid_pos.y -= 1
	elif facing_direction == Vector2.DOWN:
		target_grid_pos.y += 1
	
	# Try to dig the tile at target position
	var result: Dictionary = world.try_dig_tile(target_grid_pos)
	
	if result["success"]:
		last_action = result["message"]
		
		# If tile was fully cleared, add resource to inventory
		if result["cleared"]:
			if result["resource_id"] == "dirt_pile":
				inventory["dirt_pile"] += result["resource_amount"]
				dirt_dug_count += 1
				emit_signal("inventory_changed", inventory)
		
		print(result["message"])
	else:
		last_action = result["message"]
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
