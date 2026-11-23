extends Node2D
## Fast city-map demo.
##
## Replaces the old Wave Function Collapse demo. The map is generated in a
## single synchronous pass by city_map.gd and drawn directly with canvas draw
## calls; text annotations are real Label nodes, not tiles. Press R to reroll.

const CityMapScript = preload("res://assets/map_generator/demo/city_map.gd")

const COL_BG := Color("#090d13")
const COL_PANEL := Color("#111823")
const COL_PANEL_EDGE := Color("#8a7448")
const COL_GROUND := Color("#252c37")
const COL_GROUND_ALT := Color("#222933")
const COL_PLAZA := Color("#303a49")
const COL_GRID := Color(1.0, 1.0, 1.0, 0.022)
const COL_PARK := Color("#2a4838")
const COL_PARK_ALT := Color("#315440")
const COL_WATER := Color("#2b4d6a")
const COL_ROAD := Color("#697183")
const COL_LANE := Color("#4f5664")
const COL_CURB := Color("#a39a86")
const COL_LANE_MARK := Color("#d6b25e")
const COL_BORDER := Color("#070a0e")
const COL_BORDER_GOLD := Color("#caa768")

const LABEL_COLORS := {
	"zone_com": Color("#8fd3ff"),
	"zone_res": Color("#ffe0a3"),
	"zone_ind": Color("#ffc68a"),
	"zone_park": Color("#a8e6a0"),
	"hospital": Color("#ff9b9b"),
	"fire": Color("#ffb36b"),
	"police": Color("#9dc0ff"),
	"school": Color("#ffe28a"),
	"city_hall": Color("#d7b6ff"),
}

@export_range(10, 96, 1) var length: int = 24
@export_range(10, 96, 1) var height: int = 32
@export_range(8.0, 40.0, 1.0) var cell_size: float = 18.0
@export var random_seed: int = 0
@export var auto_fit: bool = true
@export var show_status: bool = true

var city: RefCounted
var _font: SystemFont
var _canvas: CanvasLayer
var _label_nodes: Array[Label] = []
var _label_boxes: Array[Rect2] = []
var _status_label: Label
var _legend_label: Label
var _map_origin := Vector2.ZERO
var _map_scale := 1.0

const PAD_X := 20.0
const PAD_TOP := 36.0
const PAD_BOTTOM := 54.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(COL_BG)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC",
		"Noto Sans SC", "PingFang SC", "WenQuanYi Micro Hei", "Arial"
	])
	_canvas = CanvasLayer.new()
	_canvas.layer = 4
	add_child(_canvas)
	_create_hud()
	_generate()
	get_viewport().size_changed.connect(_on_viewport_resized)


func regenerate(seed_override: int = -1) -> void:
	_generate(seed_override)


func _generate(seed_override: int = -1) -> void:
	var seed_value := random_seed
	if seed_override >= 0:
		seed_value = seed_override
	if seed_value == 0:
		seed_value = randi() | 1
	city = CityMapScript.new()
	city.generate(length, height, seed_value)
	_layout_map()
	_update_hud()
	print("[CityMap] seed=%d size=%dx%d cells=%d roads=%d buildings=%d labels=%d components=%d time=%.2fms" % [
		int(city.stats["seed"]), int(city.stats["width"]), int(city.stats["height"]),
		int(city.stats["inside"]), int(city.stats["roads"]) + int(city.stats["lanes"]),
		int(city.stats["buildings"]), int(city.stats["labels"]),
		int(city.stats["road_components"]), float(city.stats["ms"]),
	])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_generate(randi() | 1)
		get_viewport().set_input_as_handled()


func _on_viewport_resized() -> void:
	_layout_map()
	_update_hud()


# ---------------------------------------------------------------------------
# Layout and labels
# ---------------------------------------------------------------------------

func _layout_map() -> void:
	if city == null:
		return
	var viewport_size := get_viewport_rect().size
	var bbox: Rect2i = city.get_map_rect()
	var focus_size := Vector2(bbox.size) * cell_size
	var focus_center := (Vector2(bbox.position) + Vector2(bbox.size) * 0.5) * cell_size
	var available := Vector2(
		maxf(1.0, viewport_size.x - PAD_X * 2.0),
		maxf(1.0, viewport_size.y - PAD_TOP - PAD_BOTTOM)
	)
	if auto_fit:
		_map_scale = minf(available.x / focus_size.x, available.y / focus_size.y)
		_map_scale = clampf(_map_scale, 0.05, 1.5)
		_map_origin = Vector2(
			viewport_size.x * 0.5,
			PAD_TOP + available.y * 0.5
		) - focus_center * _map_scale
	else:
		_map_scale = 1.0
		_map_origin = Vector2(PAD_X, PAD_TOP) - Vector2(bbox.position) * cell_size
	position = _map_origin
	scale = Vector2.ONE * _map_scale
	_rebuild_labels()
	queue_redraw()


