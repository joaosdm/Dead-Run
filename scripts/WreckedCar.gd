class_name WreckedCar
extends StaticBody3D

## Dead Run - Wrecked Car Obstacle (Godot 4.3 - Web / Playgama Optimized)
## Instancia "assets/3D/wrecked+car+3d+model.glb" com variações de cor procedurais na lataria,
## colisão simplificada com BoxShape3D (~2.0m x ~1.3m x ~4.5m) e sistema opcional de fogo e fumaça.

# --- CONFIGURAÇÃO DE COLISÃO E DIMENSÕES ---
@export var car_width: float = 2.0
@export var car_height: float = 1.4
@export var car_length: float = 4.6

# --- ESTADO E ELEMENTOS INTERNOS ---
var is_active: bool = false
var is_burning: bool = false
var has_hit_player: bool = false

var collision_shape: CollisionShape3D = null
var car_mesh_instance: MeshInstance3D = null
var fire_light: OmniLight3D = null
var fire_particles: GPUParticles3D = null
var smoke_particles: GPUParticles3D = null
var visual_root: Node3D = null

# --- LUZES DE EMERGÊNCIA (GIROFLEX POLICIAL) E FARÓIS EMISSIVOS LEVES (WEB/MOBILE) ---
var has_headlights: bool = false
var is_police_emergency: bool = false
var siren_omni_light: OmniLight3D = null
var siren_bar_mesh: MeshInstance3D = null
var siren_bar_mat: StandardMaterial3D = null
var headlight_beam_mesh: MeshInstance3D = null
var siren_phase: float = 0.0

# Variações de cores procedurais da lataria (ferrugem escura, verde desbotado, cinza queimado, azul oxidado)
const BODY_COLORS: Array[Color] = [
	Color("#4a3028"), # Ferrugem escura
	Color("#3c4a3e"), # Verde militar desbotado
	Color("#232629"), # Cinza queimado / fuligem
	Color("#222d38")  # Azul escuro oxidado
]

var base_light_energy: float = 3.5
var flicker_timer: float = 0.0


func _ready() -> void:
	_setup_collision()
	_setup_side_scrape_area()
	_setup_visual_model()
	_setup_fire_and_smoke()
	_setup_dynamic_car_lights()
	
	# Inicializa com cor e estado
	apply_random_color()


func _setup_collision() -> void:
	collision_layer = 1 # Ambiente / Obstáculos
	collision_mask = 2  # Colide com o Jogador
	
	collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(car_width, car_height, car_length)
		collision_shape.shape = box
		collision_shape.position = Vector3(0.0, car_height * 0.5, 0.0)
		add_child(collision_shape)
	else:
		# Garante que seja estritamente BoxShape3D com a base exatamente em Y = 0 (sem penetrar no asfalto)
		var box = collision_shape.shape as BoxShape3D
		if not box:
			box = BoxShape3D.new()
			collision_shape.shape = box
		box.size = Vector3(car_width, car_height, car_length)
		collision_shape.position = Vector3(0.0, car_height * 0.5, 0.0)

	# Remove quaisquer colisões convexas/trimesh indesejadas
	for child in get_children():
		if child is CollisionShape3D and child != collision_shape:
			child.queue_free()


func _setup_visual_model() -> void:
	visual_root = get_node_or_null("VisualRoot") as Node3D
	if not visual_root:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)

	var model_inst = visual_root.get_node_or_null("WreckedCarModel")
	if not model_inst:
		var car_glb = load("res://assets/3D/wrecked+car+3d+model.glb")
		if car_glb:
			model_inst = car_glb.instantiate()
			model_inst.name = "WreckedCarModel"
			visual_root.add_child(model_inst)

	if model_inst:
		# Escala de ~4.5 ajusta o modelo cru (0.99m x 0.29m x 0.45m) para 4.5m comprimento, 1.33m altura e 2.05m largura
		model_inst.scale = Vector3(4.5, 4.5, 4.5)
		# Rotaciona 90 graus no eixo Y para alinhar o comprimento com o eixo Z da pista
		model_inst.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		model_inst.position = Vector3(0.0, 0.0, 0.0)

		# Localiza a malha do carro para pintura procedural
		car_mesh_instance = model_inst.find_child("tripo_node*", true, false) as MeshInstance3D
		if not car_mesh_instance and model_inst.get_child_count() > 0:
			car_mesh_instance = model_inst.get_child(0) as MeshInstance3D


