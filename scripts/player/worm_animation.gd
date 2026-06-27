class_name WormAnimation
extends Node

# Preload textures
var crawl_right_texture: Texture2D = preload("res://assets/sprites/worm_crawl_right_scaled.png")
var crawl_left_texture: Texture2D = preload("res://assets/sprites/worm_crawl_left_scaled.png")

var sprite: Sprite2D
var current_facing: Vector2 = Vector2.RIGHT
var animation_frame: int = 0
var animation_time: float = 0.0
var animation_fps: float = 8.0
var is_moving: bool = false

# Dig animation state
var is_digging: bool = false
var dig_time: float = 0.0
var dig_duration: float = 0.22
var dig_facing: Vector2 = Vector2.RIGHT

# Base offset/scale for restoration after animation
var base_offset: Vector2 = Vector2.ZERO
var base_scale: Vector2 = Vector2.ONE
var base_offset_initialized: bool = false

# Surface orientation state — set by worm_player via set_surface_orientation()
var surface_orientation: String = "none"

# Head direction while wall-gripping — VS009A Part 3E
# Vector2.UP = head points up while climbing, Vector2.DOWN = head points down
var wall_head_direction: Vector2 = Vector2.UP

# -- VS009A Part 3B-D Diagnostic --
var orientation_debug_logging: bool = false
var _last_reported_surface_orientation: String = ""

# Offset presets per surface orientation
var default_sprite_offset: Vector2 = Vector2.ZERO
var floor_sprite_offset: Vector2 = Vector2.ZERO

# Wall offset presets — VS009A Part 3E-R1: four cases for head-up/head-down on each wall
var left_wall_head_up_sprite_offset: Vector2 = Vector2.ZERO
var left_wall_head_down_sprite_offset: Vector2 = Vector2.ZERO
var right_wall_head_up_sprite_offset: Vector2 = Vector2.ZERO
var right_wall_head_down_sprite_offset: Vector2 = Vector2.ZERO

# Backward-compatible aliases (point to head-up presets)
var left_wall_sprite_offset: Vector2:
	get: return left_wall_head_up_sprite_offset
	set(v): left_wall_head_up_sprite_offset = v
var right_wall_sprite_offset: Vector2:
	get: return right_wall_head_up_sprite_offset
	set(v): right_wall_head_up_sprite_offset = v

# Floor rotation
const FLOOR_ROTATION: float = 0.0

# Ceiling rotation — flip upside down (180°)
const CEILING_ROTATION: float = PI

# Wall visual head state helpers — VS009A Part 3F
const WALL_HEAD_UP := "head_up"
const WALL_HEAD_DOWN := "head_down"

# --- Explicit wall visual presets — VS009A Part 3F ---
# Each wall+head combination explicitly chooses: texture, rotation, offset.
# No derived math, no formulas — these are hand-tuned visual constants.
#
# Texture logic:
#   left wall  always uses crawl_right_texture (head on right)
#   right wall always uses crawl_left_texture  (head on left)
# When rotated, the head side points in the climb direction.

# Left wall rotations
const LEFT_WALL_HEAD_UP_ROTATION: float = -PI / 2.0   # CCW 90°: right side (head) → up
const LEFT_WALL_HEAD_DOWN_ROTATION: float = PI / 2.0   # CW 90°:  right side (head) → down

# Right wall rotations
const RIGHT_WALL_HEAD_UP_ROTATION: float = PI / 2.0    # CW 90°:  left side (head) → up
const RIGHT_WALL_HEAD_DOWN_ROTATION: float = -PI / 2.0  # CCW 90°: left side (head) → down

# Wall offsets — all start at known-good Part 3D value Vector2(-32.0, -32.0)
# Tune head-down offsets separately from head-up if visual testing shows drift.
const LEFT_WALL_HEAD_UP_OFFSET := Vector2(-32.0, -32.0)
const LEFT_WALL_HEAD_DOWN_OFFSET := Vector2(-32.0, -32.0)
const RIGHT_WALL_HEAD_UP_OFFSET := Vector2(-32.0, -32.0)
const RIGHT_WALL_HEAD_DOWN_OFFSET := Vector2(-32.0, -32.0)

