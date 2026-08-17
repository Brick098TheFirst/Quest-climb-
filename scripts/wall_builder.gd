extends Node3D
## Procedurally builds the test wall:
##   - 15 m tall x 4 m wide plywood gym wall
##   - a floor / mat
##   - 6 quickdraws bolted in a staggered vertical line
##   - a route of colored holds linking the draws
##
## Everything is spawned from code so the main scene stays tiny.

const HoldScript := preload("res://scripts/hold.gd")
const QuickdrawScript := preload("res://scripts/quickdraw.gd")

@export var wall_width: float = 4.0
@export var wall_height: float = 15.0
@export var hold_scene: PackedScene = preload("res://scenes/hold.tscn")
@export var draw_scene: PackedScene = preload("res://scenes/quickdraw.tscn")

# Climbing route as (height_m, x_offset_m, difficulty 0..1).
# Start low, zig-zag up, end at an anchor near the top.
var ROUTE: Array = [
	[0.5, 0.0, 0.25],
	[1.2, 0.4, 0.30],
	[2.0, -0.3, 0.35],
	[2.8, 0.5, 0.40],
	[3.6, -0.4, 0.42],
	[4.5, 0.3, 0.45],
	[5.4, -0.2, 0.48],
	[6.3, 0.5, 0.50],
	[7.1, -0.5, 0.52],
	[8.0, 0.2, 0.55],
	[8.9, -0.3, 0.58],
	[9.8, 0.4, 0.60],
	[10.7, -0.2, 0.62],
	[11.6, 0.3, 0.65],
	[12.5, -0.4, 0.68],
	[13.4, 0.0, 0.72],
	[14.2, 0.0, 0.60],
	[14.6, 0.0, 0.30],  # anchor jug
]


func _ready() -> void:
	_build_wall()
	_build_floor()
	_build_draws()
	_build_route_holds()
	_build_extra_holds_for_feet()


func _build_wall() -> void:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(wall_width, wall_height, 0.3)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.70, 0.66)
	mat.roughness = 0.9
	mesh.material_override = mat
	wall.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	wall.add_child(col)
	wall.position = Vector3(0.0, wall_height * 0.5, -0.15)
	add_child(wall)


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.32)
	mat.roughness = 1.0
	mesh.material_override = mat
	floor_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := WorldBoundaryShape3D.new()
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position = Vector3(0.0, 0.0, 1.0)
	add_child(floor_body)


func _build_draws() -> void:
	var heights: Array[float] = [2.8, 5.0, 7.2, 9.4, 11.6, 13.8]
	for i in heights.size():
		var draw: Quickdraw = draw_scene.instantiate() as Quickdraw
		draw.draw_index = i
		# Stagger left-right.
		var x: float = 0.4 if i % 2 == 0 else -0.4
		draw.position = Vector3(x, heights[i], 0.0)
		add_child(draw)


func _build_route_holds() -> void:
	for entry in ROUTE:
		var h: Hold = hold_scene.instantiate() as Hold
		h.required_grip = entry[2]
		h.position = Vector3(entry[1], entry[0], 0.06)
		# Color by difficulty band - green = easy, yellow = mid, red = hard.
		if entry[2] < 0.4:
			h.hold_color = Color(0.25, 0.75, 0.35)
		elif entry[2] < 0.6:
			h.hold_color = Color(0.95, 0.85, 0.2)
		else:
			h.hold_color = Color(0.85, 0.25, 0.2)
		add_child(h)


func _build_extra_holds_for_feet() -> void:
	# Sprinkle neutral, easy foot-holds between the route holds so the player
	# has something to stand on. These aren't part of the "set" but make the
	# wall climbable.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 80:
		var h: Hold = hold_scene.instantiate() as Hold
		h.required_grip = 0.15  # feet don't need grip
		h.hold_color = Color(0.55, 0.55, 0.58)
		var y: float = rng.randf_range(0.5, wall_height - 0.5)
		var x: float = rng.randf_range(-wall_width * 0.45, wall_width * 0.45)
		h.position = Vector3(x, y, 0.05)
		h.scale = Vector3(0.6, 0.3, 0.5)
		add_child(h)
