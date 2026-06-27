class_name LayeredTestWorld
extends Node2D

## Tile type enum
enum TileType {
	AIR,
	SURFACE,
	DIRT,
	EMPTY,
	ROCK,
	PLACED_DIRT
}

const TILE_SIZE: int = 32

const WORLD_WIDTH: int = 96
const WORLD_HEIGHT: int = 54

# Grid of tile types
var tile_grid: Array = []

# Array of dirt texture variants for visual variety
var dirt_textures: Array[Texture2D] = []
# Per-cell stable variant index cache (deterministic, not randomized)
var dirt_variant_by_cell: Dictionary = {}

# Single texture for placed dirt (player-placed tiles)
var placed_dirt_texture: Texture2D = null

# Empty tunnel texture for dug-out underground spaces
var empty_tunnel_texture: Texture2D = null

# Spider silk texture for surface-adjacent prop
var spider_silk_texture: Texture2D = null

# Tile durability tracking for partially dug tiles
# tile_durability[Vector2i] = remaining durability
var tile_durability: Dictionary = {}

# Workshop set-dressing props (non-interactive, visual only)
var workshop_props: Array[Dictionary] = []

# World props — non-interactive visual objects layered on top of terrain
# Each entry: { "id": String, "type": String, "grid_pos": Vector2i, "size_tiles": Vector2i }
var world_props: Array[Dictionary] = []

# Reference to the player for target preview drawing
var worm_player: WormPlayer = null

# Target preview toggle state (default: off for clean-screen feel)
var show_target_preview: bool = false
var _raw_target_preview_key_was_down: bool = false

# (removed: dirt uses a single atlas tile now)

# Starter spawn position — must be EMPTY with solid tile below
const START_GRID_POS: Vector2i = Vector2i(48, 23)

# Durability values for diggable tiles
const DIRT_MAX_DURABILITY: int = 24
const SURFACE_MAX_DURABILITY: int = 24
const PLACED_DIRT_MAX_DURABILITY: int = 4

# Target preview colors
const DIG_VALID_COLOR := Color(1.0, 0.75, 0.15, 0.95)
const PLACE_VALID_COLOR := Color(0.2, 0.8, 1.0, 0.95)
const INVALID_TARGET_COLOR := Color(1.0, 0.15, 0.15, 0.85)

# Resource output when tiles are cleared
const DIRT_PILE_PER_DIRT_TILE: int = 5
const DIRT_PILE_PER_SURFACE_TILE: int = 3
const DIRT_PILE_PER_PLACED_DIRT_TILE: int = 1

# Cleared tiles remain cleared - no automatic regrowth in early development
# Future ecology/weather systems may reclaim tunnels, but cleared soil remains cleared during core gameplay.

# Visual colors for each tile type
var tile_colors: Dictionary = {
	TileType.AIR: Color.html("#1a1a2e"),          # Dark blue/black
	TileType.SURFACE: Color.html("#2d5016"),      # Green/brown surface
	TileType.DIRT: Color.html("#8B6914"),         # Brown dirt
	TileType.EMPTY: Color.html("#2C1810"),        # Dark empty
	TileType.ROCK: Color.html("#808080"),         # Gray rock
	TileType.PLACED_DIRT: Color.html("#A67C2D")   # Looser/player-placed dirt
}

var border_color: Color = Color.html("#6B4910")

func _ready() -> void:
	_initialize_layered_world()
	_load_dirt_textures()
	_load_placed_dirt_texture()
	_load_empty_tunnel_texture()
	_load_spider_silk_texture()
	_initialize_workshop_props()
	_initialize_world_props()

	# Find the player for target preview
	worm_player = get_tree().root.find_child("WormPlayer", true, false)

	queue_redraw()

func _load_dirt_textures() -> void:
	"""Load all dirt texture variants for visual variety in rendering."""
	dirt_textures.clear()
	dirt_variant_by_cell.clear()

	var paths: Array[String] = [
		"res://assets/tiles/dirt.png",
		"res://assets/tiles/dirt2.png",
		"res://assets/tiles/dirt3.png"
	]

	for path in paths:
		var texture: Texture2D = load(path)
		if texture:
			dirt_textures.append(texture)
		else:
			push_warning("Missing dirt texture: " + path)


func _load_placed_dirt_texture() -> void:
	"""Load placed_dirt.png texture with size validation."""
	var texture: Texture2D = load("res://assets/tiles/placed_dirt.png")
	if texture and texture.get_width() == TILE_SIZE and texture.get_height() == TILE_SIZE:
		placed_dirt_texture = texture
	else:
		push_warning("placed_dirt.png missing or wrong size. Falling back to debug color.")
		placed_dirt_texture = null


func _load_empty_tunnel_texture() -> void:
	"""Load empty_tunnel.png texture for dug-out underground spaces."""
	var texture: Texture2D = load("res://assets/tiles/empty_tunnel.png")
	if texture and texture.get_width() == TILE_SIZE and texture.get_height() == TILE_SIZE:
		empty_tunnel_texture = texture
	else:
		push_warning("empty_tunnel.png missing or wrong size. Falling back to debug color.")
		empty_tunnel_texture = null


