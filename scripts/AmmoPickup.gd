class_name AmmoPickup
extends Area3D

## Dead Run - Tactical Drop & Pickup System (Godot 4.3 - Grounded Military Prop with Flare & Smoke)
## Caixa militar assentada no asfalto (Y = 0.125m) com suporte a 3 tipos:
## 1. MUNIÇÃO (Verde oliva + Sinalizador Vermelho) -> +8 Balas 9mm
## 2. KIT MÉDICO (Verde Tático/Branco + Sinalizador Esmeralda) -> +30 HP
## 3. ADRENALINA (Dourado/Âmbar + Sinalizador Âmbar) -> 4.5s Sprint Ilimitado + 15% Velocidade

signal collected(ammo_amount: int)

enum PickupType {
	AMMO = 0,
	MEDKIT = 1,
	ADRENALINE = 2
}

@export var pickup_type: PickupType = PickupType.AMMO
@export var ammo_amount: int = 8
var is_active: bool = true
var road_speed: float = 10.5
var light_pulse_time: float = 0.0

@export var box_mesh: MeshInstance3D
@export var flare_light: OmniLight3D
@export var smoke_particles: GPUParticles3D
@export var collision_shape: CollisionShape3D

var _box_mat: StandardMaterial3D = null
var _smoke_mat: ParticleProcessMaterial = null


func _ready() -> void:
	collision_layer = 8 # Coletáveis / Pickups
	collision_mask = 2  # Jogador
	
	_setup_components()
	_apply_visual_type()
	body_entered.connect(_on_body_entered)