func _setup_fire_and_smoke() -> void:
	# 1. Luz do fogo: alaranjada, pulsante, com shadow_enabled = false para Web
	fire_light = get_node_or_null("FireLight") as OmniLight3D
	if not fire_light:
		fire_light = OmniLight3D.new()
		fire_light.name = "FireLight"
		# Posicionado sobre o capô do motor
		fire_light.position = Vector3(0.0, 1.1, -1.3)
		fire_light.light_color = Color("#ff7722")
		fire_light.omni_range = 8.5
		fire_light.light_energy = 3.5
		fire_light.shadow_enabled = false # Otimização para Web / Playgama
		add_child(fire_light)

	# 2. Emissor de partículas de fogo (GPUParticles3D)
	fire_particles = get_node_or_null("FireParticles") as GPUParticles3D
	if not fire_particles:
		fire_particles = GPUParticles3D.new()
		fire_particles.name = "FireParticles"
		fire_particles.position = Vector3(0.0, 0.85, -1.3)
		fire_particles.amount = 10
		fire_particles.lifetime = 0.50
		fire_particles.explosiveness = 0.05
		fire_particles.randomness = 0.3
		
		# Material do processo
		var fire_mat := ParticleProcessMaterial.new()
		fire_mat.direction = Vector3(0, 1, 0)
		fire_mat.spread = 22.0
		fire_mat.initial_velocity_min = 1.2
		fire_mat.initial_velocity_max = 2.4
		fire_mat.gravity = Vector3(0, 1.5, 0) # Fogo sobe
		fire_mat.scale_min = 0.25
		fire_mat.scale_max = 0.65
		fire_mat.color = Color(1.0, 0.45, 0.08, 0.9)
		fire_particles.process_material = fire_mat
		
		# Malha das partículas (Quad billboard)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.4, 0.4)
		var fire_draw_mat := StandardMaterial3D.new()
		fire_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		fire_draw_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.85)
		fire_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fire_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad.material = fire_draw_mat
		fire_particles.draw_pass_1 = quad
		add_child(fire_particles)

	# 3. Emissor de partículas de fumaça preta (GPUParticles3D)
	smoke_particles = get_node_or_null("SmokeParticles") as GPUParticles3D
	if not smoke_particles:
		smoke_particles = GPUParticles3D.new()
		smoke_particles.name = "SmokeParticles"
		smoke_particles.position = Vector3(0.0, 1.2, -1.3)
		smoke_particles.amount = 10
		smoke_particles.lifetime = 1.1
		smoke_particles.explosiveness = 0.02
		
		var smoke_mat := ParticleProcessMaterial.new()
		smoke_mat.direction = Vector3(0, 1, 0)
		smoke_mat.spread = 15.0
		smoke_mat.initial_velocity_min = 1.6
		smoke_mat.initial_velocity_max = 3.2
		smoke_mat.gravity = Vector3(0, 0.8, 0)
		smoke_mat.scale_min = 0.4
		smoke_mat.scale_max = 1.2
		smoke_mat.color = Color(0.12, 0.12, 0.14, 0.6)
		smoke_particles.process_material = smoke_mat
		
		var smoke_quad := QuadMesh.new()
		smoke_quad.size = Vector2(0.6, 0.6)
		var smoke_draw_mat := StandardMaterial3D.new()
		smoke_draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		smoke_draw_mat.albedo_color = Color(0.12, 0.12, 0.14, 0.5)
		smoke_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smoke_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_quad.material = smoke_draw_mat
		smoke_particles.draw_pass_1 = smoke_quad
		add_child(smoke_particles)

	_set_fire_active(false)


func _setup_dynamic_car_lights() -> void:
	# 1. Cone Visual de Farol Fake-Volumétrico (Zero custo de iluminação GPU!)
	headlight_beam_mesh = get_node_or_null("HeadlightBeamMesh") as MeshInstance3D
	if not headlight_beam_mesh:
		headlight_beam_mesh = MeshInstance3D.new()
		headlight_beam_mesh.name = "HeadlightBeamMesh"
		var beam_cyl := CylinderMesh.new()
		beam_cyl.top_radius = 0.25
		beam_cyl.bottom_radius = 1.65
		beam_cyl.height = 6.5
		beam_cyl.radial_segments = 6
		beam_cyl.rings = 1
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_mat.albedo_color = Color(1.0, 0.90, 0.65, 0.14)
		beam_cyl.material = beam_mat
		headlight_beam_mesh.mesh = beam_cyl
		headlight_beam_mesh.position = Vector3(0.0, 0.55, 5.2)
		headlight_beam_mesh.rotation_degrees = Vector3(86.0, 0.0, 0.0)
		headlight_beam_mesh.visible = false
		add_child(headlight_beam_mesh)

	# 2. Barra Luminosa de Giroflex no Teto + 1 Única OmniLight3D que alterna Vermelho <-> Azul
	siren_bar_mesh = get_node_or_null("SirenBarMesh") as MeshInstance3D
	if not siren_bar_mesh:
		siren_bar_mesh = MeshInstance3D.new()
		siren_bar_mesh.name = "SirenBarMesh"
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.95, 0.14, 0.28)
		siren_bar_mat = StandardMaterial3D.new()
		siren_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		siren_bar_mat.albedo_color = Color(1.0, 0.15, 0.15)
		sbox.material = siren_bar_mat
		siren_bar_mesh.mesh = sbox
		siren_bar_mesh.position = Vector3(0.0, 1.42, 0.0)
		siren_bar_mesh.visible = false
		add_child(siren_bar_mesh)

	siren_omni_light = get_node_or_null("SirenOmniLight") as OmniLight3D
	if not siren_omni_light:
		siren_omni_light = OmniLight3D.new()
		siren_omni_light.name = "SirenOmniLight"
		siren_omni_light.position = Vector3(0.0, 1.6, 0.0)
		siren_omni_light.omni_range = 7.0
		siren_omni_light.light_energy = 2.8
		siren_omni_light.shadow_enabled = false
		siren_omni_light.visible = false
		add_child(siren_omni_light)


