extends RefCounted
## Fast procedural city map used by the demo generator.
##
## The whole map is generated in one synchronous pass (no WFC, no awaiting
## between cells). Every cell is stored as a single-character tile name, so
## the result can also be printed as an ASCII map or handed to gameplay code
## that uses one character per tile.
##
## Layout outline:  several overlapping rectangles -> one connected footprint
##                  with a slightly jittered border.
## Road network:    arterial grid (plus a ring road on larger maps), connected
##                  with BFS where the irregular outline would break a road,
##                  then short secondary streets cut through large blocks.
## Districts:       weighted Voronoi (CBD / residential / industrial / park).
## Buildings:       rectangle packing inside each block, guaranteed fill so the
##                  generator can never end with an unusable / empty map.

const VOID := " "
const ROAD := "R"
const LANE := "r"
const RES := "H"
const COM := "C"
const IND := "I"
const PUB := "P"
const PARK := "G"
const PLAZA := "."
const WATER := "W"

const ZONE_RES := 0
const ZONE_COM := 1
const ZONE_IND := 2
const ZONE_PARK := 3

const TILE_DESCRIPTIONS := {
	VOID: "空",
	ROAD: "主干道",
	LANE: "支路",
	RES: "居民楼",
	COM: "商业楼",
	IND: "厂房",
	PUB: "公共设施",
	PARK: "公园绿地",
	PLAZA: "空地",
	WATER: "水面",
}

const POI_NAMES := {
	"hospital": "市立医院",
	"fire": "消防站",
	"police": "警察局",
	"school": "第一中学",
	"city_hall": "市政厅",
}

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var width: int = 24
var height: int = 32
var used_seed: int = 0
var generation_msec: float = 0.0

## Row-major grid of one-character tile names.
var cells := PackedStringArray()
var footprint := PackedByteArray()
var zone_map := PackedByteArray()
var buildings: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var stats: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _bbox := Rect2i()
var _inside_cells: Array[Vector2i] = []
var _zone_seeds: Array[Dictionary] = []
var _has_ring := false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate(p_width: int, p_height: int, p_seed: int = 0) -> void:
	var start_usec := Time.get_ticks_usec()
	width = clampi(p_width, 10, 96)
	height = clampi(p_height, 10, 96)
	used_seed = p_seed if p_seed != 0 else (randi() | 1)
	_rng.seed = used_seed

	cells.resize(width * height)
	cells.fill(VOID)
	footprint.resize(width * height)
	footprint.fill(0)
	zone_map.resize(width * height)
	zone_map.fill(ZONE_RES)
	buildings.clear()
	labels.clear()
	_zone_seeds.clear()
	_has_ring = false
	_inside_cells.clear()

	_build_outline()
	_refresh_inside()
	if _inside_cells.is_empty():
		_fallback_outline()
		_refresh_inside()

	_assign_zones()
	_ensure_min_park()
	_build_roads()
	_ensure_roads()
	_build_secondary_streets()
	_connect_road_components()
	_place_buildings()
	_scatter_pocket_parks()
	_assign_pois()
	_collect_labels()

	generation_msec = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_build_stats()


func is_inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and footprint[y * width + x] == 1