func _ready() -> void:
	sprite = get_parent().get_node_or_null("Sprite2D")
	if sprite:
		sprite.hframes = 4
		sprite.vframes = 1
		base_offset = sprite.offset
		base_scale = sprite.scale
		base_offset_initialized = true
		default_sprite_offset = sprite.offset
		floor_sprite_offset = default_sprite_offset
		# VS009A Part 3F: Explicit wall preset offsets — direct values, no derived math.
		left_wall_head_up_sprite_offset = LEFT_WALL_HEAD_UP_OFFSET
		left_wall_head_down_sprite_offset = LEFT_WALL_HEAD_DOWN_OFFSET
		right_wall_head_up_sprite_offset = RIGHT_WALL_HEAD_UP_OFFSET
		right_wall_head_down_sprite_offset = RIGHT_WALL_HEAD_DOWN_OFFSET
		update_texture()

func update_sprite(facing: Vector2, moving: bool) -> void:
	current_facing = facing
	is_moving = moving
	update_texture()

func update_texture() -> void:
	if not sprite:
		return
	
	# VS009A Part 3F: When wall-gripping, texture is owned by _apply_surface_visuals().
	# Do not overwrite the wall preset texture with floor-facing logic.
	# Ceiling uses floor-style facing-based textures, not wall-style locked textures.
	if surface_orientation == "left_wall" or surface_orientation == "right_wall":
		return
	
	var new_texture = crawl_right_texture if current_facing != Vector2.LEFT else crawl_left_texture
	if sprite.texture != new_texture:
		sprite.texture = new_texture
		animation_frame = 0
		animation_time = 0.0

func update_animation(delta: float) -> void:
	if not sprite:
		return

	# Dig animation takes priority over crawl/idle
	if is_digging:
		_update_dig_animation(delta)
		return

	if not is_moving:
		if sprite.frame != 0:
			sprite.frame = 0
		animation_time = 0.0
		animation_frame = 0
		_apply_surface_visuals()
		sprite.scale = base_scale
		return

	animation_time += delta
	var frame_duration = 1.0 / animation_fps

	while animation_time >= frame_duration:
		animation_time -= frame_duration
		animation_frame = (animation_frame + 1) % 4
		sprite.frame = animation_frame

func play_dig(facing: Vector2) -> void:
	if not sprite:
		return

	dig_facing = facing
	is_digging = true
	dig_time = 0.0

	if facing == Vector2.LEFT:
		current_facing = Vector2.LEFT
	elif facing == Vector2.RIGHT:
		current_facing = Vector2.RIGHT

	update_texture()

func _update_dig_animation(delta: float) -> void:
	dig_time += delta

	var progress: float = clamp(dig_time / dig_duration, 0.0, 1.0)
	var punch: float = sin(progress * PI)

	var direction: Vector2 = dig_facing
	if direction == Vector2.ZERO:
		direction = current_facing
	direction = direction.normalized()

	var lunge_pixels: float = 5.0

	# Hold first frame during dig
	sprite.frame = 0

	# Lunge toward dig direction
	sprite.offset = base_offset + direction * lunge_pixels * punch

	# Subtle squash/stretch
	if abs(direction.x) > abs(direction.y):
		# Horizontal dig: stretch horizontally, squash vertically
		sprite.scale = base_scale * Vector2(1.04, 0.96)
	else:
		# Vertical dig: squash horizontally, stretch vertically
		sprite.scale = base_scale * Vector2(0.98, 1.04)

	if dig_time >= dig_duration:
		is_digging = false
		dig_time = 0.0
		_apply_surface_visuals()
		sprite.scale = base_scale


func set_wall_head_direction(direction: Vector2) -> void:
	"""Public API: set the visual head direction while wall-gripping.
	Vector2.UP = head points up during wall climb.
	Vector2.DOWN = head points down during wall climb.
	Ignores horizontal directions to avoid visual corruption."""
	if direction == Vector2.UP:
		wall_head_direction = Vector2.UP
	elif direction == Vector2.DOWN:
		wall_head_direction = Vector2.DOWN
	else:
		return

	_apply_surface_visuals()


