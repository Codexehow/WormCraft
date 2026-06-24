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
