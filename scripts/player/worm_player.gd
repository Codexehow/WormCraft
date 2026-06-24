class_name WormPlayer
extends CharacterBody2D

const MAX_HUNGER: float = 100.0
const STARTING_HUNGER: float = 75.0
const HUNGER_DRAIN_RATE: float = 2.0  # per second
const HUNGER_RESTORE: float = 20.0
const MOVE_SPEED: float = 100.0  # pixels per second

var hunger: float = STARTING_HUNGER
var max_hunger: float = MAX_HUNGER
var is_alive: bool = true
var dirt_eaten_count: int = 0
var current_tile_type: int = LayeredTestWorld.TileType.EMPTY
var facing_direction: Vector2 = Vector2.RIGHT

# Reference to the world
var world: LayeredTestWorld

# Signals
signal hunger_changed(new_hunger: float)
signal dirt_eaten
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
	
	# Handle eating input
	if Input.is_action_just_pressed("eat"):
		_on_eat_input()

func _physics_process(_delta: float) -> void:
	if not is_alive:
		return
	
	var direction: Vector2 = Vector2.ZERO
	
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
		facing_direction = Vector2.LEFT
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
		facing_direction = Vector2.RIGHT
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
		facing_direction = Vector2.UP
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
		facing_direction = Vector2.DOWN
	
	if direction.length() > 0.0 and world:
		direction = direction.normalized()
		
		# Check if the target tile is passable before moving
		var current_grid_pos: Vector2i = world.world_to_grid(global_position)
		var target_grid_pos: Vector2i = current_grid_pos
		
		if direction.x < 0:  # Moving left
			target_grid_pos.x -= 1
		elif direction.x > 0:  # Moving right
			target_grid_pos.x += 1
		elif direction.y < 0:  # Moving up
			target_grid_pos.y -= 1
		elif direction.y > 0:  # Moving down
			target_grid_pos.y += 1
		
		# Only move if the target tile is passable
		if world.is_passable(target_grid_pos):
			velocity = direction * MOVE_SPEED
			move_and_slide()
			_update_current_tile()
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

func _on_eat_input() -> void:
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
	
	# Try to eat the tile at target position
	var result: Dictionary = world.try_eat_tile(target_grid_pos)
	
	if result["success"]:
		hunger = clamp(hunger + result["hunger_restore"], 0.0, max_hunger)
		dirt_eaten_count += 1
		emit_signal("hunger_changed", hunger)
		emit_signal("dirt_eaten")
		print(result["message"])
	else:
		print(result["message"])

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