func _load_spider_silk_texture() -> void:
	"""Load silk.png texture for the spider silk world prop."""
	var texture: Texture2D = load("res://assets/tiles/silk.png")
	if texture and texture.get_width() == TILE_SIZE * 3 and texture.get_height() == TILE_SIZE:
		spider_silk_texture = texture
	else:
		push_warning("silk.png missing or wrong size (expected 96x32). Falling back to placeholder.")
		spider_silk_texture = null


func _initialize_workshop_props() -> void:
	"""Place non-interactive visual props in and near the starting pocket."""
	workshop_props = [
		{
			"id": "dead_machine",
			"grid_pos": Vector2i(46, 19),
		},
		{
			"id": "wall_hooks",
			"grid_pos": Vector2i(50, 18),
		},
		{
			"id": "child_relic",
			"grid_pos": Vector2i(44, 23),
		},
		{
			"id": "quantum_folder_anchor",
			"grid_pos": Vector2i(48, 22),
		},
		{
			"id": "broken_satchel",
			"grid_pos": Vector2i(52, 19),
		},
	]


func _initialize_world_props() -> void:
	"""Initialize non-interactive world props layered on top of terrain."""
	world_props = [
		{
			"id": "spider_silk_01",
			"type": "spider_silk",
			"grid_pos": Vector2i(62, 11),
			"size_tiles": Vector2i(3, 1),
			"sampled": false,
		},
	]


func _initialize_expanded_yard() -> void:
	"""
	Add a larger handcrafted yard/test area extending from the starter pocket.
	
	Provides:
	- Rightward expansion from the workshop (wide tunnel at y=20)
	- Staircase upward (worm steps RIGHT+UP at each step)
	- Upper walkway (y=12) leading to a surface-adjacent cavity
	- Spider silk prop in the cavity (y=11)
	- Rock and dirt obstacles for terrain feel
	
	Staircase design:
	  The worm walks right on y=20 until hitting a DIRT wall,
	  then steps up-and-right to the next walkway level (y-1).
	  Each level has a walkway 2+ tiles wide followed by a DIRT step trigger.
	
	Surface
	 y=10  SSSSSSSSSSSSSSSSSSSSSSS  (surface grass)
	 y=11  ..............EEEEEEEE   (cavity + silk)
	 y=12  ..............EEEEEEEE   (upper walkway)
	 y=13  .............D........
	 y=14  ............D.........  (walkway)
	 y=15  ...........D..........  (walkway)
	 y=16  ..........D...........  (walkway)
	 y=17  .........D............  (walkway)
	 y=18  ........D.............  (walkway)
	 y=19  .......D..............  (walkway)
	 y=20  EEEEEEEEEEEEEEE       (right tunnel)
			  (E=empty, D=dirt step-wall, .=untouched dirt)
	"""
	var cavity_x := 62  # Spider silk cavity center x
	var tunnel_end := 68  # Rightward tunnel end x
	
	# --- Remove the old rock blockage at x=57 ---
	tile_grid[19][57] = TileType.EMPTY
	tile_grid[20][57] = TileType.EMPTY
	
	# --- Rightward expansion from the workshop (y=20) ---
	_carve_h_tunnel(20, 57, tunnel_end)
	
	# --- Rightward+upward staircase (always stepping RIGHT) ---
	# Each step n (0..6): walk right on walkway at y=20-n from x=52+n to x=56+n
	#                      then bump into DIRT at (57+n, 20-n), step to (57+n, 19-n)
	#                      next walkway is at y-1
	#
	# Conditions checked per step:
	#   target_same_level = (57+n, 20-n) = DIRT
	#   step_target        = (57+n, 19-n) = EMPTY
	#   above_current      = (56+n, 19-n) = EMPTY
	#   below_current      = (56+n, 21-n) = DIRT (original world below)
	
	for step_n in range(7):
		var walkway_y: int = 20 - step_n
		var trigger_x: int = 57 + step_n
		
		# Walkway: worm walks right on this level
		_carve_h_tunnel(walkway_y, 52 + step_n, 56 + step_n)
		
		# Step trigger wall (DIRT) — worm bumps into this
		tile_grid[walkway_y][trigger_x] = TileType.DIRT
		
		# Step destination (EMPTY) — worm lands here
		tile_grid[walkway_y - 1][trigger_x] = TileType.EMPTY
		
		# Headroom above worm's current position (EMPTY)
		tile_grid[walkway_y - 1][trigger_x - 1] = TileType.EMPTY
	
	# After step 6, worm arrives at (63, 13).
	# Final walkway at y=13 going left (but worm is pressing RIGHT, so we need
	# another step-right trigger)
	
	# Step 7: from (63,13) → bump (64,13)=DIRT → step to (64,12)
	tile_grid[13][64] = TileType.DIRT
	tile_grid[12][64] = TileType.EMPTY
	tile_grid[12][63] = TileType.EMPTY
	
	# Upper walkway at y=12 from x=52 to x=64
	_carve_h_tunnel(12, 52, 64)
	
	# Surface-adjacent cavity at y=11 for spider silk
	_carve_h_tunnel(11, cavity_x, cavity_x + 2)
	
	# Ensure solid floor below the cavity
	for x in range(cavity_x, cavity_x + 3):
		tile_grid[13][x] = TileType.DIRT
	
	# Solid wall right of the cavity
	tile_grid[12][cavity_x + 3] = TileType.DIRT
	tile_grid[11][cavity_x + 3] = TileType.DIRT
	
	# Rock obstacle on upper walkway
	tile_grid[12][58] = TileType.ROCK
	
	# Tunnel rock for visual variety
	tile_grid[19][63] = TileType.ROCK
	tile_grid[20][65] = TileType.DIRT
	
	# Small drop at the far right of the tunnel
	tile_grid[21][tunnel_end] = TileType.EMPTY
	tile_grid[22][tunnel_end] = TileType.EMPTY
	tile_grid[23][tunnel_end] = TileType.DIRT  # Landing


