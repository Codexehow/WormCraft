class_name WormPlayer
extends CharacterBody2D

# Hunger constants
const MAX_HUNGER: float = 100.0
const STARTING_HUNGER: float = 85.0
const HUNGER_DRAIN_RATE: float = 0.2  # per second
const DIRT_PILE_MEAL_HUNGER_RESTORE: float = 20.0

# Movement constants
const MOVE_SPEED: float = 36.0  # pixels per second — VS009A: reduced for slower crawl
const GRIP_MOVE_SPEED: float = 30.0  # pixels per second — VS009A Part 2E: tuned for visible continuous movement
const GRAVITY: float = 200.0  # pixels per second squared
const MAX_FALL_SPEED: float = MOVE_SPEED * 2.0
const STEP_COOLDOWN_SECONDS: float = 0.16

# Fall tracking constants
const FALL_TRACKING_ENABLED: bool = true
const LETHAL_FALL_TILES: int = 3  # Falls of this magnitude or greater are lethal.
const WARNING_FALL_TILES: int = 2

# Placement constants
const DIRT_PILE_PLACE_COST: int = 1

# Quantum Space Folder capacity
const DIRT_PILE_CAPACITY: int = 30

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

# Fall tracking state
var is_falling: bool = false
var fall_start_grid_y: int = 0
var last_fall_distance_tiles: int = 0
var death_cause: String = ""

# Animation state
var worm_animation: WormAnimation = null
var _horizontal_facing: Vector2 = Vector2.RIGHT

# Grip state — VS009A Part 2
var is_gripping: bool = false
var grip_normal: Vector2 = Vector2.ZERO
var grip_orientation: String = "none"
var grip_target_grid: Vector2i = Vector2i.ZERO
var _was_grip_input_down: bool = false  # Diagnostic: track right-mouse press edge
var _grip_debug_printed: bool = false  # Prevent console spam: only print diagnostics once per press

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

	# Ensure interact action exists (R key for scanning, inspecting, sampling)
	if not InputMap.has_action("interact"):
		var interact_event := InputEventKey.new()
		interact_event.keycode = KEY_R
		InputMap.add_action("interact")
		InputMap.action_add_event("interact", interact_event)
		push_warning("InputMap action 'interact' was missing — created at runtime and bound to R.")

	# Initialize animation helper
	worm_animation = WormAnimation.new()
	add_child(worm_animation)
	worm_animation._ready()

	# Opening mood line — the worm has been here for decades
	last_action = "Still here. Still the only one."

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
	
	# Handle interact input (R key — scanning, inspecting, sampling)
	if Input.is_action_just_pressed("interact"):
		_on_interact_input()

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
	
	# Update animation: determine facing for horizontal movement
	var moving_horizontally: bool = Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
	if moving_horizontally:
		if Input.is_action_pressed("move_left"):
			_horizontal_facing = Vector2.LEFT
		elif Input.is_action_pressed("move_right"):
			_horizontal_facing = Vector2.RIGHT
	
	# Update animation sprite facing (use horizontal facing for left/right, or preserve for up/down)
	var animation_facing = facing_direction if facing_direction != Vector2.UP and facing_direction != Vector2.DOWN else _horizontal_facing
	if worm_animation:
		worm_animation.update_sprite(animation_facing, moving_horizontally)
		worm_animation.update_animation(delta)
	
	if world:
		var current_grid_pos: Vector2i = world.world_to_grid(global_position)
		# Snapshot before any velocity change — used by solid-tile safety guard after move_and_slide()
		var _prev_safe_position: Vector2 = global_position
		var _prev_safe_grid: Vector2i = current_grid_pos
		
		# VS009A Part 2: Right-mouse surface grip check — with diagnostic feedback
		var right_mouse_held: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		
		# Right-mouse press/release edge detection diagnostics
		if right_mouse_held and not _was_grip_input_down:
			print("Right mouse grip input detected.")
			last_action = "Right mouse grip input detected."
			_grip_debug_printed = false  # Reset for next press diagnostics
		if not right_mouse_held and _was_grip_input_down:
			print("Right mouse grip input released.")
			last_action = "Right mouse grip input released."
		_was_grip_input_down = right_mouse_held
		
		var grip_active: bool = false
		
		if right_mouse_held:
			grip_active = _handle_grip_movement(current_grid_pos, horizontal_direction, delta)
		
		if not grip_active:
			# Release grip state if we were gripping but no longer active
			if is_gripping:
				_release_grip()
			
			# Normal movement (Part 1 behavior — slow crawl, no auto step-up)
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
					# VS009A Part 1: Automatic step-up disabled in normal movement.
					# Future right-mouse grip will own deliberate climbing.
					#_try_step_up(current_grid_pos, target_x)
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
				if FALL_TRACKING_ENABLED and not is_falling:
					is_falling = true
					fall_start_grid_y = current_grid_pos.y
				velocity.y += GRAVITY * delta
				velocity.y = clamp(velocity.y, 0.0, MAX_FALL_SPEED)
			else:
				if FALL_TRACKING_ENABLED and is_falling:
					var fall_distance_tiles: int = max(current_grid_pos.y - fall_start_grid_y, 0)
					_resolve_tracked_fall(fall_distance_tiles)
					is_falling = false
					fall_start_grid_y = current_grid_pos.y
				if velocity.y > 0.0:
					velocity.y = 0.0
		
		move_and_slide()
		_update_current_tile()
		
		# Solid-tile safety guard: if worm ended up in a non-passable tile, restore previous safe position
		var _post_move_grid: Vector2i = world.world_to_grid(global_position)
		if _post_move_grid != _prev_safe_grid and not world.is_passable(_post_move_grid) and world.is_passable(_prev_safe_grid):
			global_position = _prev_safe_position
			velocity = Vector2.ZERO
			_release_grip()
			last_action = "Blocked by solid terrain."
			print("Blocked: restored from solid tile ", _post_move_grid, " to ", _prev_safe_grid)
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

