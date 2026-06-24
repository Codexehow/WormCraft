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