func _get_dirt_texture_for_cell(grid_position: Vector2i) -> Texture2D:
	"""Return a stable, deterministic dirt texture variant for the given grid cell."""
	if dirt_textures.is_empty():
		return null

	if not dirt_variant_by_cell.has(grid_position):
		# Stable deterministic variation using prime number hashing.
		# Do NOT use randi() — the result must be reproducible per cell.
		var index: int = abs((grid_position.x * 73856093) ^ (grid_position.y * 19349663)) % dirt_textures.size()
		dirt_variant_by_cell[grid_position] = index

	return dirt_textures[dirt_variant_by_cell[grid_position]]


func _process(_delta: float) -> void:
	# Toggle target preview with Q key (edge-triggered, raw fallback)
	var raw_q_down: bool = Input.is_key_pressed(KEY_Q)
	if raw_q_down and not _raw_target_preview_key_was_down:
		show_target_preview = not show_target_preview
		print("Target preview enabled." if show_target_preview else "Target preview disabled.")
		queue_redraw()
	_raw_target_preview_key_was_down = raw_q_down

	# Redraw each frame so target preview follows player movement and facing changes
	queue_redraw()

func _initialize_layered_world() -> void:
	# Create empty 2D grid
	for y in range(WORLD_HEIGHT):
		var row: Array = []
		for x in range(WORLD_WIDTH):
			row.append(TileType.DIRT)
		tile_grid.append(row)
	
	# Create layered world structure
	# Rows 0-9: AIR
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
	
	# Add rocks at strategic locations
	tile_grid[15][20] = TileType.ROCK
	tile_grid[15][50] = TileType.ROCK
	tile_grid[25][30] = TileType.ROCK
	tile_grid[35][15] = TileType.ROCK
	tile_grid[40][60] = TileType.ROCK
	
	# Create organic starting pocket and handcrafted starter layout
	_initialize_starter_layout()

func _initialize_starter_layout() -> void:
	"""Replace the old debug square pocket with an organic handcrafted starter burrow."""
	var start_pos := Vector2i(48, 20)

	# Main organic workshop pocket (oval, wider than tall)
	_carve_oval_pocket(start_pos, 5, 3)

	# Short left tunnel
	_carve_h_tunnel(20, 41, 45)

	# Short right tunnel
	_carve_h_tunnel(20, 51, 56)

	# Small downward nook (lower workshop area)
	_carve_v_tunnel(45, 20, 23)
	_carve_oval_pocket(Vector2i(45, 24), 2, 1)

	# Upward tunnel stub — hints at surface but does NOT reach it
	_carve_v_tunnel(52, 17, 20)

	# Rock blockage — suggests the worm tried to dig further right but hit hard rock
	tile_grid[20][57] = TileType.ROCK
	tile_grid[19][57] = TileType.ROCK

	# Ensure spawn tile is EMPTY and tile below is solid for safe spawn
	tile_grid[START_GRID_POS.y][START_GRID_POS.x] = TileType.EMPTY
	if is_in_bounds(Vector2i(START_GRID_POS.x, START_GRID_POS.y + 1)):
		tile_grid[START_GRID_POS.y + 1][START_GRID_POS.x] = TileType.DIRT

	# Plug the bottom of the vertical tunnel at x=45 so the worm can walk
	# across y=22 level without falling into the small oval below.
	# The tunnel remains 2 tiles deep (y=20 to y=22) for visual interest.
	tile_grid[23][45] = TileType.DIRT

	# Add fall test geometry to the left of the pocket
	_carve_fall_test_geometry()

	# Add larger handcrafted yard/test area to the right and upward
	_initialize_expanded_yard()