# -------- VS009A Part 2: Grip helpers --------

func _get_current_grid_pos() -> Vector2i:
	"""Return the worm's current grid position."""
	return world.world_to_grid(global_position)


func _is_solid_for_grip(grid_pos: Vector2i) -> bool:
	"""Return true if the tile at grid_pos is a valid grip surface (solid, not empty/air/prop)."""
	if not world:
		return false
	if not world.is_in_bounds(grid_pos):
		return false
	var tile_type: int = world.get_tile_type(grid_pos)
	return tile_type == world.TileType.DIRT \
		or tile_type == world.TileType.SURFACE \
		or tile_type == world.TileType.ROCK \
		or tile_type == world.TileType.PLACED_DIRT


func _find_grip_surface_for_grid(grid_pos: Vector2i) -> Dictionary:
	"""Check all four adjacent tiles of grid_pos for a valid grip surface.
	A valid surface means a solid tile (DIRT, SURFACE, ROCK, or PLACED_DIRT)
	adjacent to the given grid position.
	Returns { found: bool, grid: Vector2i, normal: Vector2, orientation: String }."""
	var candidates := [
		{
			"found": true,
			"grid": grid_pos + Vector2i(0, 1),
			"normal": Vector2.UP,
			"orientation": "floor"
		},
		{
			"found": true,
			"grid": grid_pos + Vector2i(-1, 0),
			"normal": Vector2.RIGHT,
			"orientation": "left_wall"
		},
		{
			"found": true,
			"grid": grid_pos + Vector2i(1, 0),
			"normal": Vector2.LEFT,
			"orientation": "right_wall"
		},
		{
			"found": true,
			"grid": grid_pos + Vector2i(0, -1),
			"normal": Vector2.DOWN,
			"orientation": "ceiling"
		}
	]

	for candidate in candidates:
		if _is_solid_for_grip(candidate["grid"]):
			return candidate

	return {"found": false, "grid": Vector2i.ZERO, "normal": Vector2.ZERO, "orientation": "none"}