func _process(delta: float) -> void:
	if not is_active:
		return
		
	# Simula oscilação estocástica / crepitação da chama
	if is_burning and fire_light:
		flicker_timer -= delta
		if flicker_timer <= 0.0:
			flicker_timer = randf_range(0.05, 0.12)
			fire_light.light_energy = randf_range(2.2, 3.8)

	# Giroflex de emergência estroboscópico (Alterna cor em 1 única luz + barra unshaded!)
	if is_police_emergency:
		siren_phase += delta * 12.0
		var is_red_half: bool = sin(siren_phase) >= 0.0
		var col := Color(1.0, 0.12, 0.12) if is_red_half else Color(0.12, 0.42, 1.0)
		if siren_omni_light:
			siren_omni_light.light_color = col
		if siren_bar_mat:
			siren_bar_mat.albedo_color = col


## Aplica tonalidade aleatória no material da lataria
func apply_random_color() -> void:
	if not car_mesh_instance:
		return
		
	var orig_mat: Material = car_mesh_instance.mesh.surface_get_material(0)
	var new_mat: StandardMaterial3D = null
	if orig_mat is StandardMaterial3D:
		new_mat = orig_mat.duplicate() as StandardMaterial3D
	else:
		new_mat = StandardMaterial3D.new()
		
	var picked_color: Color = BODY_COLORS.pick_random()
	new_mat.albedo_color = picked_color
	# Superfície molhada e reflexiva: roughness 0.25 e metallic 0.35
	new_mat.roughness = 0.25
	new_mat.metallic = 0.35
	car_mesh_instance.set_surface_override_material(0, new_mat)


## Configura e monitora a área de esbarrão lateral nos carros
func _setup_side_scrape_area() -> void:
	var scrape_area := get_node_or_null("SideScrapeArea") as Area3D
	if not scrape_area:
		scrape_area = Area3D.new()
		scrape_area.name = "SideScrapeArea"
		scrape_area.collision_layer = 1
		scrape_area.collision_mask = 2 # Detecta Player
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.55, 1.4, 4.4)
		col.shape = box
		col.position = Vector3(0.0, 0.7, 0.0)
		scrape_area.add_child(col)
		add_child(scrape_area)

	if not scrape_area.body_entered.is_connected(_on_side_scrape_entered):
		scrape_area.body_entered.connect(_on_side_scrape_entered)


func _on_side_scrape_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body is Player and not body.is_dead and not body.get("is_grappled") and not body.get("is_in_ambush"):
		var contact_pos: Vector3 = body.global_position
		contact_pos.y = clampf(contact_pos.y, 0.4, 1.2)
		if body.has_method("handle_car_side_scrape"):
			body.handle_car_side_scrape(self, contact_pos)


## Ativa ou desativa o sistema de fogo e fumaça
func _set_fire_active(active: bool) -> void:
	is_burning = active
	if fire_light:
		fire_light.visible = active
	if fire_particles:
		fire_particles.emitting = active
	if smoke_particles:
		smoke_particles.emitting = active


## Ativa o carro destruído em uma posição e rotação na pista
func activate(spawn_pos: Vector3, rot_y_deg: float = 0.0) -> void:
	if is_inside_tree():
		global_position = spawn_pos
	else:
		position = spawn_pos
	rotation_degrees.y = rot_y_deg
	visible = true
	is_active = true
	has_hit_player = false
	
	if collision_shape:
		collision_shape.disabled = false

	var scrape_area := get_node_or_null("SideScrapeArea") as Area3D
	if scrape_area:
		scrape_area.monitoring = true
		
	apply_random_color()
	
	# 30% de probabilidade de estar em chamas
	var should_burn: bool = randf() < 0.30
	_set_fire_active(should_burn)

	# Quando não está em chamas, 35% de chance de ter giroflex policial (nunca acumula 2 luzes no mesmo carro!)
	is_police_emergency = (not should_burn and randf() < 0.35)
	has_headlights = (randf() < 0.45)
	if siren_omni_light:
		siren_omni_light.visible = is_police_emergency
	if siren_bar_mesh:
		siren_bar_mesh.visible = is_police_emergency
	if headlight_beam_mesh:
		headlight_beam_mesh.visible = has_headlights


## Desativa o carro para reaproveitamento no pool
func deactivate() -> void:
	is_active = false
	visible = false
	if collision_shape:
		collision_shape.disabled = true
	var scrape_area := get_node_or_null("SideScrapeArea") as Area3D
	if scrape_area:
		scrape_area.monitoring = false
	_set_fire_active(false)
	is_police_emergency = false
	has_headlights = false
	if siren_omni_light:
		siren_omni_light.visible = false
	if siren_bar_mesh:
		siren_bar_mesh.visible = false
	if headlight_beam_mesh:
		headlight_beam_mesh.visible = false
