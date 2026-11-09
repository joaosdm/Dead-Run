class_name WeaponManager
extends Node3D

## Dead Run - Weapon Manager (Godot 4.3)
## Carrega instâncias de cenas/modelos 3D (.glb), controla munição, cadência de tiro,
## efeito de Muzzle Flash com OmniLight3D, raycasting e animações (embutidas no .glb ou procedurais).

# --- SINAIS ---
signal weapon_fired
signal ammo_updated(current: int, reserve: int)
signal reload_started
signal reload_completed
signal dry_fire
signal target_hit(collider: Object, hit_point: Vector3, normal: Vector3)

# --- CONFIGURAÇÃO DO MODELO 3D (.GLB) ---
@export_group("Modelo da Arma (.glb / .tscn)")
@export_file("*.glb", "*.gltf", "*.tscn") var default_weapon_path: String = "res://assets/3D/handgun 3d model.glb"
@export var weapon_holder: Node3D
@export var model_scale: Vector3 = Vector3(0.7, 0.7, 0.7)
@export var model_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var model_rotation_deg: Vector3 = Vector3(0.0, 0.0, 0.0)

# --- AJUSTE DE MATERIAIS PBR DO VIEWMODEL ---
@export_group("Materiais PBR do Viewmodel")
@export var auto_tune_pbr: bool = true
@export var gun_metallic: float = 0.85 ## Brilho metálico da Glock (cano/ferrolho)
@export var gun_roughness: float = 0.28 ## Rugosidade polida para reflexo da luz ambiente e lanterna
@export var glove_metallic: float = 0.02 ## Tecido/couro das luvas (sem reflexo metálico)
@export var glove_roughness: float = 0.88 ## Aspecto fosco tático de tecido

# --- BALÍSTICA E ATRIBUTOS DE DISPARO ---
@export_group("Atributos da Arma")
@export var weapon_name: String = "Glock 9mm Tática"
@export var max_clip: int = 6
@export var current_ammo: int = 6
@export var reserve_ammo: int = 0
@export var max_reserve: int = 180
@export var fire_rate: float = 4.5 ## Tiros por segundo
@export var is_automatic: bool = false
@export var damage_per_shot: float = 35.0
@export var max_range: float = 120.0
@export var spread_angle_deg: float = 1.0
@export var reload_duration: float = 1.6
@export var current_weapon_recoil: float = 1.0

# --- RECUO PROCEDURAL E POSIÇÃO DE REPOUSO ---
@export_group("Recuo Procedural")
@export var weapon: Node3D = null ## Referência ao nó visual da arma (weapon_holder)
var default_weapon_pos: Vector3 = Vector3.ZERO
var default_weapon_rot: Vector3 = Vector3.ZERO
var default_pos: Vector3:
	get: return default_weapon_pos
	set(val): default_weapon_pos = val
var default_rot: Vector3:
	get: return default_weapon_rot
	set(val): default_weapon_rot = val
var procedural_tween: Tween = null
var recoil_tween: Tween = null

# --- EFEITOS DE MUZZLE FLASH E CARTUCHO ---
@export_group("Muzzle Flash e Cartucho")
@export var muzzle_light: OmniLight3D
@export var muzzle_point: Marker3D
var muzzle_flash_visual: Node3D = null
var muzzle_tween: Tween = null
var shell_casing_emitter: CPUParticles3D = null
var casing_particles: CPUParticles3D:
	get: return shell_casing_emitter

# --- ESTADO INTERNO ---
var can_shoot: bool = true
var is_reloading: bool = false
var fire_cooldown_timer: float = 0.0
var active_weapon_instance: Node3D = null
var animation_player: AnimationPlayer = null

var weapon_node: Node3D:
	get:
		if active_weapon_instance and is_instance_valid(active_weapon_instance):
			return active_weapon_instance
		if weapon_holder and is_instance_valid(weapon_holder):
			return weapon_holder
		return weapon


