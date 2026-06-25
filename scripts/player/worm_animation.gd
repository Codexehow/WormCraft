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

func _ready() -> void:
	sprite = get_parent().get_node_or_null("Sprite2D")
	if sprite:
		sprite.hframes = 4
		sprite.vframes = 1
		base_offset = sprite.offset
		base_scale = sprite.scale
		base_offset_initialized = true
		update_texture()

func update_sprite(facing: Vector2, moving: bool) -> void:
	current_facing = facing
	is_moving = moving
	update_texture()

func update_texture() -> void:
	if not sprite:
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
		sprite.offset = base_offset
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
		sprite.offset = base_offset
		sprite.scale = base_scale