func _try_grip_corner_crawl(current_grid: Vector2i, input_direction: Vector2i) -> Dictionary:
	"""
	When direct grip movement is blocked by solid terrain, try nearby diagonal
	destinations that let the worm crawl around a one-block lip/corner.
	Only called during right-mouse grip mode.
	Returns { found: bool, destination: Vector2i, surface: Dictionary, message: String }.
	"""
	if not world:
		return {"found": false, "destination": Vector2i.ZERO, "surface": {}, "message": "No world."}

	var candidates: Array[Vector2i] = []
	if input_direction.y < 0:  # Up
		candidates = [current_grid + Vector2i(-1, -1), current_grid + Vector2i(1, -1)]
	elif input_direction.y > 0:  # Down
		candidates = [current_grid + Vector2i(-1, 1), current_grid + Vector2i(1, 1)]
	elif input_direction.x < 0:  # Left
		candidates = [current_grid + Vector2i(-1, -1), current_grid + Vector2i(-1, 1)]
	elif input_direction.x > 0:  # Right
		candidates = [current_grid + Vector2i(1, -1), current_grid + Vector2i(1, 1)]

	for candidate in candidates:
		if not world.is_in_bounds(candidate):
			continue
		if not world.is_passable(candidate):
			continue
		var surface: Dictionary = _find_grip_surface_for_grid(candidate)
		if surface.get("found", false):
			return {
				"found": true,
				"destination": candidate,
				"surface": surface,
				"message": "Grip corner crawl found."
			}

	return {"found": false, "destination": Vector2i.ZERO, "surface": {}, "message": "No corner crawl found."}


func _find_best_grip_surface() -> Dictionary:
	"""
	Check all four adjacent tiles for valid grip surfaces.
	Use mouse position to prefer the surface most aligned with where the player is looking.
	Returns { found: bool, grid: Vector2i, normal: Vector2, orientation: String }.
	"""
	var current_grid: Vector2i = _get_current_grid_pos()
	
	# Diagnostic: report tile state — only once per press to avoid spam
	if not _grip_debug_printed:
		var below_grid: Vector2i = current_grid + Vector2i(0, 1)
		var left_grid: Vector2i = current_grid + Vector2i(-1, 0)
		var right_grid: Vector2i = current_grid + Vector2i(1, 0)
		var above_grid: Vector2i = current_grid + Vector2i(0, -1)
		print("Grip surface check — current grid: %s, below solid: %s, left solid: %s, right solid: %s, above solid: %s" % [
			current_grid,
			_is_solid_for_grip(below_grid),
			_is_solid_for_grip(left_grid),
			_is_solid_for_grip(right_grid),
			_is_solid_for_grip(above_grid)
		])
	
	var candidates := [
		{
			"found": true,
			"grid": current_grid + Vector2i(0, 1),
			"normal": Vector2.UP,
			"orientation": "floor"
		},
		{
			"found": true,
			"grid": current_grid + Vector2i(-1, 0),
			"normal": Vector2.RIGHT,
			"orientation": "left_wall"
		},
		{
			"found": true,
			"grid": current_grid + Vector2i(1, 0),
			"normal": Vector2.LEFT,
			"orientation": "right_wall"
		},
		{
			"found": true,
			"grid": current_grid + Vector2i(0, -1),
			"normal": Vector2.DOWN,
			"orientation": "ceiling"
		}
	]
	
	# Collect valid candidates
	var valid_candidates: Array[Dictionary] = []
	for candidate in candidates:
		if _is_solid_for_grip(candidate["grid"]):
			valid_candidates.append(candidate)
	
	if valid_candidates.is_empty():
		return {"found": false, "grid": Vector2i.ZERO, "normal": Vector2.ZERO, "orientation": "none"}
	
	# Use mouse position to prefer the surface most aligned with the mouse direction
	var mouse_world_pos: Vector2 = get_global_mouse_position()
	var mouse_dir: Vector2 = (mouse_world_pos - global_position).normalized()
	
	var preferred_orientation: String = "floor"
	if abs(mouse_dir.x) > abs(mouse_dir.y):
		if mouse_dir.x < 0.0:
			preferred_orientation = "left_wall"
		else:
			preferred_orientation = "right_wall"
	else:
		if mouse_dir.y < 0.0:
			preferred_orientation = "ceiling"
		else:
			preferred_orientation = "floor"
	
	# Try to return the preferred orientation first
	for candidate in valid_candidates:
		if candidate["orientation"] == preferred_orientation:
			return candidate
	
	# Fall back to the first valid candidate
	return valid_candidates[0]


