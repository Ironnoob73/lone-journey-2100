@tool
extends MeshInstance3D

## 低多边形头颅网格：球体 ↔ 带倒角的正立方体。
##
## 立方体端点采用“先内缩、再补倒角”的构造：
##   - 六个正方形面内缩 bevel_width；
##   - 12 条棱用四分之一圆弧连接，圆弧分成 bevel_steps 段；
##   - 8 个角用球面三角补片连接。
## bevel_steps = 1 时是单段平直倒角，2 段/3 段逐渐接近圆角，与 bevel1~3.obj 一致。
##
## 网格支持平面着色和平滑着色：
##   flat_shading = true  ：每个三角形独立法线，棱面清晰；
##   flat_shading = false ：共享顶点，法线按面积加权平均。
##
## 三角形数量：
##   2 × (6 × segments² + 12 × segments × bevel_steps)   （面和棱的四边形）
##   + 8 × (bevel_steps == 1 ? 1 : 3 × bevel_steps)       （角补片）
## 参考参数 width = 0.1、steps = 1、segments = 3：
##   188 个三角形；平滑着色 96 个顶点，平面着色 564 个渲染顶点。

## 立方体面的定义：[法线轴, 法线方向, 切线 A 轴, 切线 B 轴]。
## 切线 A × 切线 B 必须等于法线方向。
const _FACES: Array = [
	[0, 1, 1, 2],   # +X
	[0, -1, 2, 1],  # -X
	[1, 1, 2, 0],   # +Y
	[1, -1, 0, 2],  # -Y
	[2, 1, 0, 1],   # +Z
	[2, -1, 1, 0],  # -Z
]

## 极小三角形视为退化并跳过。
const _AREA_EPSILON := 0.00000000000000000001


## 收集顶点和三角形的临时数据。顶点按位置焊接，便于棱、角和面共享边界。
class BevelBuilder:
	const WELD_SCALE := 100000.0

	var positions := PackedVector3Array()
	var lookup := {}
	var triangles: Array[Vector3i] = []

	func vertex(p: Vector3) -> int:
		var key := Vector3i(
			roundi(p.x * WELD_SCALE),
			roundi(p.y * WELD_SCALE),
			roundi(p.z * WELD_SCALE)
		)
		if lookup.has(key):
			return int(lookup[key])
		var index := positions.size()
		positions.push_back(p)
		lookup[key] = index
		return index

	func triangle(a: int, b: int, c: int) -> void:
		triangles.append(Vector3i(a, b, c))


## 0 = 球体，1 = 正立方体（即 0% ~ 100%）。
@export_range(0.0, 1.0, 0.01) var cube_ratio: float = 0.55:
	set(value):
		cube_ratio = clampf(value, 0.0, 1.0)
		_rebuild()

## 倒角宽度（相对于立方体半边长的 0~0.5）。
## 0 为完全尖锐的立方体；0.1、0.25 分别对应参考模型的宽度。
@export_range(0.0, 0.5, 0.01) var bevel_width: float = 0.1:
	set(value):
		bevel_width = clampf(value, 0.0, 0.5)
		_rebuild()

## 倒角次数（圆弧分段数），1 为单段平直倒角，越大越接近圆角。
@export_range(1, 6, 1) var bevel_steps: int = 1:
	set(value):
		bevel_steps = clampi(value, 1, 6)
		_rebuild()

## 每个正方形面的细分数。参考模型使用 3。
@export_range(2, 6, 1) var segments: int = 3:
	set(value):
		segments = clampi(value, 2, 6)
		_rebuild()

## 头颅半径（整体缩放）。
@export_range(0.05, 2.0, 0.01, "suffix:m") var head_radius: float = 0.5:
	set(value):
		head_radius = maxf(value, 0.001)
		_rebuild()

## true = 平面着色（低多边形棱面）；false = 平滑着色。
@export var flat_shading: bool = true:
	set(value):
		flat_shading = value
		_rebuild()

func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	var n := segments
	var steps := bevel_steps
	var width := bevel_width
	var inner := 1.0 - width

	var data := BevelBuilder.new()
	_build_faces(data, n, inner)
	if width > 0.000001:
		_build_edges(data, n, inner, width, steps)
		_build_corners(data, inner, width, steps)

	var head_mesh := ArrayMesh.new()
	head_mesh.resource_name = "LowPolyHead"
	if flat_shading:
		_build_flat_surface(head_mesh, data)
	else:
		_build_smooth_surface(head_mesh, data)

	#if head_mesh.get_surface_count() > 0 and head_material != null:
	#	head_mesh.surface_set_material(0, head_material)
	mesh = head_mesh


