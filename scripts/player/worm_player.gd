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

# Reference to the dirt world
var dirt_world: Node2D

# Signals
signal hunger_changed(new_hunger: float)
signal dirt_eaten
signal worm_died

func _ready() -> void:
	# Find the dirt world
	dirt_world = get_tree().root.find_child("TestDirtWorld", true, false)
	
	# Initialize hunger
	hunger = STARTING_HUNGER
	emit_signal("hunger_changed", hunger)

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
	
	# Handle movement input
	_handle_movement(delta)
	
	# Handle eating input
	if Input.is_action_just_pressed("eat"):
		_on_eat_input()

func _handle_movement(_delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	
	if direction.length() > 0.0:
		direction = direction.normalized()
		velocity = direction * MOVE_SPEED
		move_and_slide()
	else:
		velocity = Vector2.ZERO

func _on_eat_input() -> void:
	if not is_alive:
		return
	
	# For now, just eat dirt at the worm's current position
	if dirt_world:
		if dirt_world.eat_dirt_at(global_position):
			hunger = clamp(hunger + HUNGER_RESTORE, 0.0, max_hunger)
			dirt_eaten_count += 1
			emit_signal("hunger_changed", hunger)
			emit_signal("dirt_eaten")
			print("Ate dirt. Hunger restored. (Count: %d)" % dirt_eaten_count)

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
