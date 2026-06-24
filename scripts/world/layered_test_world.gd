class_name LayeredTestWorld
extends Node2D

## Tile type enum
enum TileType {
	AIR,
	SURFACE,
	DIRT,
	EMPTY,
	ROCK
}

const TILE_SIZE: int = 32
const WORLD_WIDTH: int = 32
const WORLD_HEIGHT: int = 18

# Grid of tile types
var tile_grid: Array = []

# Cleared tiles remain cleared - no automatic regrowth in early development
# Future ecology/weather systems may reclaim tunnels, but cleared soil remains cleared during core gameplay

# Visual colors for each tile type
var tile_colors: Dictionary = {
	TileType.AIR: Color.html("#1a1a2e"),      # Dark blue/black
	TileType.SURFACE: Color.html("#2d5016"),  # Green/brown surface
	TileType.DIRT: Color.html("#8B6914"),     # Brown dirt
	TileType.EMPTY: Color.html("#2C1810"),    # Dark empty
	TileType.ROCK: Color.html("#808080")      # Gray rock
}

var border_color: Color = Color.html("#6B4910")

func _ready() -> void:
	_initialize_layered_world()

func _process(delta: float) -> void:
	queue_redraw()

func _initialize_layered_world() -> void:
	# Create empty 2D grid
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			row.append(TileType.DIRT)
		tile_grid.append(row)
	
	# Create layered world structure
	# Rows 0-3: AIR
	for y in range(4):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.AIR
	
	# Row 4: SURFACE
	for x in range(WORLD_WIDTH):
		tile_grid[4][x] = TileType.SURFACE
	
	# Rows 5-17: Mostly DIRT with some rocks and empty tunnel pocket
	for y in range(5, WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.DIRT
	
	# Add rocks at strategic locations
	tile_grid[7][5] = TileType.ROCK
	tile_grid[7][10] = TileType.ROCK
	tile_grid[10][15] = TileType.ROCK
	tile_grid[12][8] = TileType.ROCK
	
	# Create initial empty tunnel pocket where worm starts (around position 500, 288)
	# That's roughly grid position (15, 9)
	var start_x: int = 15
	var start_y: int = 9
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = start_x + dx
			var y: int = start_y + dy
			if x >= 0 and x < WORLD_WIDTH and y >= 0 and y < WORLD_HEIGHT:
				tile_grid[y][x] = TileType.EMPTY

func _draw() -> void:
	# Draw all tiles
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var tile_type: int = tile_grid[y][x]
			var tile_color: Color = tile_colors.get(tile_type, Color.WHITE)
			var rect_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), tile_color)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), border_color, false, 1.0)

# World query API
func world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / TILE_SIZE), int(world_position.y / TILE_SIZE))

func grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * TILE_SIZE, grid_position.y * TILE_SIZE)

func is_in_bounds(grid_position: Vector2i) -> bool:
	return grid_position.x >= 0 and grid_position.x < WORLD_WIDTH and grid_position.y >= 0 and grid_position.y < WORLD_HEIGHT

func get_tile_type(grid_position: Vector2i) -> int:
	if not is_in_bounds(grid_position):
		return TileType.AIR
	return tile_grid[grid_position.y][grid_position.x]

func is_passable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	match tile_type:
		TileType.EMPTY, TileType.AIR:
			return true
		TileType.DIRT, TileType.SURFACE, TileType.ROCK:
			return false
		_:
			return false

func is_edible(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.DIRT or tile_type == TileType.SURFACE

func try_eat_tile(grid_position: Vector2i) -> Dictionary:
	if not is_in_bounds(grid_position):
		return {"success": false, "message": "Out of bounds.", "tile_type": TileType.AIR, "hunger_restore": 0}
	
	var tile_type: int = get_tile_type(grid_position)
	
	match tile_type:
		TileType.EMPTY:
			return {"success": false, "message": "Nothing to eat.", "tile_type": tile_type, "hunger_restore": 0}
		TileType.AIR:
			return {"success": false, "message": "Nothing to eat.", "tile_type": tile_type, "hunger_restore": 0}
		TileType.ROCK:
			return {"success": false, "message": "Too hard to eat.", "tile_type": tile_type, "hunger_restore": 0}
		TileType.DIRT, TileType.SURFACE:
			# Eat the tile - it stays cleared
			tile_grid[grid_position.y][grid_position.x] = TileType.EMPTY
			
			return {"success": true, "message": "Ate dirt.", "tile_type": tile_type, "hunger_restore": 20}
		_:
			return {"success": false, "message": "Cannot eat.", "tile_type": tile_type, "hunger_restore": 0}

# Regrowth disabled - cleared tiles remain cleared
# func _update_regrowth_timers(delta: float) -> void:
# 	Cleared soil stays cleared in current implementation

func get_tile_type_name(tile_type: int) -> String:
	match tile_type:
		TileType.AIR:
			return "AIR"
		TileType.SURFACE:
			return "SURFACE"
		TileType.DIRT:
			return "DIRT"
		TileType.EMPTY:
			return "EMPTY"
		TileType.ROCK:
			return "ROCK"
		_:
			return "UNKNOWN"