func _handle_grip_movement(current_grid_pos: Vector2i, _horizontal_direction: Vector2, delta: float) -> bool:
	"""
	Surface crawl movement while right-mouse grip is held.
	The worm may move into any passable destination tile that is adjacent
	to at least one solid grip surface. This allows crawling around corners
	and across irregular terrain without requiring a perfect continuous wall.
	"""
	# Terrain contact validation — anti-flying: grip only works while worm is
	# in a passable tile adjacent to at least one solid grip surface.
	var current_check: Vector2i = _get_current_grid_pos()
	if not world.is_passable(current_check):
		_release_grip()
		velocity = Vector2.ZERO
		last_action = "Grip lost: inside solid terrain."
		print("Grip lost: inside solid terrain at ", current_check)
		return false
	
	var result: Dictionary = _find_best_grip_surface()
	var grip_found: bool = result.get("found", false)
	
	# Only print grip-found line once per press to avoid spam
	if not _grip_debug_printed:
		print("_handle_grip_movement: found=%s, orientation=%s" % [grip_found, result.get("orientation", "none")])
		_grip_debug_printed = true
	
	if not grip_found:
		_release_grip()
		last_action = "Grip lost: no adjacent terrain."
		print("Grip lost: no adjacent terrain at ", current_check)
		return false
	
	# Lock orientation on first grip frame — prevents flickering from mouse position changes
	if not is_gripping:
		grip_orientation = result.get("orientation", "none")
		grip_target_grid = result.get("grid", Vector2i.ZERO)
		grip_normal = result.get("normal", Vector2.ZERO)
		last_action = "Gripping: %s" % grip_orientation
	
	is_gripping = true
	
	# Suspend gravity during grip
	velocity.y = 0.0
	
	# Read directional input for surface crawl.
	# Prioritize vertical input (W/S) over horizontal input (A/D) when both are pressed.
	var grip_input := Vector2.ZERO
	var input_up: bool = Input.is_action_pressed("move_up")
	var input_down: bool = Input.is_action_pressed("move_down")
	var input_left: bool = Input.is_action_pressed("move_left")
	var input_right: bool = Input.is_action_pressed("move_right")
	
	if input_up:
		grip_input.y = -1.0
	elif input_down:
		grip_input.y = 1.0
	elif input_left:
		grip_input.x = -1.0
	elif input_right:
		grip_input.x = 1.0
	
	if grip_input == Vector2.ZERO:
		velocity.x = 0.0
		velocity.y = 0.0
		return true
	
	# Determine direction name for debug logging
	var dir_name: String = "none"
	if grip_input.y < 0.0:
		dir_name = "up"
	elif grip_input.y > 0.0:
		dir_name = "down"
	elif grip_input.x < 0.0:
		dir_name = "left"
	elif grip_input.x > 0.0:
		dir_name = "right"
	
	# Calculate destination grid tile
	var destination_grid: Vector2i = current_grid_pos + Vector2i(int(grip_input.x), int(grip_input.y))
	
	print("Grip move attempt: direction=%s, current=%s, dest=%s" % [dir_name, current_grid_pos, destination_grid])
	
	# Check 1: Destination must be passable (AIR or EMPTY)
	if not world.is_passable(destination_grid):
		velocity = Vector2.ZERO
		print("Grip direct blocked: destination not passable at %s" % destination_grid)
		print("Trying grip corner crawl...")
		# Attempt corner crawl around the blocking tile
		var corner_input: Vector2i = Vector2i(int(grip_input.x), int(grip_input.y))
		var corner_result: Dictionary = _try_grip_corner_crawl(current_grid_pos, corner_input)
		if corner_result.get("found", false):
			var candidate: Vector2i = corner_result.get("destination", Vector2i.ZERO)
			var surface: Dictionary = corner_result.get("surface", {})
			var move_vector: Vector2 = Vector2(candidate.x - current_grid_pos.x, candidate.y - current_grid_pos.y).normalized()
			var cc_intended: Vector2 = move_vector * GRIP_MOVE_SPEED
			var cc_predicted_pos: Vector2 = global_position + cc_intended * delta
			var cc_predicted_grid: Vector2i = world.world_to_grid(cc_predicted_pos)
			# Terrain-aware check: predicted corner crawl path must not enter solid
			if not world.is_passable(cc_predicted_grid):
				print("Grip corner crawl failed: no safe terrain-aware candidate.")
				last_action = "Grip blocked: no corner crawl available."
				return true
			if not _find_grip_surface_for_grid(cc_predicted_grid).get("found", false):
				print("Grip corner crawl failed: no safe terrain-aware candidate.")
				last_action = "Grip blocked: no corner crawl available."
				return true
			velocity = cc_intended
			grip_orientation = surface.get("orientation", grip_orientation)
			grip_normal = surface.get("normal", grip_normal)
			grip_target_grid = surface.get("grid", grip_target_grid)
			last_action = "Grip corner crawl: %s" % surface.get("orientation", "unknown")
			print("Grip corner crawl: current=%s, candidate=%s, surface=%s" % [current_grid_pos, candidate, surface.get("orientation", "none")])
			return true
		else:
			print("Grip corner crawl failed: no passable adjacent surface.")
			last_action = "Grip blocked: no corner crawl available."
			return true
	
	# Check 2: Destination must have at least one adjacent solid grip surface
	var new_surface: Dictionary = _find_grip_surface_for_grid(destination_grid)
	if not new_surface.get("found", false):
		velocity = Vector2.ZERO
		print("Grip blocked: no adjacent surface at %s" % destination_grid)
		last_action = "Grip blocked: no adjacent surface at %s" % destination_grid
		return true
	
	# Predicted position check — anti-clipping: verify velocity does not push into solid
	var intended_velocity: Vector2 = Vector2(grip_input.x, grip_input.y) * GRIP_MOVE_SPEED
	var predicted_position: Vector2 = global_position + intended_velocity * delta
	var predicted_grid: Vector2i = world.world_to_grid(predicted_position)
	
	if not world.is_passable(predicted_grid):
		velocity = Vector2.ZERO
		print("Grip blocked: predicted solid terrain at ", predicted_grid)
		last_action = "Grip blocked: predicted solid terrain."
		return true
	
	if not _find_grip_surface_for_grid(predicted_grid).get("found", false):
		_release_grip()
		velocity = Vector2.ZERO
		print("Grip lost: no surface at predicted position ", predicted_grid)
		last_action = "Grip lost: no surface at predicted position."
		return false
	
	# Both checks passed — allow movement at grip speed
	velocity = intended_velocity
	
	# Update grip state based on the new surface at the destination.
	# This allows the worm to transition between surfaces (e.g. right_wall -> ceiling)
	# without requiring a perfect continuous wall.
	grip_orientation = new_surface.get("orientation", grip_orientation)
	grip_normal = new_surface.get("normal", grip_normal)
	grip_target_grid = new_surface.get("grid", grip_target_grid)
	
	print("Grip moving: %s, velocity=(%d,%d), new_surface=%s" % [dir_name, int(grip_input.x * GRIP_MOVE_SPEED), int(grip_input.y * GRIP_MOVE_SPEED), new_surface.get("orientation", "none")])
	
	return true