func get_tile(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return VOID
	return cells[y * width + x]


func get_tile_description(tile: String) -> String:
	return TILE_DESCRIPTIONS.get(tile, tile)


func get_map_rect() -> Rect2i:
	return _bbox


func to_ascii() -> String:
	var lines := PackedStringArray()
	for y in height:
		var line := ""
		for x in width:
			line += cells[y * width + x]
		lines.append(line)
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Outline: overlapping rectangles, jittered, largest connected component kept
# ---------------------------------------------------------------------------

func _build_outline() -> void:
	footprint.fill(0)
	var margin_x := maxi(1, int(round(float(width) * 0.08)))
	var margin_y := maxi(1, int(round(float(height) * 0.08)))
	if width - margin_x * 2 < 8:
		margin_x = maxi(0, (width - 8) / 2)
	if height - margin_y * 2 < 8:
		margin_y = maxi(0, (height - 8) / 2)

	var ux0 := margin_x
	var uy0 := margin_y
	var uw := width - margin_x * 2
	var uh := height - margin_y * 2
	if uw < 6 or uh < 6:
		_fallback_outline()
		return

	var core_w := _rng.randi_range(maxi(6, int(uw * 0.68)), maxi(7, int(uw * 0.86)))
	var core_h := _rng.randi_range(maxi(6, int(uh * 0.64)), maxi(7, int(uh * 0.82)))
	core_w = mini(core_w, uw)
	core_h = mini(core_h, uh)
	var core_x := _rng.randi_range(ux0, ux0 + uw - core_w)
	var core_y := _rng.randi_range(uy0, uy0 + uh - core_h)
	var core := Rect2i(core_x, core_y, core_w, core_h)
	var rects: Array[Rect2i] = [core]

	var wing_count := _rng.randi_range(3, 5)
	for i in wing_count:
		for attempt in 10:
			var base: Rect2i = rects[_rng.randi_range(0, rects.size() - 1)]
			var room_left := base.position.x - ux0
			var room_right := (ux0 + uw) - (base.position.x + base.size.x)
			var room_up := base.position.y - uy0
			var room_down := (uy0 + uh) - (base.position.y + base.size.y)
			var directions: Array[int] = []
			if room_left >= 2:
				directions.append(0)
			if room_right >= 2:
				directions.append(1)
			if room_up >= 2:
				directions.append(2)
			if room_down >= 2:
				directions.append(3)
			if directions.is_empty():
				continue
			var direction: int = directions[_rng.randi_range(0, directions.size() - 1)]
			var new_w := _rng.randi_range(maxi(4, int(uw * 0.28)), maxi(5, int(uw * 0.52)))
			var new_h := _rng.randi_range(maxi(4, int(uh * 0.28)), maxi(5, int(uh * 0.52)))
			new_w = mini(new_w, uw)
			new_h = mini(new_h, uh)
			var overlap := _rng.randi_range(2, 4)
			var nx := 0
			var ny := 0
			if direction <= 1:
				# Grow left / right, keep a vertical overlap with the base.
				if new_h <= base.size.y:
					ny = base.position.y + _rng.randi_range(0, base.size.y - new_h)
				else:
					ny = base.position.y + _rng.randi_range(base.size.y - new_h, 0)
				if direction == 1:
					nx = base.position.x + base.size.x - overlap
				else:
					nx = base.position.x - new_w + overlap
			else:
				# Grow up / down, keep a horizontal overlap with the base.
				if new_w <= base.size.x:
					nx = base.position.x + _rng.randi_range(0, base.size.x - new_w)
				else:
					nx = base.position.x + _rng.randi_range(base.size.x - new_w, 0)
				if direction == 3:
					ny = base.position.y + base.size.y - overlap
				else:
					ny = base.position.y - new_h + overlap
			nx = clampi(nx, ux0, ux0 + uw - new_w)
			ny = clampi(ny, uy0, uy0 + uh - new_h)
			var candidate := Rect2i(nx, ny, new_w, new_h)
			if _rect_overlap_area(candidate, base) <= 0:
				continue
			# Require the wing to actually stick out of the base, otherwise it
			# only burns time without making the outline less rectangular.
			var sticks_out := false
			if direction == 1 and candidate.position.x + candidate.size.x > base.position.x + base.size.x + 1:
				sticks_out = true
			elif direction == 0 and candidate.position.x < base.position.x - 1:
				sticks_out = true
			elif direction == 3 and candidate.position.y + candidate.size.y > base.position.y + base.size.y + 1:
				sticks_out = true
			elif direction == 2 and candidate.position.y < base.position.y - 1:
				sticks_out = true
			if not sticks_out:
				continue
			rects.append(candidate)
			break

	for rect in rects:
		var x_end := mini(rect.position.x + rect.size.x, ux0 + uw)
		var y_end := mini(rect.position.y + rect.size.y, uy0 + uh)
		for y in range(maxi(rect.position.y, uy0), y_end):
			for x in range(maxi(rect.position.x, ux0), x_end):
				footprint[y * width + x] = 1

	# Nibble convex corners and fill concave notches. This keeps the shape
	# "several rectangles combined" while avoiding a perfectly rectangular rim.
	for pass_index in 2:
		var to_remove: Array[Vector2i] = []
		var to_add: Array[Vector2i] = []
		for y in range(uy0, uy0 + uh):
			for x in range(ux0, ux0 + uw):
				var n := _inside_neighbor_count(x, y)
				if footprint[y * width + x] == 1:
					if n <= 1:
						to_remove.append(Vector2i(x, y))
					elif n == 2 and _rng.randf() < 0.16:
						to_remove.append(Vector2i(x, y))
					elif n == 3 and _rng.randf() < 0.05:
						to_remove.append(Vector2i(x, y))
				else:
					if n >= 3 and _rng.randf() < 0.16:
						to_add.append(Vector2i(x, y))
		for cell in to_remove:
			footprint[cell.y * width + cell.x] = 0
		for cell in to_add:
			footprint[cell.y * width + cell.x] = 1

	_keep_largest_component()
	_carve_outline_notches()
	_center_outline()


func _count_inside() -> int:
	var count := 0
	for value in footprint:
		count += value
	return count


func _footprint_bbox() -> Rect2i:
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in height:
		for x in width:
			if footprint[y * width + x] == 1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _carve_outline_notches() -> void:
	# A union of rectangles can still end up looking like a plain block. Bite
	# two or three shallow notches out of the rim so the silhouette reads as
	# an organically grown city rather than a single bounding box.
	var bb := _footprint_bbox()
	if bb.size.x < 8 or bb.size.y < 8:
		return
	var before := footprint.duplicate()
	var before_count := _count_inside()
	var sides: Array[int] = [0, 1, 2, 3]
	for idx in range(sides.size() - 1, 0, -1):
		var swap_with := _rng.randi_range(0, idx)
		var tmp := sides[idx]
		sides[idx] = sides[swap_with]
		sides[swap_with] = tmp
	var notches := _rng.randi_range(2, 3)
	for i in notches:
		var side: int = sides[i % sides.size()]
		var notch_w := _rng.randi_range(2, mini(5, bb.size.x / 2))
		var notch_h := _rng.randi_range(2, mini(5, bb.size.y / 2))
		var depth := _rng.randi_range(1, 3)
		if side <= 1:
			var start_x := _rng.randi_range(bb.position.x + 1, bb.position.x + bb.size.x - notch_w - 1)
			var start_y := bb.position.y if side == 0 else bb.position.y + bb.size.y - depth
			for yy in range(start_y, start_y + depth):
				for xx in range(start_x, start_x + notch_w):
					if xx >= 0 and yy >= 0 and xx < width and yy < height:
						footprint[yy * width + xx] = 0
		else:
			var start_y := _rng.randi_range(bb.position.y + 1, bb.position.y + bb.size.y - notch_h - 1)
			var start_x := bb.position.x if side == 2 else bb.position.x + bb.size.x - depth
			for yy in range(start_y, start_y + notch_h):
				for xx in range(start_x, start_x + depth):
					if xx >= 0 and yy >= 0 and xx < width and yy < height:
						footprint[yy * width + xx] = 0
	_keep_largest_component()
	if _count_inside() < int(before_count * 0.78):
		footprint = before


func _center_outline() -> void:
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in height:
		for x in width:
			if footprint[y * width + x] == 1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return
	var margin_x := maxi(1, int(round(width * 0.05)))
	var margin_y := maxi(1, int(round(height * 0.05)))
	var dx := int(round((width - 1) * 0.5 - (min_x + max_x) * 0.5))
	var dy := int(round((height - 1) * 0.5 - (min_y + max_y) * 0.5))
	dx = clampi(dx, margin_x - min_x, width - 1 - margin_x - max_x)
	dy = clampi(dy, margin_y - min_y, height - 1 - margin_y - max_y)
	if dx == 0 and dy == 0:
		return
	var moved := PackedByteArray()
	moved.resize(width * height)
	moved.fill(0)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if footprint[y * width + x] == 1:
				moved[(y + dy) * width + (x + dx)] = 1
	footprint = moved


func _fallback_outline() -> void:
	# If anything went wrong, a solid centered rectangle still gives a usable
	# map instead of an empty one.
	footprint.fill(0)
	var x0 := maxi(1, int(width * 0.15))
	var y0 := maxi(1, int(height * 0.15))
	var x1 := mini(width - 1, int(width * 0.85))
	var y1 := mini(height - 1, int(height * 0.85))
	for y in range(y0, y1):
		for x in range(x0, x1):
			footprint[y * width + x] = 1


func _keep_largest_component() -> void:
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var best: Array[Vector2i] = []
	for y in height:
		for x in width:
			var idx := y * width + x
			if footprint[idx] == 0 or visited[idx] == 1:
				continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			var component: Array[Vector2i] = []
			visited[idx] = 1
			var head := 0
			while head < queue.size():
				var current: Vector2i = queue[head]
				head += 1
				component.append(current)
				for dir in DIRS:
					var nx := current.x + dir.x
					var ny := current.y + dir.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var nidx := ny * width + nx
					if footprint[nidx] == 1 and visited[nidx] == 0:
						visited[nidx] = 1
						queue.append(Vector2i(nx, ny))
			if component.size() > best.size():
				best = component
	if best.is_empty():
		return
	footprint.fill(0)
	for cell in best:
		footprint[cell.y * width + cell.x] = 1


func _refresh_inside() -> void:
	_inside_cells.clear()
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in height:
		for x in width:
			if footprint[y * width + x] == 1:
				_inside_cells.append(Vector2i(x, y))
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x >= min_x and max_y >= min_y:
		_bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	else:
		_bbox = Rect2i()


func _inside_neighbor_count(x: int, y: int) -> int:
	var count := 0
	for dir in DIRS:
		var nx := x + dir.x
		var ny := y + dir.y
		if nx >= 0 and ny >= 0 and nx < width and ny < height:
			if footprint[ny * width + nx] == 1:
				count += 1
	return count


func _rect_overlap_area(a: Rect2i, b: Rect2i) -> int:
	var x0 := maxi(a.position.x, b.position.x)
	var y0 := maxi(a.position.y, b.position.y)
	var x1 := mini(a.position.x + a.size.x, b.position.x + b.size.x)
	var y1 := mini(a.position.y + a.size.y, b.position.y + b.size.y)
	return maxi(0, x1 - x0) * maxi(0, y1 - y0)


# ---------------------------------------------------------------------------
# Districts: weighted Voronoi with a little noise for organic edges
# ---------------------------------------------------------------------------

func _assign_zones() -> void:
	_zone_seeds.clear()
	if _inside_cells.is_empty():
		return
	var center := Vector2(_bbox.position.x + _bbox.size.x * 0.5, _bbox.position.y + _bbox.size.y * 0.5)
	var center_cell := _nearest_inside(center)
	_zone_seeds.append({
		"pos": center_cell,
		"zone": ZONE_COM,
		"weight": 1.28,
		"name": "商业区",
	})

	var specs := [
		{"zone": ZONE_RES, "weight": 1.04, "angle": PI * 0.5},
		{"zone": ZONE_IND, "weight": 0.94, "angle": PI},
		{"zone": ZONE_RES, "weight": 1.0, "angle": PI * 1.5},
		{"zone": ZONE_PARK, "weight": 0.74, "angle": PI * 0.25},
	]
	var base_angle := _rng.randf() * TAU
	var radius := Vector2(_bbox.size.x * 0.32, _bbox.size.y * 0.30)
	var used_names := {"商业区": true}
	for spec in specs:
		var seed_cell := center_cell
		for attempt in 5:
			var angle: float = base_angle + spec["angle"] + _rng.randf_range(-0.30, 0.30)
			var target := center + Vector2(cos(angle), sin(angle)) * radius
			seed_cell = _nearest_inside(target)
			var too_close := false
			for existing in _zone_seeds:
				if Vector2(seed_cell).distance_to(Vector2(existing["pos"])) < 4.0:
					too_close = true
					break
			if not too_close:
				break
		var zone_name := "城市公园"
		if spec["zone"] == ZONE_RES:
			zone_name = "居民区·" + _direction_suffix(center_cell, seed_cell)
		elif spec["zone"] == ZONE_IND:
			zone_name = "工业区·" + _direction_suffix(center_cell, seed_cell)
		if used_names.has(zone_name):
			zone_name += "二"
		used_names[zone_name] = true
		_zone_seeds.append({
			"pos": seed_cell,
			"zone": spec["zone"],
			"weight": spec["weight"],
			"name": zone_name,
		})

	for cell in _inside_cells:
		var best_zone := ZONE_RES
		var best_score := 1.0e20
		for seed in _zone_seeds:
			var pos: Vector2i = seed["pos"]
			var dx := float(cell.x - pos.x)
			var dy := float(cell.y - pos.y)
			var distance := sqrt(dx * dx + dy * dy) / float(seed["weight"])
			distance += _rng.randf_range(-1.3, 1.3)
			if distance < best_score:
				best_score = distance
				best_zone = int(seed["zone"])
		zone_map[cell.y * width + cell.x] = best_zone


func _ensure_min_park() -> void:
	var park_seed := Vector2i.ZERO
	var has_park := false
	for seed in _zone_seeds:
		if int(seed["zone"]) == ZONE_PARK:
			park_seed = seed["pos"]
			has_park = true
			break
	if not has_park:
		return
	var park_count := 0
	for cell in _inside_cells:
		if int(zone_map[cell.y * width + cell.x]) == ZONE_PARK:
			park_count += 1
	var target := maxi(6, int(_inside_cells.size() * 0.05))
	if park_count >= target:
		return
	var candidates := _inside_cells.duplicate()
	var target_vec := Vector2(park_seed)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(target_vec) < Vector2(b).distance_squared_to(target_vec))
	var needed := target - park_count
	for cell in candidates:
		var idx: int = cell.y * width + cell.x
		if int(zone_map[idx]) == ZONE_PARK:
			continue
		zone_map[idx] = ZONE_PARK
		needed -= 1
		if needed <= 0:
			break


