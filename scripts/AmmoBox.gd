class_name AmmoBox
extends Area3D

## Dead Run - Tactical Ammo Box (Godot 4.3 - Grounded Military Prop)
## Caixa de suprimentos militar verde-oliva (#2d3829) assentada no asfalto (altura < 0.4m).
## Coleta discreta no chão com sinalizador baixo sem rotação flutuante.

signal collected(ammo_amount: int)

@export var ammo_amount: int = 6
var is_active: bool = false
var road_speed: float = 10.5

var box_mesh: MeshInstance3D = null
var beacon_light: OmniLight3D = null
var collision_shape: CollisionShape3D = null


func _ready() -> void:
	collision_layer = 8 # Itens / Coletáveis
	collision_mask = 2  # Detecta o Jogador
	
	_setup_nodes()
	body_entered.connect(_on_body_entered)


func _setup_nodes() -> void:
	# Colisor amplo o suficiente para coleta suave enquanto corre
	collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 0.6, 1.2)
		collision_shape.shape = box
		collision_shape.position = Vector3(0.0, 0.3, 0.0)
		add_child(collision_shape)

	# Modelo 3D de caixa de munição militar pequena no chão (altura 0.22m, max 0.4m)
	box_mesh = get_node_or_null("BoxMesh") as MeshInstance3D
	if not box_mesh:
		box_mesh = MeshInstance3D.new()
		box_mesh.name = "BoxMesh"
		var mesh := BoxMesh.new()
		# Dimensões realistas de caixa metálica 9mm (0.45m larg x 0.22m alt x 0.32m prof)
		mesh.size = Vector3(0.45, 0.22, 0.32)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#2d3829") # Verde-oliva militar
		mat.metallic = 0.35
		mat.roughness = 0.72
		mesh.material = mat
		box_mesh.mesh = mesh
		# Centro em Y=0.11m garante a base exatamente encostada no asfalto em Y=0.0
		box_mesh.position = Vector3(0.0, 0.11, 0.0)
		add_child(box_mesh)

	# Sinalizador luminoso baixo e discreto no asfalto (sem clarão exagerado)
	beacon_light = get_node_or_null("BeaconLight") as OmniLight3D
	if not beacon_light:
		beacon_light = OmniLight3D.new()
		beacon_light.name = "BeaconLight"
		beacon_light.position = Vector3(0.0, 0.22, 0.0)
		beacon_light.light_color = Color(0.85, 0.38, 0.18) # Âmbar militar sóbrio
		beacon_light.omni_range = 2.2
		beacon_light.light_energy = 0.65
		beacon_light.shadow_enabled = false # Otimizado para Web / Playgama
		add_child(beacon_light)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	# Acompanha o scroll da esteira da rodovia
	if is_inside_tree():
		global_position.z += road_speed * delta
	else:
		position.z += road_speed * delta


func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return

	var player = body as Player
	if not player and body.is_in_group("player"):
		player = body as Player

	if player:
		if player.weapon_manager and player.weapon_manager.has_method("add_ammo"):
			player.weapon_manager.add_ammo(ammo_amount)
		collected.emit(ammo_amount)
		deactivate()


func activate(spawn_pos: Vector3, new_road_speed: float) -> void:
	# Garante que assente exatamente no nível da pista Y = 0.0
	var grounded_pos = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	if is_inside_tree():
		global_position = grounded_pos
	else:
		position = grounded_pos

	road_speed = new_road_speed
	visible = true
	is_active = true
	if collision_shape:
		collision_shape.disabled = false


func deactivate() -> void:
	is_active = false
	visible = false
	if collision_shape:
		collision_shape.disabled = true