func _release_grip() -> void:
	"""Clear grip state immediately. Gravity will resume naturally."""
	if is_gripping:
		print("_release_grip called — clearing grip state.")
	is_gripping = false
	grip_normal = Vector2.ZERO
	grip_orientation = "none"
	grip_target_grid = Vector2i.ZERO


# -------- End VS009A Part 2 --------

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

	# Trigger dig animation even if digging fails — the worm still tries
	if worm_animation:
		worm_animation.play_dig(facing_direction)
	
	if result["success"] and result["cleared"]:
		if result["resource_id"] == "dirt_pile":
			var amount: int = result["resource_amount"]
			var added: int = _add_inventory_item("dirt_pile", amount)
			dirt_dug_count += 1

			if added < amount:
				var wasted: int = amount - added
				if added > 0:
					last_action = "Folder full. Added %d, wasted %d soil." % [added, wasted]
				else:
					last_action = "Folder full. Soil wasted."
	
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

func _on_interact_input() -> void:
	"""
	Handle interact input (R key). Scans/inspects the prop in front of the worm.
	"""
	print("Interact pressed.")
	if not is_alive or not world:
		return

	var target_grid_pos: Vector2i = _get_target_grid_pos()
	# Use fallback range (Manhattan distance <= 1 around target) to make
	# interaction reachable even if the worm isn't perfectly aligned to the prop tile.
	var result: Dictionary = world.try_interact_prop_near(target_grid_pos, 1)

	last_action = result["message"]

	if result["success"]:
		var resource_id: String = result.get("resource_id", "")
		var amount: int = result.get("resource_amount", 0)
		if resource_id != "" and amount > 0:
			_add_inventory_item(resource_id, amount)

		# Spawn particle burst at effect position
		var effect_pos: Vector2 = result.get("effect_world_pos", Vector2.ZERO)
		if effect_pos != Vector2.ZERO:
			world._spawn_scan_particles_at(effect_pos)

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

