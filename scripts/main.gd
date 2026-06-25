class_name Main
extends Node2D

var worm_player: CharacterBody2D
var camera: Camera2D
var world: LayeredTestWorld

func _ready() -> void:
	worm_player = find_child("WormPlayer", true, false)
	camera = find_child("Camera2D", true, false)
	world = find_child("LayeredTestWorld", true, false)
	
	if not worm_player:
		print("ERROR: WormPlayer not found!")
	if not camera:
		print("ERROR: Camera2D not found!")
	if not world:
		print("ERROR: LayeredTestWorld not found!")
		return
	
	# Position worm at the world's designated spawn point in the underground pocket
	worm_player.global_position = world.get_start_world_position()

func _process(_delta: float) -> void:
	if worm_player and camera:
		camera.global_position = worm_player.global_position