func _ready() -> void:
	current_ammo = max_clip
	visible = true
	_setup_weapon_hierarchy()
	_setup_muzzle_flash_light()
	_setup_shell_casing_emitter()
	
	if default_weapon_path != "":
		load_weapon_model(default_weapon_path)
		
	if weapon_holder:
		weapon_holder.visible = true
		weapon_holder.scale = Vector3.ONE
	if weapon:
		weapon.visible = true
		default_weapon_pos = Vector3.ZERO
		default_weapon_rot = Vector3.ZERO
		weapon.position = default_weapon_pos
		weapon.rotation = default_weapon_rot
	if active_weapon_instance:
		active_weapon_instance.visible = true

	ammo_updated.emit(current_ammo, reserve_ammo)


func ensure_weapon_visible() -> void:
	visible = true
	if weapon_holder and is_instance_valid(weapon_holder):
		weapon_holder.visible = true
	if weapon and is_instance_valid(weapon):
		weapon.visible = true
	if active_weapon_instance and is_instance_valid(active_weapon_instance):
		active_weapon_instance.visible = true


func _setup_weapon_hierarchy() -> void:
	if not weapon_holder:
		weapon_holder = get_node_or_null("WeaponHolder")
		if not weapon_holder:
			weapon_holder = Node3D.new()
			weapon_holder.name = "WeaponHolder"
			add_child(weapon_holder)
			
	if not weapon:
		weapon = weapon_holder
		
	default_weapon_pos = weapon.position
	default_weapon_rot = weapon.rotation

	if not muzzle_point:
		muzzle_point = weapon.get_node_or_null("MuzzlePoint") as Marker3D
		if not muzzle_point:
			muzzle_point = Marker3D.new()
			muzzle_point.name = "MuzzlePoint"
			# Posicionado na ponta do cano da Glock
			muzzle_point.position = Vector3(0.0, 0.30, -0.33)
			weapon.add_child(muzzle_point)


## Cria programaticamente a OmniLight3D na ponta do cano (cor #ff9922, alcance 8m, energia inicial 0)
## e adiciona malha curta de cruz com textura de chama no cano
func _setup_muzzle_flash_light() -> void:
	if not muzzle_light and muzzle_point:
		muzzle_light = muzzle_point.get_node_or_null("MuzzleLight") as OmniLight3D
		if not muzzle_light:
			muzzle_light = OmniLight3D.new()
			muzzle_light.name = "MuzzleLight"
			muzzle_point.add_child(muzzle_light)
			
	if muzzle_light:
		muzzle_light.light_color = Color("#ff9922") # Laranja vívido
		muzzle_light.omni_range = 8.0
		muzzle_light.light_energy = 0.0
		muzzle_light.shadow_enabled = false
		muzzle_light.visible = false

	_setup_muzzle_flash_cross()


func _setup_muzzle_flash_cross() -> void:
	if not muzzle_point:
		return
	muzzle_flash_visual = muzzle_point.get_node_or_null("MuzzleFlashCross") as Node3D
	if not muzzle_flash_visual:
		muzzle_flash_visual = Node3D.new()
		muzzle_flash_visual.name = "MuzzleFlashCross"

		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flame_mat.albedo_color = Color(1.0, 0.60, 0.13, 0.95)

		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(0.14, 0.14)
		quad_mesh.material = flame_mat

		var quad1 := MeshInstance3D.new()
		quad1.mesh = quad_mesh
		muzzle_flash_visual.add_child(quad1)

		var quad2 := MeshInstance3D.new()
		quad2.mesh = quad_mesh
		quad2.rotation_degrees.z = 90.0
		muzzle_flash_visual.add_child(quad2)

		muzzle_point.add_child(muzzle_flash_visual)

	muzzle_flash_visual.visible = false


