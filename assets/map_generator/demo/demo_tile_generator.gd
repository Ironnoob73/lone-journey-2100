extends Node2D

## Source: https://github.com/GarnetKane99/WaveFunctionCollapse/tree/main
## Tile image from: https://kenney.nl/assets/minimap-pack

@export var length: int = 16
@export var height: int = 16
@export var tile_objects: Array[DemoTile]
@export var failed_tile: DemoTile
var grid_components: Array[DemoCell]
var iterations: int = 0

@onready var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	for y in height:
		for x in length:
			var new_cell: DemoCell = DemoCell.new()
			add_child(new_cell)
			new_cell.scale *= 5
			new_cell.position = Vector2(x * 40, y * 40) + Vector2(40, 40)
			new_cell.tile_options.append_array(tile_objects)
			new_cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
			grid_components.append(new_cell)
	check_entropy()

func check_entropy() -> void:
	var temp_grid: Array = grid_components.filter(
		func(cell: DemoCell) -> bool:
			return not cell.collapsed
			).duplicate()
	#print(temp_grid.size())
	temp_grid.sort_custom(
		func(a: DemoCell, b: DemoCell) -> bool:
			return calculate_entropy_value(a) - calculate_entropy_value(b) < 0
	)
	var arr_length: int = temp_grid[0].tile_options.size()
	#print(arr_length)
	var stop_index: int
	for i in temp_grid.size():
		if temp_grid[i].tile_options.size() > arr_length:
			stop_index = i
			break
	if stop_index > 0:
		temp_grid.resize(stop_index)
	await get_tree().create_timer(0.01).timeout
	collapse_cell(temp_grid)

func calculate_entropy_value(cell: DemoCell) -> float:
	var denominator: float = 0
	for option in cell.tile_options:
		denominator += option.weight
	var entropy_value: float = 0
	for option in cell.tile_options:
		entropy_value -= (option.weight / denominator) * log(option.weight / denominator) / log(2)
	return entropy_value

func collapse_cell(temp_grid_components: Array[DemoCell]) -> void:
	var rand_index: int = rng.randi_range(0, temp_grid_components.size() - 1)
	var cell_to_collapse: DemoCell = temp_grid_components[rand_index]
	cell_to_collapse.collapsed = true
	var selected_tile: DemoTile
	if cell_to_collapse.tile_options.size() == 0:
		selected_tile = failed_tile
	else:
		var weights: Array[float]
		for option in cell_to_collapse.tile_options:
			weights.append(option.weight)
		selected_tile = cell_to_collapse.tile_options[rng.rand_weighted(weights)]
	cell_to_collapse.tile_options.clear()
	cell_to_collapse.tile_options.append(selected_tile)
	cell_to_collapse.texture = selected_tile.appearance
	update_generation()

func update_generation() -> void:
	var new_generation_cell: Array[DemoCell] = grid_components.duplicate()
	for y in height:
		for x in length:
			var index: int = x + (y * length)
			if grid_components[index].collapsed:
				new_generation_cell[index] = grid_components[index]
			else:
				var options: Array[DemoTile] = tile_objects.duplicate()
				# update above
				if y > 0:
					var up: DemoCell = grid_components[x + ((y-1) * length)]
					var valid_options: Array[DemoTile]
					for listed_option in up.tile_options:
						if listed_option.down.size() == 0:
							for possible_option in tile_objects:
								if (possible_option.up.size() == 0
								and not valid_options.has(possible_option)):
									#valid_options.append(possible_option)
									if possible_option.family == listed_option.family:
										valid_options.append(possible_option)
						else:
							for plug in listed_option.down:
								for possible_option in tile_objects:
									if (possible_option.up.size() != 0 
									and possible_option.up.has(plug) 
									and not valid_options.has(possible_option)):
										#valid_options.append(possible_option)
										if plug == listed_option.family and possible_option.family == listed_option.family:
											valid_options.append(possible_option)
										if plug != listed_option.family and possible_option.family != listed_option.family:
											valid_options.append(possible_option)
					options = check_validity(options, valid_options)
				# update below
				if y < height - 1:
					var down: DemoCell = grid_components[x + ((y+1) * length)]
					var valid_options: Array[DemoTile]
					for listed_option in down.tile_options:
						if listed_option.up.size() == 0:
							for possible_option in tile_objects:
								if (possible_option.down.size() == 0
								and not valid_options.has(possible_option)):
									#valid_options.append(possible_option)
									if possible_option.family == listed_option.family:
										valid_options.append(possible_option)
						else:
							for plug in listed_option.up:
								for possible_option in tile_objects:
									if (possible_option.down.size() != 0 
									and possible_option.down.has(plug) 
									and not valid_options.has(possible_option)):
										#valid_options.append(possible_option)
										if plug == listed_option.family and possible_option.family == listed_option.family:
											valid_options.append(possible_option)
										if plug != listed_option.family and possible_option.family != listed_option.family:
											valid_options.append(possible_option)
					options = check_validity(options, valid_options)
				# update left
				if x > 0:
					var left: DemoCell = grid_components[x - 1 + (y * length)]
					var valid_options: Array[DemoTile]
					for listed_option in left.tile_options:
						if listed_option.right.size() == 0:
							for possible_option in tile_objects:
								if (possible_option.left.size() == 0
								and not valid_options.has(possible_option)):
									#valid_options.append(possible_option)
									if possible_option.family == listed_option.family:
										valid_options.append(possible_option)
						else:
							for plug in listed_option.right:
								for possible_option in tile_objects:
									if (possible_option.left.size() != 0 
									and possible_option.left.has(plug) 
									and not valid_options.has(possible_option)):
										#valid_options.append(possible_option)
										if plug == listed_option.family and possible_option.family == listed_option.family:
											valid_options.append(possible_option)
										if plug != listed_option.family and possible_option.family != listed_option.family:
											valid_options.append(possible_option)
					options = check_validity(options, valid_options)
				# update right
				if x < length - 1:
					var right: DemoCell = grid_components[x + 1 + (y * length)]
					var valid_options: Array[DemoTile]
					for listed_option in right.tile_options:
						if listed_option.left.size() == 0:
							for possible_option in tile_objects:
								if (possible_option.right.size() == 0
								and not valid_options.has(possible_option)):
									#valid_options.append(possible_option)
									if possible_option.family == listed_option.family:
										valid_options.append(possible_option)
						else:
							for plug in listed_option.left:
								for possible_option in tile_objects:
									if (possible_option.right.size() != 0 
									and possible_option.right.has(plug) 
									and not valid_options.has(possible_option)):
										#valid_options.append(possible_option)
										if plug == listed_option.family and possible_option.family == listed_option.family:
											valid_options.append(possible_option)
										if plug != listed_option.family and possible_option.family != listed_option.family:
											valid_options.append(possible_option)
					options = check_validity(options, valid_options)
				#print(options.size())
				new_generation_cell[index].tile_options = options.duplicate()
	grid_components = new_generation_cell
	iterations += 1
	if iterations < length * height:
		#print(iterations,":",length * height)
		check_entropy()

func check_validity(tile_options: Array[DemoTile], valid_options: Array[DemoTile]) -> Array[DemoTile]:
	return tile_options.filter(
		func(tile: DemoTile) -> bool:
			return valid_options.has(tile)
	)
	#print(valid_options.size(),":",tile_options.size())
