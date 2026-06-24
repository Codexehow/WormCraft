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

const TILE_SIZE: int = 16
const WORLD_WIDTH: int = 96
const WORLD_HEIGHT: int = 54

# Grid of tile types
var tile_grid: Array = []

# Tile durability tracking for partially dug tiles
# tile_durability[Vector2i] = remaining durability
var tile_durability: Dictionary = {}

# Durability values for diggable tiles
const DIRT_MAX_DURABILITY: int = 8
const SURFACE_MAX_DURABILITY: int = 8

# Resource output when tiles are cleared
const DIRT_PILE_PER_DIRT_TILE: int = 5
const DIRT_PILE_PER_SURFACE_TILE: int = 3

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
	# Rows 0-9: AIR (increased to account for larger world)
	for y in range(10):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.AIR
	
	# Row 10: SURFACE
	for x in range(WORLD_WIDTH):
		tile_grid[10][x] = TileType.SURFACE
	
	# Rows 11-53: Mostly DIRT with some rocks and empty tunnel pocket
	for y in range(11, WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			tile_grid[y][x] = TileType.DIRT
	
	# Add rocks at strategic locations (spaced out across larger world)
	tile_grid[15][20] = TileType.ROCK
	tile_grid[15][50] = TileType.ROCK
	tile_grid[25][30] = TileType.ROCK
	tile_grid[35][15] = TileType.ROCK
	tile_grid[40][60] = TileType.ROCK
	
	# Create initial empty tunnel pocket where worm starts
	# Scale worm start position to new world size
	var start_x: int = 48
	var start_y: int = 20
	for dy in range(-2, 3):
		for dx in range(-2, 3):
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

func try_dig_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Attempt to dig a tile. Returns durability status and resource output.
	"""
	if not is_in_bounds(grid_position):
		return {
			"success": false,
			"cleared": false,
			"message": "Out of bounds.",
			"tile_type": TileType.AIR,
			"resource_id": "",
			"resource_amount": 0,
			"dig_progress": 0,
			"dig_required": 0
		}
	
	var tile_type: int = get_tile_type(grid_position)
	var current_durability: int = tile_durability.get(grid_position, 0)
	
	match tile_type:
		TileType.EMPTY:
			return {
				"success": false,
				"cleared": false,
				"message": "Nothing to dig.",
				"tile_type": tile_type,
				"resource_id": "",
				"resource_amount": 0,
				"dig_progress": 0,
				"dig_required": 0
			}
		TileType.AIR:
			return {
				"success": false,
				"cleared": false,
				"message": "Nothing to dig.",
				"tile_type": tile_type,
				"resource_id": "",
				"resource_amount": 0,
				"dig_progress": 0,
				"dig_required": 0
			}
		TileType.ROCK:
			return {
				"success": false,
				"cleared": false,
				"message": "Rock is too hard to dig.",
				"tile_type": tile_type,
				"resource_id": "",
				"resource_amount": 0,
				"dig_progress": 0,
				"dig_required": 0
			}
		TileType.DIRT:
			# First dig of this tile - initialize durability
			if current_durability == 0:
				current_durability = DIRT_MAX_DURABILITY
			
			# Apply one dig action
			current_durability -= 1
			tile_durability[grid_position] = current_durability
			
			# Check if tile is fully cleared
			if current_durability <= 0:
				# Tile is cleared
				tile_grid[grid_position.y][grid_position.x] = TileType.EMPTY
				tile_durability.erase(grid_position)
				
				return {
					"success": true,
					"cleared": true,
					"message": "Cleared dirt tile!",
					"tile_type": tile_type,
					"resource_id": "dirt_pile",
					"resource_amount": DIRT_PILE_PER_DIRT_TILE,
					"dig_progress": DIRT_MAX_DURABILITY,
					"dig_required": DIRT_MAX_DURABILITY
				}
			else:
				# Tile is partially dug
				return {
					"success": true,
					"cleared": false,
					"message": "Digging dirt: %d / %d" % [DIRT_MAX_DURABILITY - current_durability, DIRT_MAX_DURABILITY],
					"tile_type": tile_type,
					"resource_id": "",
					"resource_amount": 0,
					"dig_progress": DIRT_MAX_DURABILITY - current_durability,
					"dig_required": DIRT_MAX_DURABILITY
				}
		
		TileType.SURFACE:
			# First dig of this tile - initialize durability
			if current_durability == 0:
				current_durability = SURFACE_MAX_DURABILITY
			
			# Apply one dig action
			current_durability -= 1
			tile_durability[grid_position] = current_durability
			
			# Check if tile is fully cleared
			if current_durability <= 0:
				# Tile is cleared
				tile_grid[grid_position.y][grid_position.x] = TileType.EMPTY
				tile_durability.erase(grid_position)
				
				return {
					"success": true,
					"cleared": true,
					"message": "Cleared surface tile!",
					"tile_type": tile_type,
					"resource_id": "dirt_pile",
					"resource_amount": DIRT_PILE_PER_SURFACE_TILE,
					"dig_progress": SURFACE_MAX_DURABILITY,
					"dig_required": SURFACE_MAX_DURABILITY
				}
			else:
				# Tile is partially dug
				return {
					"success": true,
					"cleared": false,
					"message": "Digging surface: %d / %d" % [SURFACE_MAX_DURABILITY - current_durability, SURFACE_MAX_DURABILITY],
					"tile_type": tile_type,
					"resource_id": "",
					"resource_amount": 0,
					"dig_progress": SURFACE_MAX_DURABILITY - current_durability,
					"dig_required": SURFACE_MAX_DURABILITY
				}
		
		_:
			return {
				"success": false,
				"cleared": false,
				"message": "Cannot dig.",
				"tile_type": tile_type,
				"resource_id": "",
				"resource_amount": 0,
				"dig_progress": 0,
				"dig_required": 0
			}

func try_eat_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Legacy function - kept for compatibility. Delegates to try_dig_tile.
	"""
	return try_dig_tile(grid_position)

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