func _add_inventory_item(item_id: String, amount: int) -> int:
	"""Add items to inventory respecting Quantum Space Folder capacity. Returns amount actually added."""
	if item_id == "dirt_pile":
		var current_amount: int = inventory.get("dirt_pile", 0)
		var available_space: int = max(DIRT_PILE_CAPACITY - current_amount, 0)
		var amount_added: int = min(amount, available_space)
		inventory["dirt_pile"] = current_amount + amount_added
		emit_signal("inventory_changed", inventory)
		return amount_added

	# Non-capacity items — add freely
	inventory[item_id] = inventory.get(item_id, 0) + amount
	emit_signal("inventory_changed", inventory)
	return amount


func _update_current_tile() -> void:
	if world:
		var grid_pos: Vector2i = world.world_to_grid(global_position)
		current_tile_type = world.get_tile_type(grid_pos)
		emit_signal("tile_changed", current_tile_type)

func _resolve_tracked_fall(fall_distance_tiles: int) -> void:
	last_fall_distance_tiles = fall_distance_tiles

	if fall_distance_tiles <= 0:
		return

	if fall_distance_tiles >= LETHAL_FALL_TILES:
		last_action = "Fell %d tiles. The worm ruptured." % fall_distance_tiles
		print(last_action)
		_on_fall_death()
	elif fall_distance_tiles >= WARNING_FALL_TILES:
		last_action = "Fell %d tiles. Dangerous drop." % fall_distance_tiles
		print(last_action)
	else:
		last_action = "Fell %d tile." % fall_distance_tiles
		print(last_action)


func _on_fall_death() -> void:
	if not is_alive:
		return

	is_alive = false
	death_cause = "fall"
	velocity = Vector2.ZERO
	emit_signal("worm_died")

func _on_starve() -> void:
	if not is_alive:
		return

	is_alive = false
	death_cause = "starvation"
	velocity = Vector2.ZERO
	last_action = "The worm has starved."
	print(last_action)
	emit_signal("worm_died")

func get_status_text() -> String:
	if is_alive:
		return "Alive"

	match death_cause:
		"starvation":
			return "Starved"
		"fall":
			return "Dead - Fall"
		_:
			return "Dead"

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

func get_inventory_capacity(item_id: String) -> int:
	"""Get max capacity for a capacity-limited inventory item."""
	if item_id == "dirt_pile":
		return DIRT_PILE_CAPACITY
	return -1

func get_last_fall_distance_tiles() -> int:
	return last_fall_distance_tiles


func get_dig_target_grid_pos() -> Vector2i:
	"""Public wrapper: returns the grid position of the tile that would be dug."""
	return _get_dig_target_grid_pos()

func get_place_target_grid_pos() -> Vector2i:
	"""Public wrapper: returns the grid position of the tile where dirt would be placed."""
	return _get_target_grid_pos()