## Cria programaticamente o emissor de cartuchos (cápsula dourada com velocidade Vector3(2.5, 3.0, 1.0))
func _setup_shell_casing_emitter() -> void:
	shell_casing_emitter = weapon.get_node_or_null("ShellCasingEmitter") as CPUParticles3D
	if not shell_casing_emitter:
		shell_casing_emitter = CPUParticles3D.new()
		shell_casing_emitter.name = "ShellCasingEmitter"
		# Posicionado na janela de ejeção no lado direito do ferrolho
		shell_casing_emitter.position = Vector3(0.08, 0.28, -0.15)
		
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.007
		cyl.bottom_radius = 0.007
		cyl.height = 0.024
		var brass_mat := StandardMaterial3D.new()
		brass_mat.albedo_color = Color(0.95, 0.78, 0.22) # Dourado / Amarelo metálico
		brass_mat.metallic = 0.95
		brass_mat.roughness = 0.2
		cyl.material = brass_mat
		shell_casing_emitter.mesh = cyl
		
		shell_casing_emitter.emitting = false
		shell_casing_emitter.one_shot = true
		shell_casing_emitter.explosiveness = 1.0
		shell_casing_emitter.amount = 1
		shell_casing_emitter.lifetime = 0.5
		# Velocidade arremessada para a direita e para cima: Vector3(2.5, 3.0, 1.0)
		shell_casing_emitter.direction = Vector3(2.5, 3.0, 1.0).normalized()
		shell_casing_emitter.spread = 10.0
		shell_casing_emitter.initial_velocity_min = 3.6
		shell_casing_emitter.initial_velocity_max = 4.2
		shell_casing_emitter.gravity = Vector3(0.0, -9.8, 0.0)
		shell_casing_emitter.angular_velocity_min = 360.0
		shell_casing_emitter.angular_velocity_max = 720.0
		weapon.add_child(shell_casing_emitter)


func _process(delta: float) -> void:
	# Só interpola passivamente de volta ao repouso se nenhum tween estiver ativo
	var is_tween_busy: bool = (recoil_tween != null and recoil_tween.is_valid()) or (procedural_tween != null and procedural_tween.is_valid())
	if weapon and not is_reloading and not is_tween_busy:
		weapon.position = weapon.position.lerp(default_weapon_pos, delta * 16.0)
		weapon.rotation = weapon.rotation.lerp(default_weapon_rot, delta * 16.0)
		if not weapon.visible:
			weapon.visible = true
	if not visible:
		visible = true
	if active_weapon_instance and not active_weapon_instance.visible:
		active_weapon_instance.visible = true
		
	# Temporizador de cadência de disparo
	if fire_cooldown_timer > 0.0:
		fire_cooldown_timer -= delta
		if fire_cooldown_timer <= 0.0:
			can_shoot = true


## Carrega um modelo 3D (.glb / .gltf / .tscn) dinamicamente e instancia no WeaponHolder
func load_weapon_model(resource_path: String) -> void:
	if not ResourceLoader.exists(resource_path):
		push_warning("WeaponManager: Modelo de arma não encontrado em '%s'" % resource_path)
		return

	# Remove arma anterior se houver
	if active_weapon_instance and is_instance_valid(active_weapon_instance):
		active_weapon_instance.queue_free()
		active_weapon_instance = null
		animation_player = null

	var scene_resource = load(resource_path)
	if not scene_resource:
		push_error("WeaponManager: Falha ao carregar recurso '%s'" % resource_path)
		return

	var instance: Node = scene_resource.instantiate()
	if instance is Node3D:
		active_weapon_instance = instance
		weapon_holder.add_child(active_weapon_instance)
		
		# Aplica transformações iniciais de visualização
		active_weapon_instance.position = model_offset
		active_weapon_instance.rotation_degrees = model_rotation_deg
		active_weapon_instance.scale = model_scale
		active_weapon_instance.visible = true
		for child in active_weapon_instance.get_children():
			if child is Node3D:
				child.visible = true
		
		# Localiza AnimationPlayer no modelo .glb
		animation_player = _find_animation_player(active_weapon_instance)
		
		# Aplica balanceamento de materiais PBR (Albedo, Glock metálica e luvas de tecido fosco)
		if auto_tune_pbr:
			_tune_viewmodel_pbr_materials(active_weapon_instance)


func _find_animation_player(root_node: Node) -> AnimationPlayer:
	if root_node is AnimationPlayer:
		return root_node
	for child in root_node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null