## 六个正方形面：位于平面 ±1 上，范围为 [-inner, inner]²。
func _build_faces(data: BevelBuilder, n: int, inner: float) -> void:
	for face in _FACES:
		var normal_axis: int = face[0]
		var normal_sign: int = face[1]
		var axis_a: int = face[2]
		var axis_b: int = face[3]

		for i in range(n):
			for j in range(n):
				var p00 := _face_point(normal_axis, normal_sign, axis_a, axis_b, i, j, n, inner)
				var p10 := _face_point(normal_axis, normal_sign, axis_a, axis_b, i + 1, j, n, inner)
				var p11 := _face_point(normal_axis, normal_sign, axis_a, axis_b, i + 1, j + 1, n, inner)
				var p01 := _face_point(normal_axis, normal_sign, axis_a, axis_b, i, j + 1, n, inner)

				var i00 := data.vertex(p00)
				var i10 := data.vertex(p10)
				var i11 := data.vertex(p11)
				var i01 := data.vertex(p01)
				data.triangle(i00, i10, i11)
				data.triangle(i00, i11, i01)


func _face_point(normal_axis: int, normal_sign: int, axis_a: int, axis_b: int, i: int, j: int, n: int, inner: float) -> Vector3:
	var p := Vector3.ZERO
	p[normal_axis] = float(normal_sign)
	p[axis_a] = -inner + 2.0 * inner * float(i) / float(n)
	p[axis_b] = -inner + 2.0 * inner * float(j) / float(n)
	return p


## 12 条棱：每条棱是一个四分之一圆柱面，沿棱方向分成 n 段，圆弧分成 steps 段。
func _build_edges(data: BevelBuilder, n: int, inner: float, width: float, steps: int) -> void:
	for along_axis in range(3):
		var axis_u := (along_axis + 1) % 3
		var axis_v := (along_axis + 2) % 3
		for sign_u in [-1, 1]:
			for sign_v in [-1, 1]:
				for i in range(n):
					for k in range(steps):
						var p00 := _edge_point(along_axis, axis_u, axis_v, sign_u, sign_v, i, k, n, inner, width, steps)
						var p10 := _edge_point(along_axis, axis_u, axis_v, sign_u, sign_v, i + 1, k, n, inner, width, steps)
						var p11 := _edge_point(along_axis, axis_u, axis_v, sign_u, sign_v, i + 1, k + 1, n, inner, width, steps)
						var p01 := _edge_point(along_axis, axis_u, axis_v, sign_u, sign_v, i, k + 1, n, inner, width, steps)

						var i00 := data.vertex(p00)
						var i10 := data.vertex(p10)
						var i11 := data.vertex(p11)
						var i01 := data.vertex(p01)
						data.triangle(i00, i10, i11)
						data.triangle(i00, i11, i01)


func _edge_point(along_axis: int, axis_u: int, axis_v: int, sign_u: int, sign_v: int, i: int, k: int, n: int, inner: float, width: float, steps: int) -> Vector3:
	var theta := PI * 0.5 * float(k) / float(steps)
	var p := Vector3.ZERO
	p[along_axis] = -inner + 2.0 * inner * float(i) / float(n)
	p[axis_u] = float(sign_u) * (inner + width * cos(theta))
	p[axis_v] = float(sign_v) * (inner + width * sin(theta))
	return p


## 8 个角：三个棱的圆弧端点组成球面三角形，用中心扇形补片填充。
func _build_corners(data: BevelBuilder, inner: float, width: float, steps: int) -> void:
	for sign_x in [-1, 1]:
		for sign_y in [-1, 1]:
			for sign_z in [-1, 1]:
				var loop: Array[int] = []

				for k in range(steps + 1):
					loop.append(data.vertex(_corner_arc_point(0, sign_x, sign_y, sign_z, k, inner, width, steps)))
				for k in range(1, steps + 1):
					loop.append(data.vertex(_corner_arc_point(1, sign_x, sign_y, sign_z, k, inner, width, steps)))
				for k in range(1, steps):
					loop.append(data.vertex(_corner_arc_point(2, sign_x, sign_y, sign_z, k, inner, width, steps)))

				if steps == 1:
					data.triangle(loop[0], loop[1], loop[2])
					continue

				var center := Vector3(float(sign_x), float(sign_y), float(sign_z)).normalized() * width
				center += Vector3(float(sign_x) * inner, float(sign_y) * inner, float(sign_z) * inner)
				var center_index := data.vertex(center)

				for i in range(loop.size()):
					data.triangle(center_index, loop[i], loop[(i + 1) % loop.size()])