func _carve_fall_test_geometry() -> void:
	"""
	Carve three reachable test drops along a walkway at y=22.
	
	Key insight: the worm moves at 60px/s while falling, so each drop must be
	multiple tiles wide to prevent the worm from sliding sideways off the
	drop column before completing the full fall distance.
	
	Layout (right to left):
	  x=45-43: solid walkway (into pocket)
	  x=42-41: 1-tile drop (2 tiles wide)
	  x=40-39: solid recovery walkway
	  x=38-37: 2-tile drop (2 tiles wide)
	  x=36-35: solid recovery walkway
	  x=34-33: 3-tile drop (2 tiles wide)
	  x=32-30: recovery ramp back to walkway
	"""
	# Horizontal walkway at y=22
	_carve_h_tunnel(22, 30, 44)

	# --- 1-tile drop (2 tiles wide: x=42,41) ---
	# Fall from y=22 through y=23, land on DIRT at y=24
	tile_grid[23][42] = TileType.EMPTY
	tile_grid[23][41] = TileType.EMPTY
	tile_grid[24][42] = TileType.DIRT
	tile_grid[24][41] = TileType.DIRT

	# Recovery: worm at y=23, step LEFT -> (40,23)=DIRT -> step-up to (40,22)

	# --- 2-tile drop (2 tiles wide: x=38,37) ---
	# Fall from y=22 through y=23,24, land on DIRT at y=25
	tile_grid[23][38] = TileType.EMPTY
	tile_grid[23][37] = TileType.EMPTY
	tile_grid[24][38] = TileType.EMPTY
	tile_grid[24][37] = TileType.EMPTY
	tile_grid[25][38] = TileType.DIRT
	tile_grid[25][37] = TileType.DIRT

	# Recovery from 2-tile: worm at y=24, step LEFT -> (36,24)=DIRT -> step-up
	# above=(37 or 38, 23)=EMPTY, step=(36,23), below=(37 or 38,25)=DIRT
	# Carve (36,23)=EMPTY, (36,24)=DIRT for step-up, creating a 1-tile drop at x=36
	tile_grid[23][36] = TileType.EMPTY
	tile_grid[24][36] = TileType.DIRT
	# Worm steps up to (36,23), then walks LEFT: (35,23)=DIRT -> step-up to (35,22)
	# (35,23) stays DIRT, step=(35,22)=walkway

	# --- 3-tile drop (2 tiles wide: x=34,33) ---
	# Fall from y=22 through y=23,24,25, land on DIRT at y=26
	tile_grid[23][34] = TileType.EMPTY
	tile_grid[23][33] = TileType.EMPTY
	tile_grid[24][34] = TileType.EMPTY
	tile_grid[24][33] = TileType.EMPTY
	tile_grid[25][34] = TileType.EMPTY
	tile_grid[25][33] = TileType.EMPTY
	tile_grid[26][34] = TileType.DIRT
	tile_grid[26][33] = TileType.DIRT

	# Recovery from 3-tile: worm at y=25, step LEFT -> (32,25)=DIRT -> step-up
	# above=(33 or 34, 24)=EMPTY, step=(32,24), below=(33 or 34,26)=DIRT
	tile_grid[24][32] = TileType.EMPTY
	tile_grid[25][32] = TileType.DIRT
	# Worm at (32,24): step LEFT -> (31,24)=DIRT -> step-up
	# above=(32,23), step=(31,23), below=(32,25)=DIRT
	tile_grid[23][32] = TileType.EMPTY
	tile_grid[23][31] = TileType.EMPTY
	tile_grid[24][31] = TileType.DIRT
	# Worm at (31,23): step LEFT -> (30,23)=DIRT -> step-up
	# above=(31,22)=walkway, step=(30,22)=walkway, below=(31,24)=DIRT
	# Back on walkway at (30,22)


func _carve_oval_pocket(center: Vector2i, radius_x: int, radius_y: int) -> void:
	"""Carve an elliptical empty pocket into the tile grid."""
	for y in range(center.y - radius_y, center.y + radius_y + 1):
		for x in range(center.x - radius_x, center.x + radius_x + 1):
			var pos := Vector2i(x, y)
			if not is_in_bounds(pos):
				continue

			var nx: float = float(x - center.x) / float(radius_x)
			var ny: float = float(y - center.y) / float(radius_y)

			if nx * nx + ny * ny <= 1.0:
				tile_grid[y][x] = TileType.EMPTY


func _carve_h_tunnel(y: int, x1: int, x2: int) -> void:
	"""Carve a horizontal tunnel at a fixed y row between x1 and x2 (inclusive)."""
	var min_x: int = min(x1, x2)
	var max_x: int = max(x1, x2)
	for x in range(min_x, max_x + 1):
		var pos := Vector2i(x, y)
		if is_in_bounds(pos):
			tile_grid[y][x] = TileType.EMPTY


func _carve_v_tunnel(x: int, y1: int, y2: int) -> void:
	"""Carve a vertical tunnel at a fixed x column between y1 and y2 (inclusive)."""
	var min_y: int = min(y1, y2)
	var max_y: int = max(y1, y2)
	for y in range(min_y, max_y + 1):
		var pos := Vector2i(x, y)
		if is_in_bounds(pos):
			tile_grid[y][x] = TileType.EMPTY


