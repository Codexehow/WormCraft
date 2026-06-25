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

func _ready() -> void:
	sprite = get_parent().get_node_or_null("Sprite2D")
	if sprite:
		sprite.hframes = 4
		sprite.vframes = 1
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
	
	if not is_moving:
		if sprite.frame != 0:
			sprite.frame = 0
		animation_time = 0.0
		animation_frame = 0
		return
	
	animation_time += delta
	var frame_duration = 1.0 / animation_fps
	
	while animation_time >= frame_duration:
		animation_time -= frame_duration
		animation_frame = (animation_frame + 1) % 4
		sprite.frame = animation_frame
