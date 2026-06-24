class_name TestDirtWorld
extends Node2D

const TILE_SIZE: int = 32
const WORLD_WIDTH: int = 32
const WORLD_HEIGHT: int = 18
const REGROWTH_TIME: float = 20.0

# Grid of dirt tiles: true = has dirt, false = empty
var dirt_grid: Array = []

# Track regrowth timers: position -> remaining time
var regrowth_timers: Dictionary = {}

func _ready() -> void:
	_initialize_dirt_grid()
	_create_visual_representation()

func _process(delta: float) -> void:
	_update_regrowth_timers(delta)
	queue_redraw()

func _initialize_dirt_grid() -> void:
	# Create a 2D array to represent dirt tiles
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			row.append(true)  # All tiles start with dirt
		dirt_grid.append(row)

func _create_visual_representation() -> void:
	# Placeholder - drawing will happen in _draw()
	pass

func _draw() -> void:
	# Draw all tiles
	var dirt_color: Color = Color.html("#8B6914")
	var empty_color: Color = Color.html("#2C1810")
	var border_color: Color = Color.html("#6B4910")
	
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var tile_color: Color = dirt_color if dirt_grid[y][x] else empty_color
			var rect_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), tile_color)
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE)), border_color, false, 1.0)

func eat_dirt_at(world_position: Vector2) -> bool:
	# Convert world position to grid coordinates
	var grid_x: int = int(world_position.x / TILE_SIZE)
	var grid_y: int = int(world_position.y / TILE_SIZE)
	
	# Bounds check
	if grid_x < 0 or grid_x >= WORLD_WIDTH or grid_y < 0 or grid_y >= WORLD_HEIGHT:
		return false
	
	# Check if dirt exists
	if not dirt_grid[grid_y][grid_x]:
		return false
	
	# Remove dirt
	dirt_grid[grid_y][grid_x] = false
	_update_tile_visual(grid_x, grid_y)
	
	# Start regrowth timer
	regrowth_timers[Vector2i(grid_x, grid_y)] = REGROWTH_TIME
	
	return true

func _update_tile_visual(grid_x: int, grid_y: int) -> void:
	var tile_name: String = "Tile_%d_%d" % [grid_x, grid_y]
	var colored_rect: ColorRect = get_node_or_null(tile_name)
	
	if colored_rect:
		if dirt_grid[grid_y][grid_x]:
			colored_rect.color = Color.html("#8B6914")  # Brown dirt
		else:
			colored_rect.color = Color.html("#2C1810")  # Dark empty

func _update_regrowth_timers(delta: float) -> void:
	var positions_to_remove: Array[Vector2i] = []
	
	for pos in regrowth_timers:
		regrowth_timers[pos] -= delta
		
		if regrowth_timers[pos] <= 0.0:
			# Regrow dirt
			dirt_grid[pos.y][pos.x] = true
			_update_tile_visual(pos.x, pos.y)
			positions_to_remove.append(pos)
	
	# Remove completed timers
	for pos in positions_to_remove:
		regrowth_timers.erase(pos)

func get_world_bounds() -> Rect2:
	return Rect2(0, 0, WORLD_WIDTH * TILE_SIZE, WORLD_HEIGHT * TILE_SIZE)