func _draw() -> void:
	"""Render all tiles directly from tile_grid — single source of truth."""
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var tile_type: int = tile_grid[y][x]
			var rect_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			var rect: Rect2 = Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE))
			
			if tile_type == TileType.EMPTY and empty_tunnel_texture:
				draw_texture_rect(empty_tunnel_texture, rect, false)
			elif tile_type == TileType.DIRT:
				var dirt_texture: Texture2D = _get_dirt_texture_for_cell(Vector2i(x, y))
				if dirt_texture:
					draw_texture_rect(dirt_texture, rect, false)
				else:
					draw_rect(rect, tile_colors.get(tile_type, Color.WHITE))
			elif tile_type == TileType.PLACED_DIRT and placed_dirt_texture:
				draw_texture_rect(placed_dirt_texture, rect, false)
			else:
				var tile_color: Color = tile_colors.get(tile_type, Color.WHITE)
				draw_rect(rect, tile_color)
			
			# Subtle border for visual clarity
			draw_rect(rect, border_color, false, 1.0)

	# Draw world props (spider silk, etc.) on top of terrain
	_draw_world_props()

	# Draw dig damage overlays over partially-dug tiles
	for damaged_pos: Vector2i in tile_durability.keys():
		if not is_in_bounds(damaged_pos):
			continue
		var tile_type: int = get_tile_type(damaged_pos)
		_draw_dig_damage_overlay(damaged_pos, tile_type)

	# Draw workshop set-dressing props on top of terrain and damage
	_draw_workshop_props()

	# Draw target preview overlays on top of terrain and damage marks (only when toggled on)
	if show_target_preview:
		_draw_target_preview()

# World query API
func world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / TILE_SIZE), int(world_position.y / TILE_SIZE))

func grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * TILE_SIZE, grid_position.y * TILE_SIZE)

func grid_to_world_center(grid_position: Vector2i) -> Vector2:
	return grid_to_world(grid_position) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

func get_start_grid_position() -> Vector2i:
	"""Return the grid position where the worm should spawn."""
	return START_GRID_POS

func get_start_world_position() -> Vector2:
	"""Return the world pixel position (tile center) where the worm should spawn."""
	return grid_to_world_center(get_start_grid_position())

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
		TileType.DIRT, TileType.SURFACE, TileType.ROCK, TileType.PLACED_DIRT:
			return false
		_:
			return false

func is_placeable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.EMPTY or tile_type == TileType.AIR