## Percorre os MeshInstance3D do modelo importado, valida o Albedo e ajusta PBR (Glock metálica vs luvas foscas)
func _tune_viewmodel_pbr_materials(root_node: Node) -> void:
	var mesh_instances: Array[MeshInstance3D] = []
	_gather_mesh_instances(root_node, mesh_instances)
	
	for mesh_inst in mesh_instances:
		if not mesh_inst.mesh:
			continue
			
		var surf_count: int = mesh_inst.mesh.get_surface_count()
		var aabb: AABB = mesh_inst.mesh.get_aabb()
		var center: Vector3 = aabb.get_center()
		
		# Identificação geométrica: o cano e o ferrolho da Glock ficam no eixo central X e projetados em -Z
		var is_glock_metal: bool = (absf(center.x) < 0.075 and center.z < 0.12)
		
		for s in range(surf_count):
			var orig_mat: Material = mesh_inst.get_surface_override_material(s)
			if not orig_mat:
				orig_mat = mesh_inst.mesh.surface_get_material(s)
				
			if orig_mat is StandardMaterial3D:
				var pbr_mat: StandardMaterial3D = orig_mat.duplicate() as StandardMaterial3D
				
				# Garante que a textura Albedo embutida esteja ativa e sem escurecimento
				if pbr_mat.albedo_texture:
					pbr_mat.albedo_color = Color.WHITE
				
				if is_glock_metal:
					# Cano, ferrolho e peças metálicas: alta refletividade para luz ambiente e feixe da lanterna
					pbr_mat.metallic = gun_metallic
					pbr_mat.roughness = gun_roughness
					pbr_mat.metallic_specular = 0.55
				else:
					# Luvas táticas e mangas: aspecto fosco de tecido/polímero sem brilho especular espelhado
					pbr_mat.metallic = glove_metallic
					pbr_mat.roughness = glove_roughness
					pbr_mat.metallic_specular = 0.15
					
				mesh_inst.set_surface_override_material(s, pbr_mat)


