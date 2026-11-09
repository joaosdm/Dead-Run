class_name CarWreck
extends StaticBody3D

## Dead Run - Car Wreck & Obstacle Entity (Godot 4.3)
## Representa carcaças de veículos, destroços e obstáculos na rodovia.
## Suporta pooling, colisão física, movimento de pista e reação a tiros/impactos.

signal destroyed(obstacle: CarWreck)

enum ObstacleType { CAR_WRECK, BURNING_TRUCK, CONCRETE_BARRIER, EXPLOSIVE_BARREL }

@export var obstacle_type: ObstacleType = ObstacleType.CAR_WRECK
@export var damage_to_player: float = 30.0
@export var health: float = 60.0
@export var is_destructible: bool = true

var is_active: bool = false
var collision_shape: CollisionShape3D = null
var visual_mesh: Node3D = null


func _ready() -> void:
	_setup_nodes()


func _setup_nodes() -> void:
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.2, 1.4, 4.2)
			collision_shape.shape = box
			collision_shape.position = Vector3(0, 0.7, 0)
			add_child(collision_shape)
			
	if not visual_mesh:
		visual_mesh = get_node_or_null("Visual")
		if not visual_mesh:
			_build_procedural_car_mesh()


## Criação de carcaça 3D procedural estilizada caso não haja malha externa
func _build_procedural_car_mesh() -> void:
	visual_mesh = Node3D.new()
	visual_mesh.name = "Visual"
	add_child(visual_mesh)
	
	# Material metálico enferrujado / queimado
	var rust_mat := StandardMaterial3D.new()
	rust_mat.albedo_color = Color(0.25, 0.16, 0.12)
	rust_mat.metallic = 0.5
	rust_mat.roughness = 0.85
	
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.1, 0.12, 0.14)
	glass_mat.metallic = 0.9
	glass_mat.roughness = 0.2
	
	# Chassi do carro
	var chassis := MeshInstance3D.new()
	var chassis_box := BoxMesh.new()
	chassis_box.size = Vector3(2.1, 0.7, 4.0)
	chassis_box.material = rust_mat
	chassis.mesh = chassis_box
	chassis.position = Vector3(0, 0.45, 0)
	visual_mesh.add_child(chassis)
	
	# Cabine / Teto amassado
	var cabin := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(1.7, 0.65, 2.2)
	cabin_box.material = rust_mat
	cabin.mesh = cabin_box
	cabin.position = Vector3(0, 1.05, -0.2)
	visual_mesh.add_child(cabin)
	
	# Rodas queimadas/destruídas
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.08)
	wheel_mat.roughness = 0.95
	
	var wheel_coords := [
		Vector3(-1.05, 0.35, 1.2),
		Vector3(1.05, 0.35, 1.2),
		Vector3(-1.05, 0.35, -1.2),
		Vector3(1.05, 0.35, -1.2),
	]
	
	for coord in wheel_coords:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.36
		cyl.bottom_radius = 0.36
		cyl.height = 0.25
		cyl.material = wheel_mat
		wheel.mesh = cyl
		wheel.rotation.z = deg_to_rad(90.0)
		wheel.position = coord
		visual_mesh.add_child(wheel)


## Ativação e configuração do pool
func activate(spawn_pos: Vector3, type: ObstacleType = ObstacleType.CAR_WRECK) -> void:
	global_position = spawn_pos
	obstacle_type = type
	is_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	
	if collision_shape:
		collision_shape.disabled = false
		
	# Inclinação aleatória de carro batido / capotado
	if visual_mesh:
		visual_mesh.rotation = Vector3.ZERO
		var tilt_y: float = randf_range(-0.15, 0.15)
		var tilt_z: float = randf_range(-0.06, 0.06)
		visual_mesh.rotation = Vector3(0.0, tilt_y, tilt_z)
		
	health = 80.0


## Desativação e retorno ao pool
func deactivate() -> void:
	visible = false
	is_active = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if collision_shape:
		collision_shape.disabled = true


## Movimento com a pista em direção ao jogador (+Z)
func tick_movement(delta: float, road_speed: float) -> void:
	if not is_active:
		return
	global_position.z += road_speed * delta


## Reação a tiros
func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO, _hit_normal: Vector3 = Vector3.ZERO) -> void:
	if not is_active or not is_destructible:
		return
		
	health -= amount
	if health <= 0.0:
		explode_or_break()


func explode_or_break() -> void:
	is_active = false
	destroyed.emit(self)
	deactivate()