func _scatter_pocket_parks() -> void:
	# A few trees in the leftover courtyards stop empty blocks from reading
	# like failed placement.
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if _rng.randf() > 0.045:
				continue
			var can_place := true
			for yy in range(y, y + 2):
				for xx in range(x, x + 2):
					if not is_inside(xx, yy) or cells[yy * width + xx] != PLAZA:
						can_place = false
						break
				if not can_place:
					break
			if can_place:
				for yy in range(y, y + 2):
					for xx in range(x, x + 2):
						cells[yy * width + xx] = PARK
	for cell in _inside_cells:
		var idx: int = cell.y * width + cell.x
		if cells[idx] != PLAZA:
			continue
		if _rng.randf() > 0.055:
			continue
		var open_neighbors := 0
		for dir in DIRS:
			var nx := cell.x + dir.x
			var ny := cell.y + dir.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			if cells[ny * width + nx] == PLAZA:
				open_neighbors += 1
		if open_neighbors >= 2:
			cells[idx] = PARK


func _nearest_inside(target: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1.0e20
	for cell in _inside_cells:
		var d := Vector2(cell).distance_squared_to(target)
		if d < best_distance:
			best_distance = d
			best = cell
	return best


func _nearest_zone_cell(target: Vector2, zone: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1.0e20
	for cell in _inside_cells:
		if _is_road_at(cell.x, cell.y):
			continue
		if int(zone_map[cell.y * width + cell.x]) != zone:
			continue
		var d := Vector2(cell).distance_squared_to(target)
		if d < best_distance:
			best_distance = d
			best = cell
	if best.x >= 0:
		return best
	return _nearest_inside(target)


func _direction_suffix(from: Vector2i, to: Vector2i) -> String:
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	if dy >= dx:
		return "北" if to.y < from.y else "南"
	return "西" if to.x < from.x else "东"


# ---------------------------------------------------------------------------
# Road network
# ---------------------------------------------------------------------------

func _build_roads() -> void:
	var center := _bbox.position + Vector2i(_bbox.size.x / 2, _bbox.size.y / 2)
	var vertical_targets: Array[int] = []
	var horizontal_targets: Array[int] = []
	# Evenly spaced arterials read as city planning; a random offset keeps the
	# grid from looking machine-perfect.
	var vertical_fracs: Array[float] = [0.30, 0.70]
	var horizontal_fracs: Array[float] = [0.30, 0.70]
	if _bbox.size.x >= 22:
		vertical_fracs = [0.17, 0.50, 0.83]
	if _bbox.size.y >= 26:
		horizontal_fracs = [0.17, 0.50, 0.83]
	for fraction in vertical_fracs:
		vertical_targets.append(_bbox.position.x + int(_bbox.size.x * fraction) + _rng.randi_range(-1, 1))
	for fraction in horizontal_fracs:
		horizontal_targets.append(_bbox.position.y + int(_bbox.size.y * fraction) + _rng.randi_range(-1, 1))

	for target in vertical_targets:
		var run := _best_vertical_run(target)
		if int(run.get("len", 0)) < 4:
			continue
		# One-cell-wide avenues keep the map playable; the visual hierarchy
		# comes from colour and centre-line markings instead of width.
		_carve_vertical_run(run)

	for target in horizontal_targets:
		var run := _best_horizontal_run(target)
		if int(run.get("len", 0)) < 4:
			continue
		_carve_horizontal_run(run)

	_carve_ring(center)


func _best_vertical_run(target_x: int) -> Dictionary:
	var best := {"x": target_x, "y0": 0, "y1": -1, "len": 0}
	var best_score := -1.0e20
	var radius := 2
	for attempt in 2:
		for xx in range(target_x - radius, target_x + radius + 1):
			if xx < 0 or xx >= width:
				continue
			var y := 0
			while y < height:
				while y < height and not is_inside(xx, y):
					y += 1
				if y >= height:
					break
				var start := y
				while y < height and is_inside(xx, y):
					y += 1
				var length := y - start
				# Prefer the requested position; only drift for a clearly
				# longer run (irregular outline near the edge of a wing).
				var score := float(length) - absf(float(xx - target_x)) * 2.2
				if score > best_score:
					best_score = score
					best = {"x": xx, "y0": start, "y1": y - 1, "len": length}
		if int(best["len"]) >= int(_bbox.size.y * 0.55):
			break
		radius = 6
	return best


func _best_horizontal_run(target_y: int) -> Dictionary:
	var best := {"y": target_y, "x0": 0, "x1": -1, "len": 0}
	var best_score := -1.0e20
	var radius := 2
	for attempt in 2:
		for yy in range(target_y - radius, target_y + radius + 1):
			if yy < 0 or yy >= height:
				continue
			var x := 0
			while x < width:
				while x < width and not is_inside(x, yy):
					x += 1
				if x >= width:
					break
				var start := x
				while x < width and is_inside(x, yy):
					x += 1
				var length := x - start
				var score := float(length) - absf(float(yy - target_y)) * 2.2
				if score > best_score:
					best_score = score
					best = {"y": yy, "x0": start, "x1": x - 1, "len": length}
		if int(best["len"]) >= int(_bbox.size.x * 0.55):
			break
		radius = 6
	return best


func _carve_vertical_run(run: Dictionary) -> void:
	var x := int(run["x"])
	var y0 := int(run["y0"])
	var y1 := int(run["y1"])
	var drift := 1 if _rng.randf() < 0.5 else -1
	for y in range(y0, y1 + 1):
		if not is_inside(x, y):
			var moved := false
			for offset in [0, drift, -drift]:
				if is_inside(x + offset, y):
					x += offset
					moved = true
					break
			if not moved:
				continue
		_set_road(x, y, true)
		if _rng.randf() < 0.07:
			drift = -drift
		if _rng.randf() < 0.08:
			if is_inside(x + drift, y):
				x += drift


func _carve_horizontal_run(run: Dictionary) -> void:
	var y := int(run["y"])
	var x0 := int(run["x0"])
	var x1 := int(run["x1"])
	var drift := 1 if _rng.randf() < 0.5 else -1
	for x in range(x0, x1 + 1):
		if not is_inside(x, y):
			var moved := false
			for offset in [0, drift, -drift]:
				if is_inside(x, y + offset):
					y += offset
					moved = true
					break
			if not moved:
				continue
		_set_road(x, y, true)
		if _rng.randf() < 0.07:
			drift = -drift
		if _rng.randf() < 0.08:
			if is_inside(x, y + drift):
				y += drift


func _ensure_roads() -> void:
	for cell in cells:
		if cell == ROAD or cell == LANE:
			return
	if _inside_cells.is_empty():
		return
	var center := _bbox.position + Vector2i(_bbox.size.x / 2, _bbox.size.y / 2)
	var center_cell := _nearest_inside(Vector2(center))
	for y in height:
		if is_inside(center_cell.x, y):
			_set_road(center_cell.x, y, true)
	for x in width:
		if is_inside(x, center_cell.y):
			_set_road(x, center_cell.y, true)


func _carve_ring(center: Vector2i) -> void:
	if _bbox.size.x < 24 or _bbox.size.y < 28:
		return
	var ring_w := clampi(int(_bbox.size.x * _rng.randf_range(0.44, 0.58)), 8, _bbox.size.x - 2)
	var ring_h := clampi(int(_bbox.size.y * _rng.randf_range(0.40, 0.54)), 8, _bbox.size.y - 2)
	for attempt in 6:
		var ring_x := clampi(center.x - ring_w / 2, _bbox.position.x, _bbox.position.x + _bbox.size.x - ring_w)
		var ring_y := clampi(center.y - ring_h / 2, _bbox.position.y, _bbox.position.y + _bbox.size.y - ring_h)
		var fits := true
		for x in range(ring_x, ring_x + ring_w):
			if not is_inside(x, ring_y) or not is_inside(x, ring_y + ring_h - 1):
				fits = false
				break
		if fits:
			for y in range(ring_y, ring_y + ring_h):
				if not is_inside(ring_x, y) or not is_inside(ring_x + ring_w - 1, y):
					fits = false
					break
		if fits:
			for x in range(ring_x, ring_x + ring_w):
				_set_road(x, ring_y, true)
				_set_road(x, ring_y + ring_h - 1, true)
			for y in range(ring_y, ring_y + ring_h):
				_set_road(ring_x, y, true)
				_set_road(ring_x + ring_w - 1, y, true)
			_has_ring = true
			return
		ring_w = maxi(8, ring_w - 2)
		ring_h = maxi(8, ring_h - 2)


func _set_road(x: int, y: int, main: bool) -> void:
	if not is_inside(x, y):
		return
	var idx := y * width + x
	if main:
		cells[idx] = ROAD
	elif cells[idx] != ROAD:
		cells[idx] = LANE


func _build_secondary_streets() -> void:
	var budget := maxi(6, int(_inside_cells.size() * 0.055))
	for pass_index in 2:
		if budget <= 0:
			break
		var blocks := _block_components()
		blocks.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
		for block in blocks:
			if budget <= 0:
				break
			if block.size() < 15:
				continue
			var bb := _component_bbox(block)
			if bb.size.x < 5 or bb.size.y < 5:
				continue
			var vertical := bb.size.x >= bb.size.y
			var line := _find_block_cut(block, vertical, bb)
			if line.size() < 4 or line.size() > budget:
				continue
			var connects := false
			for end_index in [0, line.size() - 1]:
				var cell: Vector2i = line[end_index]
				for dir in DIRS:
					if _is_road_at(cell.x + dir.x, cell.y + dir.y):
						connects = true
						break
				if connects:
					break
			if not connects:
				continue
			for cell in line:
				var idx: int = cell.y * width + cell.x
				if cells[idx] != ROAD and cells[idx] != LANE:
					cells[idx] = LANE
					budget -= 1


func _find_block_cut(block: Array, vertical: bool, bb: Rect2i) -> Array[Vector2i]:
	var mark := PackedByteArray()
	mark.resize(width * height)
	mark.fill(0)
	for cell in block:
		mark[cell.y * width + cell.x] = 1
	var best: Array[Vector2i] = []
	var best_score := 0.0
	if vertical:
		for x in range(bb.position.x, bb.position.x + bb.size.x):
			var y := bb.position.y
			while y < bb.position.y + bb.size.y:
				while y < bb.position.y + bb.size.y and mark[y * width + x] == 0:
					y += 1
				if y >= bb.position.y + bb.size.y:
					break
				var start := y
				while y < bb.position.y + bb.size.y and mark[y * width + x] == 1:
					y += 1
				var length := y - start
				var score := float(length) - absf(float(x) - (bb.position.x + bb.size.x * 0.5)) * 0.12
				if length >= 4 and score > best_score:
					best_score = score
					best.clear()
					for yy in range(start, y):
						best.append(Vector2i(x, yy))
	else:
		for y in range(bb.position.y, bb.position.y + bb.size.y):
			var x := bb.position.x
			while x < bb.position.x + bb.size.x:
				while x < bb.position.x + bb.size.x and mark[y * width + x] == 0:
					x += 1
				if x >= bb.position.x + bb.size.x:
					break
				var start := x
				while x < bb.position.x + bb.size.x and mark[y * width + x] == 1:
					x += 1
				var length := x - start
				var score := float(length) - absf(float(y) - (bb.position.y + bb.size.y * 0.5)) * 0.12
				if length >= 4 and score > best_score:
					best_score = score
					best.clear()
					for xx in range(start, x):
						best.append(Vector2i(xx, y))
	return best


func _connect_road_components() -> void:
	var guard := 0
	var grid_size := width * height
	while guard < 48:
		var components := _road_components()
		if components.size() <= 1:
			return
		components.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
		var source: Array = components[0]
		var target: Array = components[1]
		var is_target := PackedByteArray()
		is_target.resize(grid_size)
		is_target.fill(0)
		for cell in target:
			is_target[cell.y * width + cell.x] = 1
		# Index-based BFS is much faster than a Dictionary<Vector2i, ...>.
		var parent := PackedInt32Array()
		parent.resize(grid_size)
		parent.fill(-1)
		var queue := PackedInt32Array()
		for cell in source:
			var idx: int = cell.y * width + cell.x
			parent[idx] = idx
			queue.append(idx)
		var found := -1
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			if is_target[current] == 1:
				found = current
				break
			var cx := current % width
			var cy := current / width
			if cx > 0:
				var nidx := current - 1
				if parent[nidx] == -1 and is_inside(cx - 1, cy):
					parent[nidx] = current
					queue.append(nidx)
			if cx + 1 < width:
				var nidx := current + 1
				if parent[nidx] == -1 and is_inside(cx + 1, cy):
					parent[nidx] = current
					queue.append(nidx)
			if cy > 0:
				var nidx := current - width
				if parent[nidx] == -1 and is_inside(cx, cy - 1):
					parent[nidx] = current
					queue.append(nidx)
			if cy + 1 < height:
				var nidx := current + width
				if parent[nidx] == -1 and is_inside(cx, cy + 1):
					parent[nidx] = current
					queue.append(nidx)
		if found < 0:
			return
		var cursor := found
		while parent[cursor] != cursor:
			_set_road(cursor % width, cursor / width, true)
			cursor = parent[cursor]
		_set_road(cursor % width, cursor / width, true)
		guard += 1


func _road_components() -> Array:
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var result: Array = []
	for y in height:
		for x in width:
			var idx := y * width + x
			if visited[idx] == 1 or not _is_road_at(x, y):
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[idx] = 1
			var head := 0
			while head < queue.size():
				var current: Vector2i = queue[head]
				head += 1
				component.append(current)
				for dir in DIRS:
					var nx := current.x + dir.x
					var ny := current.y + dir.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var nidx := ny * width + nx
					if visited[nidx] == 0 and _is_road_at(nx, ny):
						visited[nidx] = 1
						queue.append(Vector2i(nx, ny))
			result.append(component)
	return result


func _block_components() -> Array:
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var result: Array = []
	for y in height:
		for x in width:
			var idx := y * width + x
			if visited[idx] == 1 or footprint[idx] == 0 or _is_road_at(x, y):
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[idx] = 1
			var head := 0
			while head < queue.size():
				var current: Vector2i = queue[head]
				head += 1
				component.append(current)
				for dir in DIRS:
					var nx := current.x + dir.x
					var ny := current.y + dir.y
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var nidx := ny * width + nx
					if visited[nidx] == 0 and footprint[nidx] == 1 and not _is_road_at(nx, ny):
						visited[nidx] = 1
						queue.append(Vector2i(nx, ny))
			result.append(component)
	return result


func _component_bbox(component: Array) -> Rect2i:
	var min_x := width
	var min_y := height
	var max_x := 0
	var max_y := 0
	for cell in component:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _is_road_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var tile := cells[y * width + x]
	return tile == ROAD or tile == LANE


# ---------------------------------------------------------------------------
# Buildings and districts
# ---------------------------------------------------------------------------

func _place_buildings() -> void:
	for cell in _inside_cells:
		var idx: int = cell.y * width + cell.x
		if _is_road_at(cell.x, cell.y):
			continue
		cells[idx] = PARK if zone_map[idx] == ZONE_PARK else PLAZA

	for y in range(_bbox.position.y, _bbox.position.y + _bbox.size.y):
		for x in range(_bbox.position.x, _bbox.position.x + _bbox.size.x):
			var idx := y * width + x
			if not is_inside(x, y) or _is_road_at(x, y) or cells[idx] != PLAZA:
				continue
			var zone := int(zone_map[idx])
			if zone == ZONE_PARK:
				continue
			if _rng.randf() < 0.12:
				continue
			var placed_building := false
			for size in _building_size_candidates(zone):
				var building_w := size.x
				var building_h := size.y
				if _rng.randf() < 0.5:
					var tmp := building_w
					building_w = building_h
					building_h = tmp
				if _can_place_building(x, y, building_w, building_h, zone):
					_add_building(x, y, building_w, building_h, zone)
					placed_building = true
					break
			if placed_building:
				continue

	var building_area := _building_area()
	if buildings.size() < 10 or building_area < int(_inside_cells.size() * 0.18):
		_fill_leftover_buildings(building_area)


func _pick_building_size(zone: int) -> Vector2i:
	var roll := _rng.randf()
	if zone == ZONE_RES:
		if roll < 0.22:
			return Vector2i(2, 2)
		if roll < 0.66:
			return Vector2i(2, 3)
		return Vector2i(3, 3)
	if zone == ZONE_COM:
		if roll < 0.18:
			return Vector2i(2, 2)
		if roll < 0.52:
			return Vector2i(3, 3)
		if roll < 0.82:
			return Vector2i(3, 4)
		return Vector2i(4, 4)
	if zone == ZONE_IND:
		if roll < 0.30:
			return Vector2i(3, 3)
		if roll < 0.70:
			return Vector2i(4, 3)
		return Vector2i(4, 4)
	return Vector2i(2, 2)


func _building_size_candidates(zone: int) -> Array[Vector2i]:
	# Try the district's preferred building size first, then shrink near road
	# edges / zone borders. Adjacent buildings are allowed (row-house blocks),
	# only the interior cells are checked, so the map stays dense.
	var preferred := _pick_building_size(zone)
	var candidates: Array[Vector2i] = [preferred]
	if zone == ZONE_RES:
		candidates.append_array([Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1)])
	elif zone == ZONE_COM:
		candidates.append_array([Vector2i(3, 4), Vector2i(3, 3), Vector2i(2, 2), Vector2i(2, 1)])
	elif zone == ZONE_IND:
		candidates.append_array([Vector2i(4, 3), Vector2i(3, 3), Vector2i(2, 2), Vector2i(2, 1)])
	else:
		candidates.append_array([Vector2i(2, 2), Vector2i(2, 1)])
	return candidates


func _can_place_building(x: int, y: int, w: int, h: int, zone: int) -> bool:
	if x < 0 or y < 0 or x + w > width or y + h > height:
		return false
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var idx := yy * width + xx
			if not is_inside(xx, yy) or _is_road_at(xx, yy):
				return false
			if int(zone_map[idx]) != zone:
				return false
			if cells[idx] != PLAZA:
				return false
	return true


func _add_building(x: int, y: int, w: int, h: int, zone: int) -> void:
	var tile := _tile_for_zone(zone)
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			cells[yy * width + xx] = tile
	buildings.append({
		"x": x, "y": y, "w": w, "h": h,
		"zone": zone,
		"poi": "",
	})


func _fill_leftover_buildings(building_area: int) -> void:
	# Guarantees a dense, usable map even if the rectangle pass was unlucky.
	if building_area >= int(_inside_cells.size() * 0.14) and buildings.size() >= 8:
		return
	for cell in _inside_cells:
		var idx: int = cell.y * width + cell.x
		if cells[idx] != PLAZA:
			continue
		if _has_building_neighbor(cell.x, cell.y):
			continue
		var zone := int(zone_map[idx])
		if zone == ZONE_PARK:
			continue
		_add_building(cell.x, cell.y, 1, 1, zone)


func _has_building_neighbor(x: int, y: int) -> bool:
	for yy in range(y - 1, y + 2):
		for xx in range(x - 1, x + 2):
			if xx == x and yy == y:
				continue
			if xx < 0 or yy < 0 or xx >= width or yy >= height:
				continue
			if _is_building_tile(cells[yy * width + xx]):
				return true
	return false


func _building_area() -> int:
	var area := 0
	for building in buildings:
		area += int(building["w"]) * int(building["h"])
	return area


func _tile_for_zone(zone: int) -> String:
	match zone:
		ZONE_COM:
			return COM
		ZONE_IND:
			return IND
		ZONE_PARK:
			return PARK
		_:
			return RES


func _is_building_tile(tile: String) -> bool:
	return tile == RES or tile == COM or tile == IND or tile == PUB


# ---------------------------------------------------------------------------
# POIs: label-only landmarks, no separate tile type
# ---------------------------------------------------------------------------

func _assign_pois() -> void:
	if buildings.is_empty():
		return
	var used := {}
	var center := Vector2(_bbox.position.x + _bbox.size.x * 0.5, _bbox.position.y + _bbox.size.y * 0.5)
	var hospital := _choose_poi_building([ZONE_COM, ZONE_RES], center, 4, used)
	if hospital >= 0:
		_mark_poi(hospital, "hospital", used)
	var fire_near := Vector2(center.x, center.y + _bbox.size.y * 0.34)
	var fire := _choose_poi_building([ZONE_IND, ZONE_RES, ZONE_COM], fire_near, 3, used)
	if fire >= 0:
		_mark_poi(fire, "fire", used)
	var police := _choose_poi_building([ZONE_COM, ZONE_RES], center, 3, used)
	if police >= 0:
		_mark_poi(police, "police", used)
	var school := _choose_poi_building([ZONE_RES], center, 4, used)
	if school >= 0:
		_mark_poi(school, "school", used)
	var city_hall := _choose_poi_building([ZONE_COM], center, 4, used)
	if city_hall >= 0:
		_mark_poi(city_hall, "city_hall", used)

	# The two required landmarks must exist even on a tiny map.
	if hospital < 0:
		_force_poi("hospital", used)
	if fire < 0:
		_force_poi("fire", used)


func _choose_poi_building(preferred_zones: Array, near: Vector2, min_area: int, used: Dictionary) -> int:
	var best := -1
	var best_score := -1.0e20
	for i in buildings.size():
		if used.has(i):
			continue
		var building: Dictionary = buildings[i]
		if int(building["w"]) * int(building["h"]) < min_area:
			continue
		var score := 0.0
		if preferred_zones.has(int(building["zone"])):
			score += 14.0
		score += mini(int(building["w"]) * int(building["h"]), 16) * 1.5
		score += 10.0 if _building_touches_main_road(building) else 0.0
		var bx := float(building["x"]) + float(building["w"]) * 0.5
		var by := float(building["y"]) + float(building["h"]) * 0.5
		score -= Vector2(bx, by).distance_to(near) * 0.9
		# Spread public landmarks out instead of clustering them in the CBD.
		for used_index in used.keys():
			var other: Dictionary = buildings[used_index]
			var ox := float(other["x"]) + float(other["w"]) * 0.5
			var oy := float(other["y"]) + float(other["h"]) * 0.5
			var spacing := Vector2(bx, by).distance_to(Vector2(ox, oy))
			if spacing < 8.0:
				score -= (8.0 - spacing) * 5.0
		if score > best_score:
			best_score = score
			best = i
	return best


func _force_poi(kind: String, used: Dictionary) -> void:
	for i in buildings.size():
		if not used.has(i):
			_mark_poi(i, kind, used)
			return


func _mark_poi(index: int, kind: String, used: Dictionary) -> void:
	used[index] = true
	var building: Dictionary = buildings[index]
	building["poi"] = kind
	for yy in range(int(building["y"]), int(building["y"]) + int(building["h"])):
		for xx in range(int(building["x"]), int(building["x"]) + int(building["w"])):
			cells[yy * width + xx] = PUB


func _building_touches_main_road(building: Dictionary) -> bool:
	var x0 := int(building["x"])
	var y0 := int(building["y"])
	var x1 := x0 + int(building["w"])
	var y1 := y0 + int(building["h"])
	for x in range(x0 - 1, x1 + 1):
		if get_tile(x, y0 - 1) == ROAD or get_tile(x, y1) == ROAD:
			return true
	for y in range(y0 - 1, y1 + 1):
		if get_tile(x0 - 1, y) == ROAD or get_tile(x1, y) == ROAD:
			return true
	return false


# ---------------------------------------------------------------------------
# Labels and statistics
# ---------------------------------------------------------------------------

func _collect_labels() -> void:
	# District labels are placed at the district centroid, not at the Voronoi
	# seed, so they sit comfortably inside each coloured area.
	var zone_sum := {}
	var zone_count := {}
	for cell in _inside_cells:
		if _is_road_at(cell.x, cell.y):
			continue
		var zone := int(zone_map[cell.y * width + cell.x])
		if not zone_sum.has(zone):
			zone_sum[zone] = Vector2.ZERO
			zone_count[zone] = 0
		zone_sum[zone] += Vector2(cell)
		zone_count[zone] += 1
	for seed in _zone_seeds:
		var zone := int(seed["zone"])
		var label_cell: Vector2i = seed["pos"]
		if zone_sum.has(zone) and int(zone_count[zone]) > 0:
			var centroid: Vector2 = zone_sum[zone] / float(zone_count[zone])
			label_cell = _nearest_zone_cell(centroid, zone)
		labels.append({
			"text": String(seed["name"]),
			"cell": label_cell,
			"kind": "zone",
			"priority": 1,
			"subtype": zone,
		})

	for building in buildings:
		var poi := String(building["poi"])
		if poi.is_empty():
			continue
		var center := Vector2i(
			int(building["x"]) + int(building["w"]) / 2,
			int(building["y"]) + int(building["h"]) / 2
		)
		labels.append({
			"text": POI_NAMES.get(poi, poi),
			"cell": center,
			"kind": "poi",
			"priority": 3,
			"subtype": poi,
		})

func _build_stats() -> void:
	var roads := 0
	var lanes := 0
	var pois := 0
	for cell in cells:
		if cell == ROAD:
			roads += 1
		elif cell == LANE:
			lanes += 1
	for building in buildings:
		if not String(building["poi"]).is_empty():
			pois += 1
	stats = {
		"width": width,
		"height": height,
		"seed": used_seed,
		"inside": _inside_cells.size(),
		"roads": roads,
		"lanes": lanes,
		"buildings": buildings.size(),
		"pois": pois,
		"labels": labels.size(),
		"road_components": _road_components().size(),
		"has_ring": _has_ring,
		"ms": generation_msec,
	}