## 取角上某条棱圆弧的第 k 个点。
## edge_axis = 0/1/2 分别对应沿 X/Y/Z 的棱。
func _corner_arc_point(edge_axis: int, sign_x: int, sign_y: int, sign_z: int, k: int, inner: float, width: float, steps: int) -> Vector3:
	var theta := PI * 0.5 * float(k) / float(steps)
	var c := cos(theta)
	var s := sin(theta)
	var p := Vector3.ZERO
	if edge_axis == 0:
		p.x = float(sign_x) * inner
		p.y = float(sign_y) * (inner + width * c)
		p.z = float(sign_z) * (inner + width * s)
	elif edge_axis == 1:
		p.y = float(sign_y) * inner
		p.z = float(sign_z) * (inner + width * c)
		p.x = float(sign_x) * (inner + width * s)
	else:
		p.z = float(sign_z) * inner
		p.x = float(sign_x) * (inner + width * c)
		p.y = float(sign_y) * (inner + width * s)
	return p


## 平面着色：每个三角形拆分顶点并使用独立法线。
func _build_flat_surface(head_mesh: ArrayMesh, data: BevelBuilder) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	for tri in data.triangles:
		var a := _shape_point(data.positions[tri.x])
		var b := _shape_point(data.positions[tri.y])
		var c := _shape_point(data.positions[tri.z])
		_append_flat_triangle(verts, normals, a, b, c)

	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## 平滑着色：共享顶点，法线按面积加权平均。
func _build_smooth_surface(head_mesh: ArrayMesh, data: BevelBuilder) -> void:
	var shaped := PackedVector3Array()
	shaped.resize(data.positions.size())
	for i in range(data.positions.size()):
		shaped[i] = _shape_point(data.positions[i])

	var used := {}
	var valid: Array[Vector3i] = []
	for tri in data.triangles:
		if tri.x == tri.y or tri.y == tri.z or tri.x == tri.z:
			continue
		var a := shaped[tri.x]
		var b := shaped[tri.y]
		var c := shaped[tri.z]
		if (b - a).cross(c - a).length_squared() <= _AREA_EPSILON:
			continue
		valid.append(tri)
		used[tri.x] = true
		used[tri.y] = true
		used[tri.z] = true

	if valid.is_empty():
		return

	var remap := {}
	var verts := PackedVector3Array()
	for old_index in range(data.positions.size()):
		if used.has(old_index):
			remap[old_index] = verts.size()
			verts.push_back(shaped[old_index])

	var accumulated := PackedVector3Array()
	accumulated.resize(verts.size())
	var indices := PackedInt32Array()
	for tri in valid:
		_append_smooth_triangle(accumulated, indices, verts, remap[tri.x], remap[tri.y], remap[tri.z])

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(verts.size()):
		var normal := accumulated[i]
		if normal.length_squared() > 0.0:
			normals[i] = normal.normalized()
		else:
			normals[i] = verts[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## 立方体切角位置 -> 球体/立方体混合后的最终位置。
func _shape_point(beveled: Vector3) -> Vector3:
	var sphere := beveled.normalized()
	return sphere.lerp(beveled, cube_ratio) * head_radius


## 追加一个平面着色三角形。输入三点；输出时反转成 Godot 使用的顺时针正面顺序，
## 法线保持朝外。
func _append_flat_triangle(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() <= _AREA_EPSILON:
		return
	normal = normal.normalized()

	if normal.dot(a + b + c) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal

	verts.push_back(a)
	verts.push_back(c)
	verts.push_back(b)
	normals.push_back(normal)
	normals.push_back(normal)
	normals.push_back(normal)


## 累加平滑着色三角形的面积加权法线，并写入顺时针索引。
func _append_smooth_triangle(accumulated: PackedVector3Array, indices: PackedInt32Array, positions: PackedVector3Array, ia: int, ib: int, ic: int) -> void:
	var a := positions[ia]
	var b := positions[ib]
	var c := positions[ic]
	var normal := (b - a).cross(c - a)
	if normal.length_squared() <= _AREA_EPSILON:
		return

	if normal.dot(a + b + c) < 0.0:
		var swap := ib
		ib = ic
		ic = swap
		normal = -normal

	accumulated[ia] += normal
	accumulated[ib] += normal
	accumulated[ic] += normal

	indices.push_back(ia)
	indices.push_back(ic)
	indices.push_back(ib)