func _gather_mesh_instances(node: Node, out_list: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_list.append(node)
	for child in node.get_children():
		_gather_mesh_instances(child, out_list)


## Executa o disparo da arma com recuo procedural físico, clarão com chama em cruz e ejeção de cartucho dourado
func shoot() -> bool:
	if is_reloading:
		return false
		
	if not can_shoot:
		return false
		
	if current_ammo <= 0:
		dry_fire.emit()
		AudioManager.play_dry_fire()
		# Tenta recarregar automaticamente se houver munição reserva
		if reserve_ammo > 0:
			reload()
		return false

	# Consome munição e aplica cadência
	current_ammo -= 1
	can_shoot = false
	fire_cooldown_timer = 1.0 / fire_rate
	ammo_updated.emit(current_ammo, reserve_ammo)

	# Efeito sonoro: estalo seco com cauda de reverberação leve
	AudioManager.play_glock_shot()


	# 1. Tranco Físico (Recuo Procedural Suave e Firme via Tween, sem oscilações repetidas):
	if weapon:
		if recoil_tween and recoil_tween.is_valid():
			recoil_tween.kill()

		# Deslocamento controlado: recuo para trás em Z e leve subida angular no cano em X
		var kick_pos := default_weapon_pos + Vector3(0.0, 0.012, 0.045)
		var kick_rot := default_weapon_rot + Vector3(deg_to_rad(6.0), 0.0, 0.0)

		recoil_tween = create_tween()
		# Subida rápida (0.04s) com amortecimento suave
		recoil_tween.set_parallel(true)
		recoil_tween.tween_property(weapon, "position", kick_pos, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil_tween.tween_property(weapon, "rotation", kick_rot, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Retorno imediato e estável para a posição de repouso (0.10s)
		recoil_tween.chain().set_parallel(true)
		recoil_tween.tween_property(weapon, "position", default_weapon_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil_tween.tween_property(weapon, "rotation", default_weapon_rot, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil_tween.chain().tween_callback(func():
			if weapon and is_instance_valid(weapon):
				weapon.position = default_weapon_pos
				weapon.rotation = default_weapon_rot
		)

	# 2. Clarão de Fogo (Muzzle Flash):
	# - OmniLight3D ponta do cano: cor #ff9922, energia 5.0, alcance 8.0m
	# - Tween reduz a energia para 0 em 0.04 segundos
	# - Malha curta de cruz com textura de chama no cano durante esse mesmo frame de 0.04s
	if muzzle_light:
		muzzle_light.visible = true
		muzzle_light.light_energy = 5.0
		if muzzle_tween and muzzle_tween.is_valid():
			muzzle_tween.kill()
		muzzle_tween = create_tween()
		muzzle_tween.tween_property(muzzle_light, "light_energy", 0.0, 0.04)
		muzzle_tween.tween_callback(func():
			if muzzle_light:
				muzzle_light.visible = false
			if muzzle_flash_visual:
				muzzle_flash_visual.visible = false
		)

	if muzzle_flash_visual:
		muzzle_flash_visual.visible = true
		muzzle_flash_visual.scale = Vector3.ONE * randf_range(0.9, 1.25)
		muzzle_flash_visual.rotation.z = randf_range(0.0, TAU)

	# 3. Ejeção de Cartucho:
	# Cápsula metálica amarela/dourada arremessada para a direita e para cima (velocity = Vector3(2.5, 3.0, 1.0))
	# com rotação rápida, caindo com gravidade
	_eject_shell_casing()
	
	# 4. Raycast balístico
	_perform_raycast_shot()
	
	weapon_fired.emit()
	return true


func _eject_shell_casing() -> void:
	if shell_casing_emitter:
		shell_casing_emitter.restart()
		shell_casing_emitter.emitting = true
	_spawn_flying_cartridge()


func _spawn_flying_cartridge() -> void:
	if not weapon or not is_inside_tree():
		return
	var casing := Node3D.new()
	casing.name = "Cartridge"
	
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.007
	cyl.bottom_radius = 0.007
	cyl.height = 0.024
	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.95, 0.78, 0.22) # Amarela / Dourada metálica
	brass_mat.metallic = 0.95
	brass_mat.roughness = 0.22
	mesh_inst.mesh = cyl
	mesh_inst.material_override = brass_mat
	casing.add_child(mesh_inst)

	var spawn_pos: Vector3 = weapon.global_position + weapon.global_transform.basis * Vector3(0.08, 0.28, -0.15)
	var parent_scene: Node = get_tree().current_scene
	if not parent_scene:
		parent_scene = get_parent()
	parent_scene.add_child(casing)
	casing.global_position = spawn_pos
	
	# Transforma o vetor de velocidade arremessado para a direita e para cima: Vector3(2.5, 3.0, 1.0)
	var eject_dir_local := Vector3(2.5, 3.0, 1.0)
	var eject_vel: Vector3 = weapon.global_transform.basis * eject_dir_local
	var rot_speed := Vector3(randf_range(20.0, 35.0), randf_range(20.0, 35.0), randf_range(20.0, 35.0))
	
	var life_timer: float = 0.55
	var tween := casing.create_tween()
	# Simula trajetória balística com gravidade e rotação rápida por 0.55s
	tween.tween_method(func(progress: float):
		if not is_instance_valid(casing):
			return
		var t: float = progress * life_timer
		var current_pos: Vector3 = spawn_pos + eject_vel * t + Vector3(0.0, -0.5 * 9.8 * t * t, 0.0)
		casing.global_position = current_pos
		casing.rotation += rot_speed * 0.016
	, 0.0, 1.0, life_timer)
	tween.tween_callback(casing.queue_free)


## Inicia recarga de munição
func get_reload_speed_multiplier() -> float:
	var mult: float = 1.0
	if GameController.instance and GameController.instance.combo_multiplier >= 2:
		mult = 1.35 # +35% de velocidade de recarga durante combo
	return mult


func reload() -> void:
	if is_reloading:
		return
	if current_ammo >= max_clip or reserve_ammo <= 0:
		return
		
	is_reloading = true
	can_shoot = false
	reload_started.emit()
	
	# Toca animação do AnimationPlayer se existir
	var anim_played: bool = false
	if animation_player:
		var reload_names = ["reload", "Reload", "reload_ammo"]
		for anim_name in reload_names:
			if animation_player.has_animation(anim_name):
				animation_player.speed_scale = get_reload_speed_multiplier()
				animation_player.play(anim_name)
				anim_played = true
				break

	if not anim_played:
		_play_procedural_reload()
	else:
		# Aguarda duração da recarga
		get_tree().create_timer(reload_duration / get_reload_speed_multiplier()).timeout.connect(_complete_reload)


## Animação procedural de recarga via Tween (para GLB estático)
func _play_procedural_reload() -> void:
	var target_node: Node3D = weapon if weapon else weapon_holder
	if not target_node:
		_complete_reload()
		return
		
	if procedural_tween and procedural_tween.is_valid():
		procedural_tween.kill()

	var spd_mult: float = get_reload_speed_multiplier()
	var step1: float = 0.35 / spd_mult
	var pause_step: float = 0.40 / spd_mult
	var step2: float = 0.35 / spd_mult

	procedural_tween = create_tween()
	# 1. Arma desce e gira para o lado para ejetar magazine
	var down_pos := default_pos + Vector3(0.05, -0.22, 0.08)
	var down_rot := default_rot + Vector3(deg_to_rad(-18.0), deg_to_rad(30.0), deg_to_rad(-15.0))
	
	procedural_tween.set_parallel(true)
	procedural_tween.tween_property(target_node, "position", down_pos, step1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	procedural_tween.tween_property(target_node, "rotation", down_rot, step1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. Pausa inserindo novo pente
	procedural_tween.chain().tween_interval(pause_step)
	
	# 3. Retorna engatilhando
	procedural_tween.chain().set_parallel(true)
	procedural_tween.tween_property(target_node, "position", default_pos, step2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	procedural_tween.tween_property(target_node, "rotation", default_rot, step2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	procedural_tween.chain().tween_callback(_complete_reload)


func _complete_reload() -> void:
	var needed: int = max_clip - current_ammo
	var reload_amount: int = mini(needed, reserve_ammo)
	current_ammo += reload_amount
	reserve_ammo -= reload_amount
	
	is_reloading = false
	can_shoot = true
	ammo_updated.emit(current_ammo, reserve_ammo)
	reload_completed.emit()


## Adiciona munição à arma (coleta de caixas de munição táticas)
func add_ammo(amount: int) -> void:
	var needed: int = max_clip - current_ammo
	if needed > 0:
		var fill: int = mini(needed, amount)
		current_ammo += fill
		reserve_ammo = mini(reserve_ammo + (amount - fill), max_reserve)
	else:
		reserve_ammo = mini(reserve_ammo + amount, max_reserve)
	ammo_updated.emit(current_ammo, reserve_ammo)


## Raycast Hitscan disparado a partir da câmera do jogador
func _perform_raycast_shot() -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	var cam: Camera3D = viewport.get_camera_3d()
	if not cam:
		return
		
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = cam.global_position
	
	# Calcula direção à frente com leve dispersão (spread)
	var forward: Vector3 = -cam.global_transform.basis.z
	var spread_rad: float = deg_to_rad(spread_angle_deg)
	var spread_offset := Vector3(
		randf_range(-spread_rad, spread_rad),
		randf_range(-spread_rad, spread_rad),
		0.0
	)
	var shoot_dir := (forward + spread_offset).normalized()
	var target_end: Vector3 = origin + shoot_dir * max_range
	
	var query := PhysicsRayQueryParameters3D.create(origin, target_end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	# Exclui rigorosamente o jogador e todos os seus filhos de colisão do raycast
	var player = get_tree().get_first_node_in_group("player")
	var exclude_list: Array[RID] = []
	if player and player is CollisionObject3D:
		exclude_list.append((player as CollisionObject3D).get_rid())
		for child in player.get_children():
			if child is CollisionObject3D:
				exclude_list.append((child as CollisionObject3D).get_rid())
	query.exclude = exclude_list
	query.collision_mask = ~2 # Ignora a camada 2 onde o Player reside
	
	var result := space_state.intersect_ray(query)
	var tracer_end: Vector3 = target_end
	if result:
		tracer_end = result.position
	_spawn_bullet_tracer(tracer_end)

	if result:
		var collider: Object = result.collider
		# Failsafe: se de alguma forma interceptar o próprio jogador, ignora completamente
		if collider == player or (player and player.is_ancestor_of(collider)):
			return

		var hit_pos: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		var dist_to_cam: float = origin.distance_to(hit_pos)
		var is_point_blank: bool = (dist_to_cam < 5.0)

		# Detecção de Acerto Crítico (Headshot)
		var is_head_hit: bool = false
		if collider is HeadHitbox:
			is_head_hit = true
		elif collider is CollisionShape3D and collider.name == "HeadCol":
			is_head_hit = true
		elif collider.get_parent() is HeadHitbox or (collider.has_node("HeadCol")):
			is_head_hit = true
		elif collider is Zombie and hit_pos.y >= (collider.global_position.y + 1.35):
			is_head_hit = true

		# Câmera Lenta Relâmpago (Hit Stop / Tactical Freeze) e HUD Headshot: APENAS em Zumbis
		var is_zombie_target: bool = (collider is Zombie or collider is HeadHitbox or (collider.get_parent() is Zombie))
		var hud := _get_hud()
		if is_zombie_target:
			if hud and hud.has_method("show_hitmarker"):
				hud.show_hitmarker(is_head_hit)
			if is_head_hit:
				if AudioManager.instance:
					AudioManager.instance.play_headshot_ding()
				if is_point_blank:
					_trigger_tactical_hit_stop()
				if hud and hud.has_method("show_headshot_feedback"):
					hud.show_headshot_feedback(100)
		else:
			# Faíscas em superfícies metálicas / concreto
			_spawn_impact_sparks(hit_pos, hit_normal)

		target_hit.emit(collider, hit_pos, hit_normal)

		# Aplica dano ao alvo
		if collider is HeadHitbox:
			collider.take_damage(damage_per_shot, hit_pos, hit_normal, true, is_point_blank)
		elif collider is Zombie:
			var z: Zombie = collider as Zombie
			var dmg: float = damage_per_shot * (2.5 if is_head_hit else 1.0)
			z.take_damage(dmg, hit_pos, hit_normal, is_head_hit, is_point_blank)
		elif collider != player and not (player and player.is_ancestor_of(collider)):
			if collider.has_method("take_damage"):
				collider.take_damage(damage_per_shot, hit_pos, hit_normal)
			elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
				var p = collider.get_parent()
				if p != player and not (player and player.is_ancestor_of(p)):
					if p is Zombie:
						var dmg: float = damage_per_shot * (2.5 if is_head_hit else 1.0)
						p.take_damage(dmg, hit_pos, hit_normal, is_head_hit, is_point_blank)
					else:
						p.take_damage(damage_per_shot, hit_pos, hit_normal)


## Câmera Lenta Relâmpago (Hit Stop / Tactical Freeze): Engine.time_scale = 0.25 por 0.08s real
func _trigger_tactical_hit_stop() -> void:
	if not is_inside_tree():
		return
	Engine.time_scale = 0.25
	get_tree().create_timer(0.08, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
	)


## Cria rastro luminoso balístico (Bullet Tracer) da boca do cano até o alvo
func _spawn_bullet_tracer(end_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var start_pos: Vector3 = muzzle_point.global_position if muzzle_point else global_position
	var dist: float = start_pos.distance_to(end_pos)
	if dist < 0.8:
		return

	var tracer := MeshInstance3D.new()
	tracer.name = "BulletTracer"
	var box := BoxMesh.new()
	var trace_len: float = minf(dist * 0.65, 14.0)
	box.size = Vector3(0.016, 0.016, trace_len)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.82, 0.35, 0.92)
	box.material = mat
	tracer.mesh = box

	var scene_root := get_tree().current_scene if get_tree().current_scene else get_parent()
	scene_root.add_child(tracer)

	var mid_start: Vector3 = start_pos.lerp(end_pos, 0.3)
	tracer.global_position = mid_start
	tracer.look_at(end_pos, Vector3.UP)

	var tw := tracer.create_tween()
	tw.set_parallel(true)
	tw.tween_property(tracer, "global_position", start_pos.lerp(end_pos, 0.82), 0.055)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.055)
	tw.chain().tween_callback(tracer.queue_free)


func _spawn_impact_sparks(hit_pos: Vector3, hit_normal: Vector3) -> void:
	if not is_inside_tree():
		return
	var sparks_scene := preload("res://scenes/MetalSparks.tscn")
	var sparks := sparks_scene.instantiate() as CPUParticles3D
	if not sparks:
		return
	var scene_root := get_tree().current_scene if get_tree().current_scene else get_parent()
	scene_root.add_child(sparks)
	sparks.global_position = hit_pos
	sparks.direction = hit_normal if hit_normal.length_squared() > 0.01 else Vector3(0, 1, 0)


func _get_hud() -> GameHUD:
	if is_inside_tree():
		var tree := get_tree()
		if tree:
			var h = tree.get_first_node_in_group("hud") as GameHUD
			if h:
				return h
			if get_parent():
				var p_hud = get_parent().find_child("HUD", true, false) as GameHUD
				if p_hud:
					return p_hud
	return null