func _rebuild_labels() -> void:
	for label in _label_nodes:
		label.queue_free()
	_label_nodes.clear()
	_label_boxes.clear()
	if city == null:
		return

	var viewport_size := get_viewport_rect().size
	if show_status:
		_label_boxes.append(Rect2(0.0, 0.0, viewport_size.x, 30.0))
		_label_boxes.append(Rect2(0.0, viewport_size.y - 44.0, viewport_size.x, 44.0))
	var cell_screen := cell_size * _map_scale
	var zone_font := clampi(int(round(cell_screen * 0.72)), 10, 14)
	var poi_font := clampi(int(round(cell_screen * 0.62)), 9, 12)

	var sorted_labels: Array = city.labels.duplicate()
	sorted_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))

	for info in sorted_labels:
		var kind := String(info["kind"])
		var text := String(info["text"])
		var font_size := zone_font
		if kind == "poi":
			font_size = poi_font
		var color := _label_color(kind, info["subtype"])
		var text_size: Vector2 = _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		)
		var box_size := text_size + Vector2(10.0, 4.0)
		var cell: Vector2i = info["cell"]
		var anchor_local := (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
		var anchor := _map_origin + anchor_local * _map_scale
		var preferred := Vector2.ZERO
		if kind == "poi":
			preferred = Vector2(0.0, -cell_screen * 0.9)

		# On very dense maps a cell is only a few pixels wide; still move labels
		# by at least one text line so collision avoidance can actually work.
		var label_step := maxf(cell_screen * 1.1, 14.0)
		var candidates: Array[Vector2] = [
			preferred,
			preferred + Vector2(0.0, -label_step),
			preferred + Vector2(0.0, label_step),
			preferred + Vector2(label_step, 0.0),
			preferred + Vector2(-label_step, 0.0),
			preferred + Vector2(label_step, -label_step),
			preferred + Vector2(-label_step, -label_step),
			preferred + Vector2(label_step, label_step),
			preferred + Vector2(-label_step, label_step),
			preferred + Vector2(0.0, -label_step * 2.0),
			preferred + Vector2(0.0, label_step * 2.0),
			preferred + Vector2(label_step * 2.0, 0.0),
			preferred + Vector2(-label_step * 2.0, 0.0),
		]

		var placed := false
		var fallback_rect := Rect2()
		for offset in candidates:
			var center := anchor + offset
			center.x = clampf(center.x, box_size.x * 0.5 + 4.0, viewport_size.x - box_size.x * 0.5 - 4.0)
			center.y = clampf(center.y, box_size.y * 0.5 + 4.0, viewport_size.y - box_size.y * 0.5 - 4.0)
			var box := Rect2(center - box_size * 0.5, box_size)
			if fallback_rect.size == Vector2.ZERO:
				fallback_rect = box
			var collides := false
			for placed_box in _label_boxes:
				if placed_box.grow(2.0).intersects(box):
					collides = true
					break
			if collides:
				continue
			_create_label(text, box, font_size, color)
			placed = true
			break
		if not placed and kind == "poi" and fallback_rect.size != Vector2.ZERO:
			# Important landmarks keep their label even on a tiny map.
			_create_label(text, fallback_rect, font_size, color)


func _create_label(text: String, box: Rect2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.96))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = box.position
	label.size = box.size
	_canvas.add_child(label)
	_label_nodes.append(label)
	_label_boxes.append(box)


func _label_color(kind: String, subtype: Variant) -> Color:
	if kind == "zone":
		match int(subtype):
			0:
				return LABEL_COLORS["zone_res"]
			1:
				return LABEL_COLORS["zone_com"]
			2:
				return LABEL_COLORS["zone_ind"]
			3:
				return LABEL_COLORS["zone_park"]
	if kind == "poi":
		return LABEL_COLORS.get(String(subtype), Color.WHITE)
	return Color.WHITE


