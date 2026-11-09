class_name OilSlick
extends Area3D

## Dead Run - Mancha de Óleo Diesel (Godot 4.3 - Obstáculo de Derrapagem)
## Poça escura viscosa e iridescente no asfalto (Y = 0.01m).
## Quando o jogador pisa, reduz o atrito lateral causando deslize/derrapagem inercial por 1.6s.

var is_active: bool = true
var road_speed: float = 10.5
var has_slipped_player: bool = false

var visual_mesh: MeshInstance3D = null
var collision_shape: CollisionShape3D = null

static var shared_oil_material: StandardMaterial3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2 # Jogador
	_setup_components()
	body_entered.connect(_on_body_entered)


func _setup_components() -> void:
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.65
			cyl.height = 0.35
			collision_shape.shape = cyl
			collision_shape.position = Vector3(0.0, 0.175, 0.0)
			add_child(collision_shape)

	if not visual_mesh:
		visual_mesh = get_node_or_null("SlickMesh") as MeshInstance3D
		if not visual_mesh:
			visual_mesh = MeshInstance3D.new()
			visual_mesh.name = "SlickMesh"
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.65
			mesh.bottom_radius = 1.75
			mesh.height = 0.02
			mesh.radial_segments = 12
			visual_mesh.mesh = mesh
			visual_mesh.position = Vector3(0.0, 0.01, 0.0)
			
			if not shared_oil_material:
				shared_oil_material = StandardMaterial3D.new()
				shared_oil_material.albedo_color = Color(0.015, 0.018, 0.022, 0.92) # Preto piche profundo
				shared_oil_material.metallic = 0.88
				shared_oil_material.roughness = 0.04 # Altamente reflexivo / molhado
				shared_oil_material.rim_enabled = true
				shared_oil_material.rim = 0.5
				shared_oil_material.rim_tint = 0.8
			
			visual_mesh.material_override = shared_oil_material
			add_child(visual_mesh)


func activate(spawn_pos: Vector3, new_road_speed: float) -> void:
	global_position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	road_speed = new_road_speed
	is_active = true
	visible = true
	has_slipped_player = false
	if collision_shape:
		collision_shape.disabled = false


func deactivate() -> void:
	is_active = false
	visible = false
	if collision_shape:
		collision_shape.disabled = true
	global_position = Vector3(0.0, -100.0, 0.0)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	global_position.z += road_speed * delta


func _on_body_entered(body: Node3D) -> void:
	if not is_active or has_slipped_player:
		return
	var player = body as Player
	if not player and body.is_in_group("player"):
		player = body as Player
	if player and player.has_method("trigger_oil_slip"):
		has_slipped_player = true
		player.trigger_oil_slip(1.6)
