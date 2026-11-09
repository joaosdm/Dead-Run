class_name MilitaryBarricade
extends StaticBody3D

## Dead Run - Barricada Militar Dinâmica (Godot 4.3)
## Suporta 3 variantes táticas para dinamismo de corrida:
## 0 = FULL_BLOCK (Bloqueio pesado completo - exige esquiva lateral)
## 1 = LOW_VAULT (Barreira baixa de concreto/arame - permite PULAR por cima com [ESPAÇO]!)
## 2 = HIGH_SLIDE (Pórtico/placa caída com espaço embaixo - permite DESLIZAR por baixo com [SHIFT]!)

enum BarricadeType {
	FULL_BLOCK = 0,
	LOW_VAULT = 1,
	HIGH_SLIDE = 2
}

var barricade_type: BarricadeType = BarricadeType.FULL_BLOCK
var is_active: bool = false
var has_hit_player: bool = false
var beacon_mesh: MeshInstance3D = null
var beacon_mat: StandardMaterial3D = null
var action_hint_label: Label3D = null
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_mesh: Node3D = $VisualMesh


func _ready() -> void:
	add_to_group("obstacles")
	collision_layer = 1
	collision_mask = 2
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not visual_mesh:
		visual_mesh = get_node_or_null("VisualMesh") as Node3D
	_setup_tactical_beacon()


func _setup_tactical_beacon() -> void:
	beacon_mesh = MeshInstance3D.new()
	beacon_mesh.name = "HazardBeaconMesh"
	var b_box := BoxMesh.new()
	b_box.size = Vector3(1.6, 0.14, 0.22)
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = Color(1.0, 0.55, 0.08)
	b_box.material = beacon_mat
	beacon_mesh.mesh = b_box
	beacon_mesh.position = Vector3(0.0, 1.15, 0.0)
	add_child(beacon_mesh)

	action_hint_label = Label3D.new()
	action_hint_label.name = "ActionHint3D"
	action_hint_label.position = Vector3(0.0, 2.1, 0.0)
	action_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	action_hint_label.font_size = 42
	action_hint_label.outline_size = 10
	action_hint_label.modulate = Color(1.0, 0.9, 0.25, 0.92)
	action_hint_label.visible = false
	add_child(action_hint_label)


func activate(pos: Vector3, rot_y_deg: float = 0.0, forced_type: int = -1) -> void:
	is_active = true
	has_hit_player = false
	visible = true
	global_position = pos
	rotation_degrees.y = rot_y_deg

	if forced_type >= 0 and forced_type <= 2:
		barricade_type = forced_type as BarricadeType
	else:
		var r := randf()
		if r < 0.38:
			barricade_type = BarricadeType.LOW_VAULT
		elif r < 0.72:
			barricade_type = BarricadeType.HIGH_SLIDE
		else:
			barricade_type = BarricadeType.FULL_BLOCK

	_configure_geometry_for_type()

	if collision_shape:
		collision_shape.set_deferred("disabled", false)


func _configure_geometry_for_type() -> void:
	var box := collision_shape.shape as BoxShape3D if collision_shape else null
	if box and box.resource_local_to_scene == false:
		box = box.duplicate() as BoxShape3D
		collision_shape.shape = box

	var concrete := visual_mesh.get_node_or_null("ConcreteBase") as MeshInstance3D if visual_mesh else null
	var stripe := visual_mesh.get_node_or_null("HazardStripe") as MeshInstance3D if visual_mesh else null
	var wire_top := visual_mesh.get_node_or_null("BarbedWireTop") as MeshInstance3D if visual_mesh else null
	var wire_mid := visual_mesh.get_node_or_null("BarbedWireMid") as MeshInstance3D if visual_mesh else null

	match barricade_type:
		BarricadeType.LOW_VAULT:
			# Barreira baixa (0.75m de altura): Jogador pode PULAR por cima!
			if box:
				box.size = Vector3(4.2, 0.75, 0.8)
				collision_shape.position = Vector3(0.0, 0.375, 0.0)
			if concrete:
				concrete.position.y = 0.35
				concrete.scale.y = 0.75
			if stripe:
				stripe.position.y = 0.52
			if wire_top:
				wire_top.visible = false
			if wire_mid:
				wire_mid.visible = false
			if beacon_mat:
				beacon_mat.albedo_color = Color(0.2, 1.0, 0.45) # Verde tático (Saltável)
			if beacon_mesh:
				beacon_mesh.position.y = 0.85
			if action_hint_label:
				action_hint_label.visible = true
				action_hint_label.text = "[ESPAÇO] SALTAR"
				action_hint_label.modulate = Color(0.3, 1.0, 0.5, 0.9)
				action_hint_label.position.y = 1.45

		BarricadeType.HIGH_SLIDE:
			# Viga/Placa suspensa (vão livre de 0.0m a 1.05m): Jogador pode DESLIZAR [SHIFT] por baixo!
			if box:
				box.size = Vector3(4.2, 0.9, 0.8)
				collision_shape.position = Vector3(0.0, 1.55, 0.0)
			if concrete:
				concrete.position.y = 1.55
				concrete.scale.y = 0.65
			if stripe:
				stripe.position.y = 1.32
			if wire_top:
				wire_top.visible = true
				wire_top.position.y = 1.95
			if wire_mid:
				wire_mid.visible = false
			if beacon_mat:
				beacon_mat.albedo_color = Color(0.15, 0.75, 1.0) # Ciano tático (Slide)
			if beacon_mesh:
				beacon_mesh.position.y = 1.25
			if action_hint_label:
				action_hint_label.visible = true
				action_hint_label.text = "[SHIFT] DESLIZAR"
				action_hint_label.modulate = Color(0.25, 0.85, 1.0, 0.9)
				action_hint_label.position.y = 2.25

		BarricadeType.FULL_BLOCK:
			# Bloqueio total (1.45m de altura): Exige desvio de faixa
			if box:
				box.size = Vector3(4.2, 1.45, 0.8)
				collision_shape.position = Vector3(0.0, 0.725, 0.0)
			if concrete:
				concrete.position.y = 0.45
				concrete.scale.y = 1.0
			if stripe:
				stripe.position.y = 0.6
			if wire_top:
				wire_top.visible = true
				wire_top.position.y = 1.15
			if wire_mid:
				wire_mid.visible = true
				wire_mid.position.y = 1.3
			if beacon_mat:
				beacon_mat.albedo_color = Color(1.0, 0.35, 0.1) # Laranja/Vermelho (Bloqueio)
			if beacon_mesh:
				beacon_mesh.position.y = 1.35
			if action_hint_label:
				action_hint_label.visible = false


func deactivate() -> void:
	is_active = false
	visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if action_hint_label:
		action_hint_label.visible = false
	global_position = Vector3(0.0, -100.0, 0.0)