func _create_hud() -> void:
	_status_label = _make_hud_label(10, Color("#b9c2cf"))
	_legend_label = _make_hud_label(8, Color("#7f8a9a"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_legend_label.text = "R 主干道   r 支路   H 居民   C 商业   I 工业\nP 公共   G 公园   . 空地   图格名称均为单字符"
	_status_label.z_index = 10
	_legend_label.z_index = 10
	_status_label.visible = show_status
	_legend_label.visible = show_status
	_update_hud()


func _make_hud_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label


func _update_hud() -> void:
	if _status_label == null:
		return
	var viewport_size := get_viewport_rect().size
	_status_label.position = Vector2(12.0, 9.0)
	_status_label.size = Vector2(viewport_size.x - 24.0, 20.0)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_legend_label.position = Vector2(12.0, viewport_size.y - 40.0)
	_legend_label.size = Vector2(viewport_size.x - 24.0, 32.0)
	_legend_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if city == null:
		return
	var stats: Dictionary = city.stats
	_status_label.text = "种子 %d  ·  %d×%d  ·  %d 格  ·  %d 建筑  ·  %.1f ms  ·  按 R 重新生成" % [
		int(stats["seed"]), int(stats["width"]), int(stats["height"]),
		int(stats["inside"]), int(stats["buildings"]), float(stats["ms"]),
	]


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if city == null:
		return
	var cs := cell_size
	var bbox: Rect2i = city.get_map_rect()
	var panel := Rect2(Vector2(bbox.position) * cs, Vector2(bbox.size) * cs).grow(7.0)

	draw_rect(panel, COL_PANEL, true)
	draw_rect(panel, COL_PANEL_EDGE, false, 1.0)

	# Ground / parks.
	for y in city.height:
		for x in city.width:
			if not city.is_inside(x, y):
				continue
			var tile: String = city.get_tile(x, y)
			var p := Vector2(x, y) * cs
			var color := COL_GROUND
			if tile == "G":
				color = COL_PARK_ALT if (x + y) % 3 == 0 else COL_PARK
			elif tile == "W":
				color = COL_WATER
			elif tile == ".":
				color = COL_PLAZA
			elif (x * 5 + y * 11) % 7 == 0:
				color = COL_GROUND_ALT
			draw_rect(Rect2(p, Vector2(cs, cs)), color, true)
			if tile != "G" and tile != "W":
				draw_rect(Rect2(p, Vector2(cs, cs)), COL_GRID, false, 1.0)

	# Roads.
	for y in city.height:
		for x in city.width:
			if not city.is_inside(x, y):
				continue
			var tile: String = city.get_tile(x, y)
			if tile != "R" and tile != "r":
				continue
			var p := Vector2(x, y) * cs
			var color := COL_ROAD if tile == "R" else COL_LANE
			draw_rect(Rect2(p, Vector2(cs, cs)), color, true)

	# Curbs and lane markings are drawn after the asphalt.
	for y in city.height:
		for x in city.width:
			if not city.is_inside(x, y):
				continue
			var tile: String = city.get_tile(x, y)
			if tile != "R" and tile != "r":
				continue
			_draw_road_cell(x, y, tile)
	_draw_lane_markings()

	# Parks details.
	for y in city.height:
		for x in city.width:
			if city.get_tile(x, y) == "G":
				_draw_tree(x, y)

	# Buildings (single rectangle per building keeps the map readable).
	for building in city.buildings:
		_draw_building(building)

	# Landmark markers on top of roofs.
	for building in city.buildings:
		if not String(building["poi"]).is_empty():
			_draw_poi_marker(building)
	_draw_boundary()


func _draw_road_cell(x: int, y: int, tile: String) -> void:
	var cs := cell_size
	var p := Vector2(x, y) * cs
	var curb_width := 1.4 if tile == "R" else 1.0
	if not _is_road(x, y - 1):
		draw_line(p, p + Vector2(cs, 0.0), COL_CURB, curb_width)
	if not _is_road(x, y + 1):
		draw_line(p + Vector2(0.0, cs), p + Vector2(cs, cs), COL_CURB, curb_width)
	if not _is_road(x - 1, y):
		draw_line(p, p + Vector2(0.0, cs), COL_CURB, curb_width)
	if not _is_road(x + 1, y):
		draw_line(p + Vector2(cs, 0.0), p + Vector2(cs, cs), COL_CURB, curb_width)


func _draw_lane_markings() -> void:
	var cs := cell_size
	for y in city.height:
		for x in city.width:
			if city.get_tile(x, y) != "R":
				continue
			var left := _is_road(x - 1, y)
			var right := _is_road(x + 1, y)
			var up := _is_road(x, y - 1)
			var down := _is_road(x, y + 1)
			var horizontal := (left or right) and not (up or down)
			var vertical := (up or down) and not (left or right)
			if not horizontal and not vertical:
				continue
			var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * cs
			if horizontal:
				draw_line(
					center - Vector2(cs * 0.22, 0.0),
					center + Vector2(cs * 0.22, 0.0),
					Color(COL_LANE_MARK, 0.72), 1.2
				)
			else:
				draw_line(
					center - Vector2(0.0, cs * 0.22),
					center + Vector2(0.0, cs * 0.22),
					Color(COL_LANE_MARK, 0.72), 1.2
				)


func _draw_building(building: Dictionary) -> void:
	var cs := cell_size
	var x := int(building["x"])
	var y := int(building["y"])
	var w := int(building["w"])
	var h := int(building["h"])
	var px := float(x) * cs
	var py := float(y) * cs
	var body := Rect2(px + 1.2, py + 1.2, float(w) * cs - 2.4, float(h) * cs - 2.4)
	draw_rect(Rect2(body.position + Vector2(1.7, 1.7), body.size), Color(0.0, 0.0, 0.0, 0.32), true)
	var base := _building_color(building)
	draw_rect(body, base, true)
	draw_rect(body, base.lightened(0.34), false, 1.0)
	var roof := body.grow(-2.0)
	if roof.size.x > 2.0 and roof.size.y > 2.0:
		draw_rect(roof, base.darkened(0.10), true)
		draw_rect(roof, base.lightened(0.22), false, 0.8)
		# Small rooftop details make the blocks read as buildings, not tiles.
		var detail_count := mini(3, maxi(1, (w * h) / 3))
		for i in detail_count:
			var rx := _hash01(x, y, i * 3 + 1)
			var ry := _hash01(x, y, i * 3 + 2)
			var detail := Rect2(
				roof.position + Vector2(
					2.0 + rx * maxf(0.0, roof.size.x - 8.0),
					2.0 + ry * maxf(0.0, roof.size.y - 8.0)
				),
				Vector2(3.6, 3.0)
			)
			draw_rect(detail, base.lightened(0.12), true)
			draw_rect(detail, base.darkened(0.22), false, 0.7)


func _draw_tree(x: int, y: int) -> void:
	var cs := cell_size
	var jitter := Vector2(
		(_hash01(x, y, 11) - 0.5) * cs * 0.42,
		(_hash01(x, y, 23) - 0.5) * cs * 0.42
	)
	var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * cs + jitter
	var radius := cs * (0.13 + _hash01(x, y, 37) * 0.06)
	draw_circle(center + Vector2(0.8, 0.8), radius, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(center, radius, Color("#5d8b5d"))
	draw_circle(center - Vector2(radius * 0.25, radius * 0.25), radius * 0.55, Color("#78a870"))


func _draw_poi_marker(building: Dictionary) -> void:
	var cs := cell_size
	var center := Vector2(
		float(building["x"]) + float(building["w"]) * 0.5,
		float(building["y"]) + float(building["h"]) * 0.5
	) * cs
	var color := _label_color("poi", building["poi"])
	draw_circle(center, cs * 0.25, Color(0.04, 0.05, 0.07, 0.95))
	draw_circle(center, cs * 0.17, color)
	draw_circle(center, cs * 0.06, Color(0.04, 0.05, 0.07, 0.95))


func _draw_boundary() -> void:
	var cs := cell_size
	for y in city.height:
		for x in city.width:
			if not city.is_inside(x, y):
				continue
			var p := Vector2(x, y) * cs
			if not city.is_inside(x, y - 1):
				draw_line(p, p + Vector2(cs, 0.0), COL_BORDER, 3.0)
				draw_line(p, p + Vector2(cs, 0.0), COL_BORDER_GOLD, 1.0)
			if not city.is_inside(x, y + 1):
				draw_line(p + Vector2(0.0, cs), p + Vector2(cs, cs), COL_BORDER, 3.0)
				draw_line(p + Vector2(0.0, cs), p + Vector2(cs, cs), COL_BORDER_GOLD, 1.0)
			if not city.is_inside(x - 1, y):
				draw_line(p, p + Vector2(0.0, cs), COL_BORDER, 3.0)
				draw_line(p, p + Vector2(0.0, cs), COL_BORDER_GOLD, 1.0)
			if not city.is_inside(x + 1, y):
				draw_line(p + Vector2(cs, 0.0), p + Vector2(cs, cs), COL_BORDER, 3.0)
				draw_line(p + Vector2(cs, 0.0), p + Vector2(cs, cs), COL_BORDER_GOLD, 1.0)


func _building_color(building: Dictionary) -> Color:
	var zone := int(building["zone"])
	var base: Color
	match zone:
		1:
			base = Color("#4f7f9e")
		2:
			base = Color("#8b8062")
		3:
			base = Color("#6e5a7d")
		_:
			base = Color("#b07a5f")
	var poi := String(building["poi"])
	if not poi.is_empty():
		match poi:
			"hospital":
				base = Color("#b85f63")
			"fire":
				base = Color("#b06a44")
			"police":
				base = Color("#4d6f9f")
			"school":
				base = Color("#9b874c")
			"city_hall":
				base = Color("#80659b")
	var variant := (_hash01(int(building["x"]), int(building["y"]), 7) - 0.5) * 0.17
	if variant >= 0.0:
		return base.lightened(variant)
	return base.darkened(-variant)


func _is_road(x: int, y: int) -> bool:
	var tile: String = city.get_tile(x, y)
	return tile == "R" or tile == "r"


func _hash01(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = absi(h)
	return float(h % 1000) / 1000.0