func _setup_components() -> void:
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			var box := BoxShape3D.new()
			box.size = Vector3(1.4, 0.6, 1.4)
			collision_shape.shape = box
			collision_shape.position = Vector3(0.0, 0.3, 0.0)
			add_child(collision_shape)

	if not box_mesh:
		box_mesh = get_node_or_null("BoxMesh") as MeshInstance3D
		if not box_mesh:
			box_mesh = MeshInstance3D.new()
			box_mesh.name = "BoxMesh"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.5, 0.25, 0.35)
			box_mesh.mesh = mesh
			box_mesh.position = Vector3(0.0, 0.125, 0.0)
			add_child(box_mesh)

	# Assegura material independente para poder mudar cor dinamicamente
	if box_mesh:
		var existing_mat = box_mesh.get_surface_override_material(0) as StandardMaterial3D
		if not existing_mat and box_mesh.mesh and box_mesh.mesh is BoxMesh:
			existing_mat = (box_mesh.mesh as BoxMesh).material as StandardMaterial3D
		if existing_mat:
			_box_mat = existing_mat.duplicate() as StandardMaterial3D
		else:
			_box_mat = StandardMaterial3D.new()
		box_mesh.set_surface_override_material(0, _box_mat)

	if not flare_light:
		flare_light = get_node_or_null("FlareLight") as OmniLight3D
		if not flare_light:
			flare_light = OmniLight3D.new()
			flare_light.name = "FlareLight"
			flare_light.position = Vector3(0.0, 0.25, 0.0)
			flare_light.light_color = Color("#ff2211")
			flare_light.omni_range = 6.0
			flare_light.light_energy = 1.15
			flare_light.shadow_enabled = false
			add_child(flare_light)

	if not smoke_particles:
		smoke_particles = get_node_or_null("SmokeParticles") as GPUParticles3D
		if not smoke_particles:
			smoke_particles = GPUParticles3D.new()
			smoke_particles.name = "SmokeParticles"
			smoke_particles.position = Vector3(0.0, 0.25, 0.0)
			smoke_particles.amount = 26
			smoke_particles.lifetime = 1.4
			smoke_particles.explosiveness = 0.05
			
			var p_mat := ParticleProcessMaterial.new()
			p_mat.direction = Vector3(0.0, 1.0, 0.0)
			p_mat.spread = 4.0
			p_mat.initial_velocity_min = 1.9
			p_mat.initial_velocity_max = 2.4
			p_mat.gravity = Vector3(0.0, 0.2, 0.0)
			p_mat.scale_min = 0.06
			p_mat.scale_max = 0.22
			p_mat.color = Color(1.0, 0.15, 0.08, 0.32)
			smoke_particles.process_material = p_mat

			var quad := QuadMesh.new()
			quad.size = Vector2(0.3, 0.3)
			var s_mat := StandardMaterial3D.new()
			s_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
			s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			s_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.35)
			quad.material = s_mat
			smoke_particles.draw_pass_1 = quad
			add_child(smoke_particles)

	if smoke_particles and smoke_particles.process_material is ParticleProcessMaterial:
		_smoke_mat = (smoke_particles.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		smoke_particles.process_material = _smoke_mat


func _apply_visual_type() -> void:
	match pickup_type:
		PickupType.AMMO:
			if _box_mat:
				_box_mat.albedo_color = Color("#253022") # Verde militar escuro
				_box_mat.metallic = 0.45
				_box_mat.roughness = 0.65
			if flare_light:
				flare_light.light_color = Color(1.0, 0.14, 0.08)
			if _smoke_mat:
				_smoke_mat.color = Color(1.0, 0.15, 0.08, 0.35)
		PickupType.MEDKIT:
			if _box_mat:
				_box_mat.albedo_color = Color("#e0e8e2") # Branco/cinza tático médico
				_box_mat.metallic = 0.2
				_box_mat.roughness = 0.5
			if flare_light:
				flare_light.light_color = Color(0.0, 0.95, 0.45) # Verde esmeralda vivo
			if _smoke_mat:
				_smoke_mat.color = Color(0.0, 0.95, 0.45, 0.35)
		PickupType.ADRENALINE:
			if _box_mat:
				_box_mat.albedo_color = Color("#d48812") # Âmbar dourado
				_box_mat.metallic = 0.75
				_box_mat.roughness = 0.3
			if flare_light:
				flare_light.light_color = Color(1.0, 0.72, 0.0) # Luz âmbar
			if _smoke_mat:
				_smoke_mat.color = Color(1.0, 0.75, 0.05, 0.4)


func _physics_process(delta: float) -> void:
	# Oscilação contínua da luz do sinalizador entre 0.8 e 1.5
	if flare_light and is_active:
		light_pulse_time += delta * 4.5
		if light_pulse_time > TAU * 10.0:
			light_pulse_time = fmod(light_pulse_time, TAU)
		flare_light.light_energy = 1.15 + sin(light_pulse_time) * 0.35

	if not is_active:
		return

	# Acompanha o fluxo da rodovia
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
		match pickup_type:
			PickupType.AMMO:
				if GameController.mutator_melee_only:
					player.knife_charges = mini(5, player.knife_charges + 1)
					if player.has_signal("knife_charges_changed"):
						player.knife_charges_changed.emit(player.knife_charges)
					collected.emit(1)
				else:
					if player.weapon_manager and player.weapon_manager.has_method("add_ammo"):
						player.weapon_manager.add_ammo(ammo_amount)
					collected.emit(ammo_amount)
			PickupType.MEDKIT:
				player.heal(30.0)
				if AudioManager.instance:
					AudioManager.instance.play_medkit_pickup()
				collected.emit(30)
			PickupType.ADRENALINE:
				player.trigger_adrenaline_rush(4.5)
				if AudioManager.instance:
					AudioManager.instance.play_adrenaline_surge()
				collected.emit(1)
		deactivate()


func activate(spawn_pos: Vector3, new_road_speed: float, type: PickupType = PickupType.AMMO) -> void:
	pickup_type = type
	_apply_visual_type()

	# Garante que a base assente exatamente no nível da pista Y = 0.0
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
	if smoke_particles:
		smoke_particles.emitting = true


func deactivate() -> void:
	is_active = false
	visible = false
	if collision_shape:
		collision_shape.disabled = true
	if smoke_particles:
		smoke_particles.emitting = false