func is_diggable(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.DIRT or tile_type == TileType.SURFACE or tile_type == TileType.PLACED_DIRT

func is_edible(grid_position: Vector2i) -> bool:
	if not is_in_bounds(grid_position):
		return false
	
	var tile_type: int = get_tile_type(grid_position)
	return tile_type == TileType.DIRT or tile_type == TileType.SURFACE or tile_type == TileType.PLACED_DIRT

func try_place_dirt_tile(grid_position: Vector2i, actor_grid_position: Vector2i) -> Dictionary:
	"""
	Attempt to place loose/player-made dirt at a grid position.
	The world owns placement legality. The player owns inventory cost.
	"""
	if not is_in_bounds(grid_position):
		return {
			"success": false,
			"message": "Cannot place dirt out of bounds.",
			"tile_type": TileType.AIR
		}
	
	if grid_position == actor_grid_position:
		return {
			"success": false,
			"message": "Cannot place dirt inside yourself.",
			"tile_type": get_tile_type(grid_position)
		}
	
	if not is_placeable(grid_position):
		return {
			"success": false,
			"message": "Cannot place dirt there.",
			"tile_type": get_tile_type(grid_position)
		}
	
	tile_grid[grid_position.y][grid_position.x] = TileType.PLACED_DIRT
	tile_durability.erase(grid_position)
	queue_redraw()
	return {
		"success": true,
		"message": "Placed dirt.",
		"tile_type": TileType.PLACED_DIRT
	}

func try_dig_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Attempt to dig a tile. Returns durability status and resource output.
	"""
	if not is_in_bounds(grid_position):
		return _dig_result(false, false, "Out of bounds.", TileType.AIR, "", 0, 0, 0)
	
	var tile_type: int = get_tile_type(grid_position)
	var current_durability: int = tile_durability.get(grid_position, 0)
	
	match tile_type:
		TileType.EMPTY, TileType.AIR:
			return _dig_result(false, false, "Nothing to dig.", tile_type, "", 0, 0, 0)
		TileType.ROCK:
			return _dig_result(false, false, "Rock is too hard to dig.", tile_type, "", 0, 0, 0)
		TileType.DIRT:
			return _dig_solid_tile(grid_position, tile_type, current_durability, DIRT_MAX_DURABILITY, "dirt", DIRT_PILE_PER_DIRT_TILE)
		TileType.SURFACE:
			return _dig_solid_tile(grid_position, tile_type, current_durability, SURFACE_MAX_DURABILITY, "surface", DIRT_PILE_PER_SURFACE_TILE)
		TileType.PLACED_DIRT:
			return _dig_solid_tile(grid_position, tile_type, current_durability, PLACED_DIRT_MAX_DURABILITY, "placed dirt", DIRT_PILE_PER_PLACED_DIRT_TILE)
		_:
			return _dig_result(false, false, "Cannot dig.", tile_type, "", 0, 0, 0)

func _dig_solid_tile(
	grid_position: Vector2i,
	tile_type: int,
	current_durability: int,
	max_durability: int,
	tile_label: String,
	resource_amount: int
) -> Dictionary:
	if current_durability == 0:
		current_durability = max_durability
	
	current_durability -= 1
	tile_durability[grid_position] = current_durability
	
	if current_durability <= 0:
		tile_grid[grid_position.y][grid_position.x] = TileType.EMPTY
		tile_durability.erase(grid_position)
		dirt_variant_by_cell.erase(grid_position)
		queue_redraw()
		return _dig_result(true, true, "Cleared %s tile!" % tile_label, tile_type, "dirt_pile", resource_amount, max_durability, max_durability)
	
	return _dig_result(
		true,
		false,
		"Digging %s: %d / %d" % [tile_label, max_durability - current_durability, max_durability],
		tile_type,
		"",
		0,
		max_durability - current_durability,
		max_durability
	)

func _dig_result(
	success: bool,
	cleared: bool,
	message: String,
	tile_type: int,
	resource_id: String,
	resource_amount: int,
	dig_progress: int,
	dig_required: int
) -> Dictionary:
	return {
		"success": success,
		"cleared": cleared,
		"message": message,
		"tile_type": tile_type,
		"resource_id": resource_id,
		"resource_amount": resource_amount,
		"dig_progress": dig_progress,
		"dig_required": dig_required
	}

func try_eat_tile(grid_position: Vector2i) -> Dictionary:
	"""
	Legacy function - kept for compatibility. Delegates to try_dig_tile.
	"""
	return try_dig_tile(grid_position)

func try_interact_prop_at(grid_pos: Vector2i) -> Dictionary:
	"""
	Attempt to interact with a world prop at the given grid position.
	
	Returns a dictionary with:
	- success: bool
	- prop_type: String (e.g. "spider_silk")
	- message: String
	- resource_id: String
	- resource_amount: int
	- effect_world_pos: Vector2 (world position for particle effects)
	"""
	for prop in world_props:
		var prop_grid_pos: Vector2i = prop["grid_pos"]
		var prop_size: Vector2i = prop.get("size_tiles", Vector2i(1, 1))
		var is_targeting_this_prop: bool = false

		# Check if the given grid position overlaps any tile this prop occupies
		for dx in range(prop_size.x):
			for dy in range(prop_size.y):
				if Vector2i(prop_grid_pos.x + dx, prop_grid_pos.y + dy) == grid_pos:
					is_targeting_this_prop = true
					break
			if is_targeting_this_prop:
				break

		if not is_targeting_this_prop:
			continue

		# Calculate a reasonable effect position (center of the prop)
		var effect_pos: Vector2 = grid_to_world_center(prop_grid_pos) + Vector2(TILE_SIZE * prop_size.x / 2.0, 0.0)

		match prop["type"]:
			"spider_silk":
				if prop.get("sampled", false):
					return {
						"success": false,
						"prop_type": "spider_silk",
						"message": "Spider silk already sampled.",
						"resource_id": "",
						"resource_amount": 0,
						"effect_world_pos": effect_pos,
					}
				else:
					prop["sampled"] = true
					return {
						"success": true,
						"prop_type": "spider_silk",
						"message": "Sampled spider silk.",
						"resource_id": "spider_silk_sample",
						"resource_amount": 1,
						"effect_world_pos": effect_pos,
					}

	# No prop found at this grid position
	return {
		"success": false,
		"prop_type": "",
		"message": "Nothing to inspect.",
		"resource_id": "",
		"resource_amount": 0,
		"effect_world_pos": Vector2.ZERO,
	}


func try_interact_prop_near(center_pos: Vector2i, radius: int = 1) -> Dictionary:
	"""
	Try to interact with a prop near the given center position.
	Checks all tiles within Manhattan distance <= radius of the center_pos.
	
	First checks the exact center position, then expands outward.
	"""
	# First, try the exact position
	var exact_result: Dictionary = try_interact_prop_at(center_pos)
	if exact_result["success"]:
		return exact_result
	
	# Fallback: check nearby positions within Manhattan distance radius
	# Order: try positions closer to center first
	for dist in range(1, radius + 1):
		for dx in range(-dist, dist + 1):
			var dy_remainder: int = dist - abs(dx)
			for dy_sign in [1, -1]:
				var dy: int = dy_remainder * dy_sign
				if dx == 0 and dy == 0:
					continue
				# Skip positions already checked at smaller distances
				if abs(dx) + abs(dy) != dist:
					continue
				var check_pos: Vector2i = Vector2i(center_pos.x + dx, center_pos.y + dy)
				if not is_in_bounds(check_pos):
					continue
				var result: Dictionary = try_interact_prop_at(check_pos)
				if result["success"]:
					return result
	
	# Also check the worm's current position
	var worm_grid_pos: Vector2i = world_to_grid(worm_player.global_position) if worm_player else Vector2i.ZERO
	if worm_grid_pos != center_pos:
		var worm_tile_result: Dictionary = try_interact_prop_at(worm_grid_pos)
		if worm_tile_result["success"]:
			return worm_tile_result
	
	# No prop found anywhere in range — return the exact position result (which will be "Nothing to inspect.")
	return exact_result


func is_near_workshop_prop(grid_pos: Vector2i, prop_id: String, radius: int = 2) -> bool:
	"""Check if the given grid position is within Manhattan distance <= radius of the specified workshop prop."""
	for prop in workshop_props:
		if prop["id"] != prop_id:
			continue
		var prop_grid_pos: Vector2i = prop["grid_pos"]
		var distance: int = abs(grid_pos.x - prop_grid_pos.x) + abs(grid_pos.y - prop_grid_pos.y)
		return distance <= radius
	return false


func _spawn_scan_particles_at(world_pos: Vector2) -> void:
	"""Spawn a short one-shot particle burst at the given world position for scan feedback."""
	var particles := CPUParticles2D.new()
	particles.position = world_pos
	particles.z_as_relative = false
	particles.z_index = 100  # Render above terrain and props

	# Time settings: short burst
	particles.amount = 16
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.3

	# Direction: burst outward in all directions
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 60.0

	# Scale: small motes
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.5

	# Color: pale blue-white
	particles.color = Color(0.85, 0.9, 1.0, 0.9)

	# No gravity
	particles.gravity = Vector2.ZERO

	# Start emitting
	particles.emitting = true
	add_child(particles)

	# Auto-cleanup after particles finish their lifetime
	await get_tree().create_timer(particles.lifetime + 0.3).timeout
	if is_instance_valid(particles):
		particles.queue_free()


# Regrowth disabled - cleared tiles remain cleared.
# func _update_regrowth_timers(delta: float) -> void:
# 	Cleared soil stays cleared in current implementation.

# ---------------------------------------------------------------------------
# Workshop set-dressing props — non-interactive visual-only decorations
# ---------------------------------------------------------------------------

func _draw_world_props() -> void:
	"""Draw world props (spider silk, etc.) on top of terrain using textures."""
	for prop in world_props:
		var grid_pos: Vector2i = prop["grid_pos"]
		var size_tiles: Vector2i = prop.get("size_tiles", Vector2i(1, 1))
		var pixel_pos: Vector2 = grid_to_world(grid_pos)
		var rect: Rect2 = Rect2(pixel_pos, Vector2(TILE_SIZE * size_tiles.x, TILE_SIZE * size_tiles.y))

		match prop["type"]:
			"spider_silk":
				if spider_silk_texture:
					draw_texture_rect(spider_silk_texture, rect, false)
				else:
					# Fallback: semi-transparent white rectangle
					draw_rect(rect, Color(0.9, 0.85, 0.7, 0.4))


# ---------------------------------------------------------------------------

func _draw_workshop_props() -> void:
	"""Draw placeholder shapes for workshop props. These do not affect gameplay."""
	for prop in workshop_props:
		var grid_pos: Vector2i = prop["grid_pos"]
		var rect_pos: Vector2 = grid_to_world(grid_pos)

		match prop["id"]:
			"dead_machine":
				# Muted metal-gray body with a blue-ish display panel
				draw_rect(Rect2(rect_pos + Vector2(4, 8), Vector2(24, 12)), Color.html("#555566"))
				draw_rect(Rect2(rect_pos + Vector2(8, 4), Vector2(8, 8)), Color.html("#88aaff"))
			"wall_hooks":
				# Two pale bone/off-white hooks on the wall
				draw_line(rect_pos + Vector2(6, 6), rect_pos + Vector2(6, 18), Color.html("#ddddaa"), 2.0)
				draw_line(rect_pos + Vector2(16, 6), rect_pos + Vector2(16, 18), Color.html("#ddddaa"), 2.0)
				draw_line(rect_pos + Vector2(24, 6), rect_pos + Vector2(24, 18), Color.html("#ddddaa"), 2.0)
			"child_relic":
				# Bright red plastic-like circle — a relic from the worm's early years
				draw_circle(rect_pos + Vector2(16, 16), 6.0, Color.html("#cc4444"))
				draw_circle(rect_pos + Vector2(16, 16), 4.0, Color.html("#ff6666"))
			"quantum_folder_anchor":
				# Purple/cyan glow — anchor point for the Quantum Space Folder
				draw_rect(Rect2(rect_pos + Vector2(8, 8), Vector2(16, 16)), Color.html("#8844cc"))
				draw_rect(Rect2(rect_pos + Vector2(11, 11), Vector2(10, 10)), Color.html("#66ccff"))
			"broken_satchel":
				# A torn leather-like satchel shape
				draw_rect(Rect2(rect_pos + Vector2(6, 8), Vector2(20, 14)), Color.html("#8B6914"))
				draw_line(rect_pos + Vector2(10, 8), rect_pos + Vector2(10, 4), Color.html("#6B4910"), 2.0)
				draw_line(rect_pos + Vector2(22, 8), rect_pos + Vector2(22, 4), Color.html("#6B4910"), 2.0)


# ---------------------------------------------------------------------------
# Dig damage overlay — procedural crack lines on partially-dug tiles
# ---------------------------------------------------------------------------

func _draw_dig_damage_overlay(grid_position: Vector2i, tile_type: int) -> void:
	"""Draw crack marks proportional to damage taken on a partially-dug tile."""
	if not tile_durability.has(grid_position):
		return

	var max_durability: int
	match tile_type:
		TileType.DIRT:
			max_durability = DIRT_MAX_DURABILITY
		TileType.SURFACE:
			max_durability = SURFACE_MAX_DURABILITY
		TileType.PLACED_DIRT:
			max_durability = PLACED_DIRT_MAX_DURABILITY
		_:
			return

	var remaining_durability: int = tile_durability[grid_position]
	var damage: int = max_durability - remaining_durability
	var damage_ratio: float = float(damage) / float(max_durability)

	var rect_pos: Vector2 = Vector2(grid_position.x * TILE_SIZE, grid_position.y * TILE_SIZE)
	var crack_color: Color = Color(0.08, 0.04, 0.02, 0.95)
	var highlight_color: Color = Color(0.75, 0.45, 0.20, 0.5)

	# Deterministic position jitter per cell so different tiles look different
	var hash_val: int = abs(grid_position.x * 73856093 ^ grid_position.y * 19349663)
	var jitter: int = hash_val % 7

	# Level 1 — single subtle crack (any damage)
	draw_line(
		rect_pos + Vector2(8 + jitter, 10),
		rect_pos + Vector2(14 + jitter, 14),
		crack_color, 2.0
	)

	if damage_ratio >= 0.25:
		# Level 2 — second crack
		draw_line(
			rect_pos + Vector2(18 - jitter, 8),
			rect_pos + Vector2(23 - jitter, 13),
			crack_color, 2.0
		)

	if damage_ratio >= 0.50:
		# Level 3 — third crack
		draw_line(
			rect_pos + Vector2(10, 22 - jitter),
			rect_pos + Vector2(17, 18 - jitter),
			crack_color, 2.0
		)

	if damage_ratio >= 0.75:
		# Level 4 — fourth crack
		draw_line(
			rect_pos + Vector2(22, 22 + jitter),
			rect_pos + Vector2(27, 18 + jitter),
			highlight_color, 2.0
		)

	if damage_ratio >= 0.90:
		# Level 5 — near-breaking highlight crack
		draw_line(
			rect_pos + Vector2(5, 16 + jitter),
			rect_pos + Vector2(12, 16 + jitter),
			highlight_color, 3.0
		)


# ---------------------------------------------------------------------------
# Target preview drawing — procedural outlines over dig/place targets
# ---------------------------------------------------------------------------

func _draw_target_preview() -> void:
	"""Draw outline rectangles over the dig and place target tiles."""
	if not worm_player:
		return

	var dig_pos: Vector2i = worm_player.get_dig_target_grid_pos()
	var place_pos: Vector2i = worm_player.get_place_target_grid_pos()

	_draw_target_rect(dig_pos, _get_dig_preview_color(dig_pos), 3.0)

	if place_pos != dig_pos:
		_draw_target_rect(place_pos, _get_place_preview_color(place_pos), 2.0)
	else:
		# Both targets on the same tile — draw a thinner second outline
		_draw_target_rect(place_pos, _get_place_preview_color(place_pos), 1.0)


func _draw_target_rect(grid_position: Vector2i, color: Color, width: float) -> void:
	"""Draw a single tile-sized rectangle outline at the given grid position."""
	if not is_in_bounds(grid_position):
		return

	var rect_pos: Vector2 = Vector2(grid_position.x * TILE_SIZE, grid_position.y * TILE_SIZE)
	var rect: Rect2 = Rect2(rect_pos, Vector2(TILE_SIZE, TILE_SIZE))
	draw_rect(rect, color, false, width)


func _get_dig_preview_color(grid_position: Vector2i) -> Color:
	"""Return valid dig color if the tile can be dug, otherwise invalid color."""
	if is_in_bounds(grid_position) and is_diggable(grid_position):
		return DIG_VALID_COLOR
	return INVALID_TARGET_COLOR


func _get_place_preview_color(grid_position: Vector2i) -> Color:
	"""Return valid place color if the tile can receive dirt, otherwise invalid color."""
	if is_in_bounds(grid_position) and is_placeable(grid_position):
		return PLACE_VALID_COLOR
	return INVALID_TARGET_COLOR


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
		TileType.PLACED_DIRT:
			return "PLACED_DIRT"
		_:
			return "UNKNOWN"