func set_surface_orientation(new_orientation: String) -> void:
	"""Public API: set the current surface orientation and apply matching offset preset.
	Accepts 'none', 'floor', 'left_wall', 'right_wall'.
	Unknown orientations fall back to 'none'."""
	var resolved_orientation: String = new_orientation
	match new_orientation:
		"floor", "left_wall", "right_wall", "ceiling", "none":
			resolved_orientation = new_orientation
		_:
			resolved_orientation = "none"

	if orientation_debug_logging and resolved_orientation != surface_orientation:
		print("ANIMATION received orientation: ", surface_orientation, " -> ", resolved_orientation)

	surface_orientation = resolved_orientation
	_apply_surface_visuals()


func _get_wall_head_state() -> String:
	"""Resolve wall_head_direction to a readable state string for preset lookup."""
	if wall_head_direction == Vector2.DOWN:
		return WALL_HEAD_DOWN
	return WALL_HEAD_UP


func _apply_floor_visuals() -> void:
	"""Floor visuals: horizontal, default offset, texture from current_facing."""
	sprite.offset = floor_sprite_offset
	sprite.rotation = FLOOR_ROTATION
	sprite.modulate = Color.WHITE
	# Floor texture is handled by update_texture() based on current_facing


func _apply_left_wall_visuals() -> void:
	"""Left wall stable preset: always uses crawl_right_texture at -PI/2.
	# VS009A Part 3F-R1: Dynamic head-up/head-down wall flipping disabled for now.
	# The current horizontal sprite pivot causes offset drift when rotated 180°.
	# Future wall-specific sprites or better pivots can restore directional wall head orientation."""
	sprite.texture = crawl_right_texture
	sprite.rotation = LEFT_WALL_HEAD_UP_ROTATION
	sprite.offset = left_wall_head_up_sprite_offset
	sprite.modulate = Color.WHITE


func _apply_right_wall_visuals() -> void:
	"""Right wall stable preset: always uses crawl_left_texture at PI/2.
	# VS009A Part 3F-R1: Dynamic head-up/head-down wall flipping disabled for now.
	# The current horizontal sprite pivot causes offset drift when rotated 180°.
	# Future wall-specific sprites or better pivots can restore directional wall head orientation."""
	sprite.texture = crawl_left_texture
	sprite.rotation = RIGHT_WALL_HEAD_UP_ROTATION
	sprite.offset = right_wall_head_up_sprite_offset
	sprite.modulate = Color.WHITE


func _apply_ceiling_visuals() -> void:
	"""Ceiling visuals: face direction determines texture, rotate 180° upside down.
	Uses the same facing-based texture logic as floor but with upside-down rotation.
	Offset uses the floor/ceiling default offset with no wall-specific tuning needed."""
	sprite.rotation = CEILING_ROTATION
	sprite.offset = floor_sprite_offset
	sprite.modulate = Color.WHITE
	# Ceiling texture is handled by update_texture() based on current_facing, same as floor.


func _apply_surface_visuals() -> void:
	"""Apply the sprite offset and rotation preset for the current surface_orientation.
	Floor uses floor preset. Wall uses explicit per-case presets that set texture, rotation, and offset.
	Only the Sprite2D visually rotates — player node, collision, and grid anchor remain unchanged."""
	if not sprite:
		return

	match surface_orientation:
		"floor":
			_apply_floor_visuals()
		"left_wall":
			_apply_left_wall_visuals()
		"right_wall":
			_apply_right_wall_visuals()
		"ceiling":
			_apply_ceiling_visuals()
		_:
			_apply_floor_visuals()

	if orientation_debug_logging and surface_orientation != _last_reported_surface_orientation:
		print("SPRITE visuals applied: orientation=", surface_orientation,
			" rotation=", sprite.rotation,
			" degrees=", sprite.rotation_degrees,
			" offset=", sprite.offset,
			" scale=", sprite.scale,
			" sprite=", sprite.name,
			" path=", sprite.get_path())
		_last_reported_surface_orientation = surface_orientation
