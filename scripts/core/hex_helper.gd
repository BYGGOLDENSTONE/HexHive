class_name HexHelper
## Static utility class for hexagonal grid math.
## Uses axial coordinates (q, r) with pointy-top orientation.
## Reference: https://www.redblobgames.com/grids/hexagons/


# -- Constants --

## Axial direction vectors for pointy-top hex (6 neighbors)
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),   # East
	Vector2i(1, -1),  # NorthEast
	Vector2i(0, -1),  # NorthWest
	Vector2i(-1, 0),  # West
	Vector2i(-1, 1),  # SouthWest
	Vector2i(0, 1),   # SouthEast
]

## Inner slot offsets for the 7 flat-top positions within a tile.
## Index 0 = center, 1-6 = surrounding slots.
## These are normalized offsets (multiply by slot_radius to get pixel offset from tile center).
const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),                    # Center
	Vector2(0.0, -1.0),                   # Top
	Vector2(0.866, -0.5),                 # TopRight (sqrt(3)/2)
	Vector2(0.866, 0.5),                  # BottomRight
	Vector2(0.0, 1.0),                    # Bottom
	Vector2(-0.866, 0.5),                 # BottomLeft
	Vector2(-0.866, -0.5),               # TopLeft
]


# -- Coordinate Conversions --

## Convert axial hex coordinate to pixel position (pointy-top).
static func axial_to_pixel(hex: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * (sqrt(3.0) * hex.x + sqrt(3.0) / 2.0 * hex.y)
	var y: float = hex_size * (3.0 / 2.0 * hex.y)
	return Vector2(x, y)


## Convert pixel position to fractional axial coordinate (pointy-top).
static func pixel_to_axial(pixel: Vector2, hex_size: float) -> Vector2:
	var q: float = (sqrt(3.0) / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / hex_size
	var r: float = (2.0 / 3.0 * pixel.y) / hex_size
	return Vector2(q, r)


## Round fractional axial coordinate to nearest hex.
static func axial_round(frac: Vector2) -> Vector2i:
	var s: float = -frac.x - frac.y
	var q_round: int = roundi(frac.x)
	var r_round: int = roundi(frac.y)
	var s_round: int = roundi(s)

	var q_diff: float = absf(q_round - frac.x)
	var r_diff: float = absf(r_round - frac.y)
	var s_diff: float = absf(s_round - s)

	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round
	# else: s_round would be corrected, but we don't store s

	return Vector2i(q_round, r_round)


## Convert pixel position to the nearest hex coordinate.
static func pixel_to_hex(pixel: Vector2, hex_size: float) -> Vector2i:
	return axial_round(pixel_to_axial(pixel, hex_size))


# -- Neighbors & Distance --

## Get the 6 neighbor coordinates of a hex.
static func get_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir in DIRECTIONS:
		neighbors.append(hex + dir)
	return neighbors


## Get a specific neighbor by direction index (0-5).
static func get_neighbor(hex: Vector2i, direction: int) -> Vector2i:
	return hex + DIRECTIONS[direction % 6]


## Calculate the hex distance between two hexes.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var diff: Vector2i = a - b
	@warning_ignore("integer_division")
	return (absi(diff.x) + absi(diff.x + diff.y) + absi(diff.y)) / 2


## Get all hexes within a given range (inclusive).
static func get_hexes_in_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r1: int = maxi(-radius, -q - radius)
		var r2: int = mini(radius, -q + radius)
		for r in range(r1, r2 + 1):
			results.append(center + Vector2i(q, r))
	return results


## Get all hexes on a ring at exact distance from center.
static func get_hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]

	var results: Array[Vector2i] = []
	var current: Vector2i = center + DIRECTIONS[4] * radius  # Start at SW * radius

	for i in range(6):
		for _j in range(radius):
			results.append(current)
			current = current + DIRECTIONS[i]

	return results


# -- Line Drawing --

## Get all hexes on a line between two hexes (inclusive).
static func get_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n: int = distance(a, b)
	if n == 0:
		return [a]

	var results: Array[Vector2i] = []
	var a_pixel: Vector2 = Vector2(a)
	var b_pixel: Vector2 = Vector2(b)

	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var lerped: Vector2 = a_pixel.lerp(b_pixel, t)
		# Nudge slightly to avoid edge cases on hex boundaries
		var nudged: Vector2 = lerped + Vector2(1e-6, 2e-6)
		results.append(axial_round(nudged))

	return results


# -- Slot Positions --

## Get pixel positions of all 7 inner slots for a given hex.
## slot_radius controls how far the outer slots are from tile center.
static func get_slot_positions(hex: Vector2i, hex_size: float, slot_radius: float) -> Array[Vector2]:
	var center: Vector2 = axial_to_pixel(hex, hex_size)
	var positions: Array[Vector2] = []
	for offset in SLOT_OFFSETS:
		positions.append(center + offset * slot_radius)
	return positions


## Get pixel position of a specific slot (0 = center, 1-6 = ring).
static func get_slot_position(hex: Vector2i, hex_size: float, slot_radius: float, slot_index: int) -> Vector2:
	var center: Vector2 = axial_to_pixel(hex, hex_size)
	return center + SLOT_OFFSETS[slot_index % 7] * slot_radius


# -- Hex Geometry (for drawing) --

## Get the 6 corner points of a pointy-top hex in pixel space.
static func get_hex_corners(center: Vector2, hex_size: float) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var angle_deg: float = 60.0 * i - 30.0  # Pointy-top starts at -30°
		var angle_rad: float = deg_to_rad(angle_deg)
		corners.append(center + Vector2(cos(angle_rad), sin(angle_rad)) * hex_size)
	return corners


## Get the 6 corner points of a flat-top hex in pixel space (for inner slots).
static func get_flat_hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var angle_deg: float = 60.0 * i  # Flat-top starts at 0°
		var angle_rad: float = deg_to_rad(angle_deg)
		corners.append(center + Vector2(cos(angle_rad), sin(angle_rad)) * size)
	return corners
