class_name Player
extends CharacterBody3D

## Dead Run - Player Controller (Godot 4.3)
## Gerencia câmera em 1ª pessoa, movimentação lateral com inércia em pista,
## câmera bobbing durante sprint contínuo, recoil físico da arma e ações (pulo/slide/tiro).

# --- SINAIS ---
signal fired_weapon
signal jumped
signal slid(is_sliding: bool)
signal health_changed(current: float, max_val: float)
signal stamina_changed(current: float, max_val: float, is_exhausted: bool)
signal player_died
signal qte_grapple_started(duration_real: float, required_presses: int)
signal qte_progress_updated(current_presses: int, required_presses: int, time_remaining: float)
signal qte_grapple_ended(success: bool)
signal emergency_struggle_started(duration_real: float)
signal emergency_struggle_ended(success: bool)
signal knife_charges_changed(charges: int)
signal weapon_switched(slot: int)
signal quick_melee_triggered
signal near_miss_occurred(direction_sign: float, threat_zombie: Zombie)

# --- SLOTS DE ARMAS ---
enum WeaponSlot {
	GLOCK = 1,
	KNIFE = 2
}

# --- NÓS E REFERÊNCIAS ---
@export_group("Hierarquia de Nós")
@export var camera: Camera3D
@export var camera_pivot: Node3D
@export var flashlight: SpotLight3D
@export var viewmodel_anchor: Node3D
@export var weapon_manager: Node3D
@export var knife_view_model: KnifeViewModel
@export var muzzle_flash_light: OmniLight3D
@export var collision_shape: CollisionShape3D

# --- ESTADO DE ARMAS E SLOTS ---
@export_group("Arsenal")
@export var active_slot: WeaponSlot = WeaponSlot.GLOCK
var is_switching_weapon: bool = false
var is_quick_melee: bool = false
var weapon_switch_y_offset: float = 0.0

# --- MOVIMENTAÇÃO LATERAL E LIMITES ---
@export_group("Física Lateral (Pistas)")
@export var min_lane_x: float = -8.0
@export var max_lane_x: float = 8.0
@export var lateral_acceleration: float = 42.0
@export var lateral_friction: float = 14.0
@export var max_lateral_speed: float = 8.5
@export var border_bounciness: float = 0.25
@export var lock_camera_roll: bool = false ## Trava a rotação Z da Camera3D em 0.0 para manter pista e horizonte perfeitamente alinhados
@export var max_camera_tilt_rad: float = 0.065 ## Inclinação lateral dinâmica ao esquivar (estilo Mirror's Edge / Into the Dead)

# --- PULO E GRAVIDADE ---
@export_group("Pulo e Gravidade")
@export var jump_velocity: float = 8.2
@export var gravity: float = 22.0

# --- SLIDE / AGACHAMENTO ---
@export_group("Slide e Agachamento")
@export var normal_camera_height: float = 1.65
@export var slide_camera_height: float = 0.85
@export var slide_speed_factor: float = 1.15
@export var slide_duration: float = 0.75
@export var slide_transition_speed: float = 12.0

# --- CAMERA BOBBING & BREATHING ---
@export_group("Camera Bobbing (Sprint)")
@export var bob_frequency: float = 9.5
@export var bob_vertical_amplitude: float = 0.045
@export var bob_horizontal_amplitude: float = 0.03
@export var bob_smoothing: float = 12.0

# --- BALANÇO RÍTMICO DE CORRIDA DA ARMA (WEAPON BOBBING) ---
@export_group("Weapon Bobbing (Balanço da Arma)")
@export var weapon_bob_frequency: float = 9.5
@export var weapon_bob_amount: Vector2 = Vector2(0.018, 0.014) ## Deslocamento X e Y da arma
@export var weapon_bob_rot_degrees: Vector2 = Vector2(1.2, 1.8) ## Rotações pitch e roll
@export var weapon_bob_smooth: float = 12.0

# --- RECOIL DA ARMA E CLARÃO ALARANJADO (MUZZLE FLASH) ---
@export_group("Recoil da Arma e Muzzle Flash")
@export var recoil_pitch_deg: float = 8.5 ## Recuo angular no eixo X (empinamento do cano)
@export var recoil_kick_z: float = 0.055 ## Recuo linear para trás em Z
@export var recoil_recovery_speed: float = 14.0 ## Recuperação suave via lerp
@export var recoil_snappiness: float = 24.0
@export var muzzle_flash_color: Color = Color(1.0, 0.55, 0.15) ## Clarão alaranjado
@export var muzzle_flash_energy: float = 4.8
@export var muzzle_flash_duration: float = 0.045
@export var sway_intensity: float = 0.005
@export var sway_smooth: float = 10.0

# --- ATRIBUTOS DO JOGADOR ---
@export_group("Status")
@export var max_health: float = 100.0
var health: float = 100.0
var current_health: float:
	get: return health
var is_dead: bool = false

# --- SISTEMA DE ESTAMINA E FÔLEGO ---
@export var max_stamina: float = 100.0
var current_stamina: float = 100.0
var is_exhausted: bool = false
var is_sprinting: bool = false

# --- ESTADOS INTERNOS ---
var is_sliding: bool = false
var slide_timer: float = 0.0
var current_steer_input: float = 0.0
var bob_phase: float = 0.0
var initial_cam_pos: Vector3 = Vector3.ZERO
var initial_viewmodel_pos: Vector3 = Vector3.ZERO
var initial_viewmodel_rot: Vector3 = Vector3.ZERO

# Balanço da arma (Weapon Bobbing)
var weapon_bob_phase: float = 0.0
var current_weapon_bob_pos: Vector3 = Vector3.ZERO
var current_weapon_bob_rot: Vector3 = Vector3.ZERO

# Clarão momentâneo
var muzzle_flash_timer: float = 0.0

# Vetores de recoil e mola
var target_recoil_pos: Vector3 = Vector3.ZERO
var current_recoil_pos: Vector3 = Vector3.ZERO
var target_recoil_rot: Vector3 = Vector3.ZERO
var current_recoil_rot: Vector3 = Vector3.ZERO

# Sway inercial lateral
var lateral_sway_offset: Vector3 = Vector3.ZERO

# --- ESBARRÃO LATERAL NOS CARROS (SIDE SCRAPING) ---
var last_side_scrape_time: float = -10.0
static var _shared_scrape_wav: AudioStreamWAV = null

# --- AGARRÃO CINEMÁTICO EM PRIMEIRA PESSOA (GRAPPLE CUTSCENE) ---

@export var knife_charges: int = 1 # Cargas de faca tática
var is_grappled: bool = false
var grapple_time_remaining: float = 0.0
const GRAPPLE_DURATION: float = 1.6 # 1.6 segundos em tempo real (tempo de leitura e reação justa)
var current_grapple_zombie: Node3D = null
var is_resolving_grapple: bool = false
var has_played_heartbeat_warning: bool = false

# Compatibilidade com referências antigas de struggle/qte
var is_in_struggle: bool:
	get: return is_grappled or is_in_ambush
	set(val): is_grappled = val
var struggle_time_remaining: float:
	get: return grapple_time_remaining
	set(val): grapple_time_remaining = val
const STRUGGLE_DURATION: float = 1.6
var qte_time_remaining: float:
	get: return grapple_time_remaining
	set(val): grapple_time_remaining = val

var qte_presses_needed: int = 1
var qte_current_presses: int = 0

# --- SISTEMA ANTI-CAMPER / EMBOSCADA DE ZUMBI POR FICAR PRESO ---
var stuck_timer: float = 0.0
const MAX_STUCK_TIME: float = 2.0 # Se ficar 2 segundos sem avançar
var is_in_ambush: bool = false
var ambush_time_remaining: float = 0.0
const AMBUSH_DURATION: float = 0.9 # Janela de 0.9s em tempo real
var ambush_zombie: Zombie = null
var ambush_requires_knife: bool = false

# --- IMERSÃO FÍSICA: HEAD BOBBING EM 8 (LISSAJOUS) E FOV DINÂMICO ---
var step_time: float = 0.0
var default_cam_y: float = 0.0
var default_cam_x: float = 0.0
var base_fov: float = 70.0
var sprint_fov: float = 77.0
var current_road_speed: float = 10.5
var is_adrenaline_rush: bool = false
var adrenaline_timer: float = 0.0
var is_slipping_oil: bool = false
var oil_slip_timer: float = 0.0
var oil_slip_drift_dir: float = 0.0
var near_miss_cooldown: float = 0.0
var wind_particles: GPUParticles3D = null


var weapon_node: Node3D:
	get:
		if viewmodel_anchor and is_instance_valid(viewmodel_anchor):
			return viewmodel_anchor
		if weapon_manager and is_instance_valid(weapon_manager):
			return weapon_manager
		return null


func _ready() -> void:
	Engine.time_scale = 1.0
	health = max_health
	_setup_nodes_hierarchy()
	
	# Grava referências iniciais de repouso
	if camera:
		camera.near = 0.05
		initial_cam_pos = camera.position
		default_cam_y = camera.position.y
		default_cam_x = camera.position.x
		camera.fov = base_fov
		camera.rotation = Vector3.ZERO
	elif camera_pivot:
		initial_cam_pos = camera_pivot.position
		default_cam_y = camera_pivot.position.y
		default_cam_x = camera_pivot.position.x
		camera_pivot.rotation = Vector3.ZERO
		
	if viewmodel_anchor:
		viewmodel_anchor.position = Vector3(0.18, -0.46, -0.48)
		viewmodel_anchor.scale = Vector3.ONE
		viewmodel_anchor.visible = true
		initial_viewmodel_pos = viewmodel_anchor.position
		initial_viewmodel_rot = viewmodel_anchor.rotation

	if weapon_manager:
		weapon_manager.visible = true
		if weapon_manager.has_method("ensure_weapon_visible"):
			weapon_manager.ensure_weapon_visible()

	# Aplica configurações de Mutators de Terror
	if GameController.mutator_no_flashlight and flashlight:
		flashlight.visible = false
	if GameController.mutator_melee_only:
		active_slot = WeaponSlot.KNIFE
		knife_charges = 3
		knife_charges_changed.emit(knife_charges)
		if viewmodel_anchor:
			viewmodel_anchor.visible = false
		if weapon_manager:
			weapon_manager.visible = false
		if knife_view_model:
			knife_view_model.visible = true


func _setup_nodes_hierarchy() -> void:
	# Fallback automático: se nós não forem conectados no Inspector, busca ou cria na hierarquia
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.4
			capsule.height = 1.8
			collision_shape.shape = capsule
			collision_shape.position = Vector3(0, 0.9, 0)
			add_child(collision_shape)

	if not camera_pivot:
		camera_pivot = get_node_or_null("CameraPivot")
		if not camera_pivot:
			camera_pivot = Node3D.new()
			camera_pivot.name = "CameraPivot"
			camera_pivot.position = Vector3(0, normal_camera_height, 0)
			add_child(camera_pivot)

	if not camera:
		camera = camera_pivot.get_node_or_null("Camera3D")
		if not camera:
			camera = Camera3D.new()
			camera.name = "Camera3D"
			camera.current = true
			camera.fov = 75.0
			camera.near = 0.05
			camera.far = 85.0
			camera_pivot.add_child(camera)
	else:
		camera.near = 0.05
		camera.far = 85.0

	# Garante que o AudioListener3D esteja ativo na Camera3D para áudio posicional 3D nítido
	if camera:
		var listener := camera.get_node_or_null("AudioListener3D") as AudioListener3D
		if not listener:
			listener = AudioListener3D.new()
			listener.name = "AudioListener3D"
			camera.add_child(listener)
		listener.make_current()

	if not flashlight and camera:
		flashlight = camera.get_node_or_null("Flashlight")
		if not flashlight:
			flashlight = SpotLight3D.new()
			flashlight.name = "Flashlight"
			flashlight.position = Vector3(0.1, -0.05, -0.1)
			flashlight.light_color = Color(0.98, 0.96, 0.92)
			flashlight.light_energy = 2.6
			flashlight.light_volumetric_fog_energy = 0.0
			flashlight.shadow_enabled = false
			flashlight.spot_range = 42.0
			flashlight.spot_angle = 36.0
			flashlight.spot_attenuation = 1.35
			camera.add_child(flashlight)
	elif flashlight:
		flashlight.shadow_enabled = false
		flashlight.spot_range = 42.0

	if not viewmodel_anchor:
		viewmodel_anchor = camera.get_node_or_null("ViewmodelAnchor")
		if not viewmodel_anchor:
			viewmodel_anchor = Marker3D.new()
			viewmodel_anchor.name = "ViewmodelAnchor"
			viewmodel_anchor.position = Vector3(0.18, -0.46, -0.48)
			camera.add_child(viewmodel_anchor)
	else:
		viewmodel_anchor.position = Vector3(0.18, -0.46, -0.48)
		viewmodel_anchor.scale = Vector3.ONE
		viewmodel_anchor.visible = true

	if not weapon_manager:
		weapon_manager = viewmodel_anchor.get_node_or_null("WeaponManager")
		if not weapon_manager:
			weapon_manager = get_node_or_null("WeaponManager")

	if weapon_manager:
		weapon_manager.visible = true
		if weapon_manager.has_method("ensure_weapon_visible"):
			weapon_manager.ensure_weapon_visible()

	if not muzzle_flash_light:
		muzzle_flash_light = find_child("MuzzleLight", true, false) as OmniLight3D
		if not muzzle_flash_light and viewmodel_anchor:
			muzzle_flash_light = OmniLight3D.new()
			muzzle_flash_light.name = "MuzzleLight"
			muzzle_flash_light.position = Vector3(0.0, 0.30, -0.33)
			muzzle_flash_light.light_color = muzzle_flash_color
			muzzle_flash_light.light_energy = muzzle_flash_energy
			muzzle_flash_light.omni_range = 6.5
			muzzle_flash_light.visible = false
			viewmodel_anchor.add_child(muzzle_flash_light)

	if not knife_view_model and camera:
		knife_view_model = camera.get_node_or_null("KnifeViewModel") as KnifeViewModel
		if not knife_view_model:
			knife_view_model = find_child("KnifeViewModel", true, false) as KnifeViewModel

	if knife_view_model:
		if active_slot == WeaponSlot.GLOCK:
			knife_view_model.visible = false
			knife_view_model.position = knife_view_model.hidden_pos
			if viewmodel_anchor:
				viewmodel_anchor.visible = true
			if weapon_manager:
				weapon_manager.visible = true
				if weapon_manager.has_method("ensure_weapon_visible"):
					weapon_manager.ensure_weapon_visible()
		else:
			knife_view_model.visible = true
			knife_view_model.position = knife_view_model.default_pos
			if viewmodel_anchor:
				viewmodel_anchor.visible = false

	_remove_unwanted_camera_meshes()
	_remove_unwanted_particles()
	_setup_rain_particles()


func _remove_unwanted_camera_meshes() -> void:
	if not camera:
		return
	for child in camera.get_children():
		# Se for uma malha direta (MeshInstance3D) na frente da câmera (que não seja o viewmodel ou faca)
		if child is MeshInstance3D:
			child.queue_free()
		elif child.name.to_lower().contains("black") or child.name.to_lower().contains("dark") or child.name.to_lower().contains("plane"):
			child.queue_free()


func _setup_rain_particles() -> void:
	if not camera:
		return
	var rain := camera.get_node_or_null("RainParticles")
	if not rain:
		rain = find_child("RainParticles", true, false)
	if rain and rain is CPUParticles3D:
		var cpu_rain := rain as CPUParticles3D
		cpu_rain.amount = 65 # Otimizado para Web/Playgama/Mobile sem perder densidade visual
		cpu_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cpu_rain.emission_box_extents = Vector3(6.0, 3.5, 6.0)
		cpu_rain.direction = Vector3(-1.0, -22.0, 3.0).normalized()
		cpu_rain.spread = 1.0
		cpu_rain.gravity = Vector3.ZERO
		cpu_rain.initial_velocity_min = 22.0
		cpu_rain.initial_velocity_max = 22.5
		cpu_rain.lifetime = 0.35
		cpu_rain.preprocess = 0.2

		var quad := cpu_rain.mesh as QuadMesh
		if not quad:
			quad = QuadMesh.new()
			cpu_rain.mesh = quad
		quad.size = Vector2(0.012, 0.4)

		var mat := quad.material as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			quad.material = mat
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.9, 1.0, 0.25)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _process(delta: float) -> void:
	if is_dead:
		return
	if is_grappled:
		_process_grapple_struggle(delta)
	elif is_in_ambush:
		_process_ambush_struggle(delta)
	_process_dynamic_fov(delta)
	_process_lissajous_head_bobbing(delta)

	# Garante que o modelo da Glock NUNCA permaneça com visible = false durante a gameplay normal (a menos que em Guerra de Trincheira)
	if not is_grappled and not is_in_ambush and not is_switching_weapon and not is_quick_melee:
		if active_slot == WeaponSlot.GLOCK and not GameController.mutator_melee_only:
			if viewmodel_anchor and not viewmodel_anchor.visible:
				viewmodel_anchor.visible = true
			if weapon_manager and not weapon_manager.visible:
				weapon_manager.visible = true


func _unhandled_input(event: InputEvent) -> void:
	# Trava todas as ações de tiro, recarga e movimentação ao morrer
	if is_dead:
		return

	# 0. Intercepta teclas do QTE de Emboscada Anti-Camper
	if is_in_ambush:
		if ambush_requires_knife:
			# "[F] APUNHALAR AGORA!"
			if event.is_action_pressed("melee_kill") or (event is InputEventKey and (event.keycode == KEY_F or event.keycode == KEY_V) and event.is_pressed() and not event.is_echo()) or (event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT):
				resolve_ambush_qte(true)
				get_viewport().set_input_as_handled()
		else:
			# "[ESPAÇO] EMPURRÃO DE EMERGÊNCIA"
			if event.is_action_pressed("jump") or (event is InputEventKey and event.keycode == KEY_SPACE and event.is_pressed() and not event.is_echo()):
				resolve_ambush_qte(true)
				get_viewport().set_input_as_handled()
		return

	# 0.5. Suporte a Toque e Swipes para Celular / Mobile (Playgama Web)
	if event is InputEventScreenTouch:
		if event.pressed:
			is_touch_dragging = true
			touch_start_pos = event.position
			touch_start_time_ms = Time.get_ticks_msec()
			touch_drag_steer = 0.0
			if is_grappled and not is_resolving_grapple:
				resolve_grapple_qte(true)
				get_viewport().set_input_as_handled()
				return
			elif is_in_ambush:
				resolve_ambush_qte(true)
				get_viewport().set_input_as_handled()
				return
		else:
			is_touch_dragging = false
			touch_drag_steer = 0.0
			var delta_vec: Vector2 = event.position - touch_start_pos
			var elapsed_ms: int = Time.get_ticks_msec() - touch_start_time_ms
			if delta_vec.length() < 28.0 and elapsed_ms < 260:
				# Toque rápido na tela = Disparo / Ataque
				trigger_primary_action()
			elif delta_vec.y < -45.0 and absf(delta_vec.y) > absf(delta_vec.x):
				# Swipe para cima = Pulo
				request_jump()
			elif delta_vec.y > 45.0 and absf(delta_vec.y) > absf(delta_vec.x):
				# Swipe para baixo = Slide
				if is_on_floor() and not is_sliding:
					start_slide()
		return

	if event is InputEventScreenDrag and is_touch_dragging:
		var viewport_w: float = maxf(320.0, get_viewport().get_visible_rect().size.x)
		touch_drag_steer = clampf(event.relative.x / (viewport_w * 0.018), -1.0, 1.0)
		return

	# 1. Se estiver no Agarrão Cinemático (Grapple Cutscene), intercepta [F], [V] ou Botão Esquerdo do Mouse
	if is_grappled:
		if not is_resolving_grapple:
			var reacted: bool = false
			if event.is_action_pressed("melee_kill"):
				reacted = true
			elif event is InputEventKey and event.is_pressed() and not event.is_echo() and (event.keycode == KEY_F or event.keycode == KEY_V):
				reacted = true
			elif event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
				reacted = true

			if reacted:
				resolve_grapple_qte(true)
				get_viewport().set_input_as_handled()
		return

	# 2. Quick Melee (Golpe Rápido) com tecla [F], [V] ou ação melee_kill
	if event.is_action_pressed("melee_kill") or (event is InputEventKey and (event.keycode == KEY_F or event.keycode == KEY_V) and event.is_pressed() and not event.is_echo()):
		trigger_quick_melee()
		get_viewport().set_input_as_handled()
		return

	# 3. Seleção de Slot de Arma Ativa por Teclas [1] e [2]
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_1:
			if not GameController.mutator_melee_only:
				switch_to_slot(WeaponSlot.GLOCK)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_2:
			switch_to_slot(WeaponSlot.KNIFE)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_T or event.keycode == KEY_L:
			toggle_flashlight()
			get_viewport().set_input_as_handled()
			return

	# 4. Alternar Arma via Roda do Mouse (Wheel Up / Wheel Down)
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not GameController.mutator_melee_only:
				toggle_weapon_slot()
			get_viewport().set_input_as_handled()
			return

	# 5. Ação Primária pelo botão esquerdo do mouse (Tiro ou Estocada)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed() and not is_dead:
			trigger_primary_action()
			get_viewport().set_input_as_handled()
			return
	
	# 6. Pulo avulso
	if event.is_action_pressed("jump") or (event is InputEventKey and event.keycode == KEY_SPACE and event.is_pressed()):
		request_jump()
		
	# 7. Recarga manual com R (Glock)
	if event.is_action_pressed("reload") or (event is InputEventKey and event.keycode == KEY_R and event.is_pressed()):
		if active_slot == WeaponSlot.GLOCK and weapon_manager and weapon_manager.has_method("reload"):
			weapon_manager.reload()


func toggle_flashlight() -> void:
	if GameController.mutator_no_flashlight:
		return
	if flashlight:
		flashlight.visible = not flashlight.visible


func _physics_process(delta: float) -> void:
	if near_miss_cooldown > 0.0:
		near_miss_cooldown -= delta
	if adrenaline_timer > 0.0:
		adrenaline_timer -= delta
		if adrenaline_timer <= 0.0:
			adrenaline_timer = 0.0
			is_adrenaline_rush = false

	if is_dead:
		return

	# Trava corrida durante QTE de agarrão cinemático
	if is_grappled:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Trava movimentação durante a emboscada Anti-Camper
	if is_in_ambush:
		velocity = Vector3.ZERO
		move_and_slide()
		return
		
	_process_inputs(delta)
	_process_stamina(delta)
	_process_gravity_and_jump(delta)
	_process_lateral_movement(delta)
	_process_slide(delta)
	
	# Movimento do CharacterBody3D (Godot Jolt / Physics)
	move_and_slide()

	# Verificação da velocidade real no eixo Z de avanço (Sistema Anti-Camper)
	var forward_speed = abs(get_real_velocity().z)
	var is_game_over: bool = GameManager.is_game_over or GameController.is_game_over
	if forward_speed < 1.0 and not is_game_over and not is_in_struggle and not is_in_ambush:
		stuck_timer += delta
		if stuck_timer >= MAX_STUCK_TIME:
			trigger_ambush_qte()
			stuck_timer = 0.0
	else:
		stuck_timer = max(0.0, stuck_timer - delta * 2.0)
	
	# Trava a coordenada Y do jogador para nunca cair abaixo do asfalto (evita limbo/queda no vazio)
	if position.y < 0.0:
		position.y = 0.0
		velocity.y = 0.0
	if global_position.y < 0.0:
		global_position.y = 0.0
		velocity.y = 0.0

	# Processa colisões de slide contra obstáculos/carros para impedir empurrão para baixo
	_process_obstacle_collisions()
	
	# Constrange limites de pista (-8m a +8m) com ricochete suave
	_enforce_lane_boundaries()
	
	# Processamento de Câmera, Bobbing e Recoil
	_process_camera_tilt(delta)
	_process_recoil_and_sway(delta)
	
	# Disparo contínuo para armas automáticas
	_check_continuous_fire()


# --- SUPORTE TOUCH / MOBILE & MOUSE DRAG (PLAYGAMA / WEB / CELULAR) ---
var is_touch_dragging: bool = false
var touch_drag_steer: float = 0.0
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_start_time_ms: int = 0
func _process_inputs(_delta: float) -> void:
	current_steer_input = 0.0
	
	# Suporta tanto Action Maps configurados quanto teclas físicas diretas (A/D ou Setas) e Arrasto Touch Mobile
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		current_steer_input -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		current_steer_input += 1.0
	if absf(current_steer_input) < 0.01 and absf(touch_drag_steer) > 0.05:
		current_steer_input = touch_drag_steer
		touch_drag_steer = lerpf(touch_drag_steer, 0.0, 0.25)
		
	# Slide / Agachamento via Shift ou Ctrl
	var slide_pressed: bool = Input.is_action_pressed("slide") or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	if slide_pressed and not is_sliding and is_on_floor():
		start_slide()


## Processa consumo de estamina no sprint máximo (15/s) e recuperação suave no trote
func _process_stamina(delta: float) -> void:
	if is_dead:
		return

	# Sprint máximo ao pressionar W ou Seta Cima ou ação de avanço acelerado (ou Adrenalina ativa)
	var wants_sprint: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or (Input.is_action_pressed("slide") and not is_sliding)
	if (wants_sprint or is_adrenaline_rush) and not is_exhausted and not is_in_struggle and not is_in_ambush and is_on_floor():
		is_sprinting = true
		if not is_adrenaline_rush:
			current_stamina = maxf(0.0, current_stamina - 15.0 * delta)
			if current_stamina <= 0.0:
				current_stamina = 0.0
				is_exhausted = true
				is_sprinting = false
		else:
			current_stamina = max_stamina
	else:
		is_sprinting = false
		# Bônus de regeneração durante Combo ativo (x2+)
		var recovery_rate: float = 13.0
		if GameController.instance and GameController.instance.combo_multiplier >= 2:
			recovery_rate = 22.0
		current_stamina = minf(max_stamina, current_stamina + recovery_rate * delta)
		if is_exhausted and current_stamina >= 35.0:
			is_exhausted = false

	# Atualiza o HUD
	stamina_changed.emit(current_stamina, max_stamina, is_exhausted)
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("update_stamina"):
		hud_node.update_stamina(current_stamina, max_stamina, is_exhausted)


## Retorna o multiplicador de velocidade de corrida (+10% com a faca, +25% em sprint máximo, -35% se exausto)
func get_speed_multiplier() -> float:
	if is_dead or is_in_struggle or is_in_ambush:
		return 1.0
	var mult: float = 1.0
	if active_slot == WeaponSlot.KNIFE:
		mult *= 1.10
	if is_adrenaline_rush:
		mult *= 1.15 # Surto de velocidade da adrenalina
	if is_sprinting and not is_exhausted:
		mult *= 1.25 # Sprint máximo
	elif is_exhausted:
		mult *= 0.65 # Reduz a velocidade em 35% ao ficar sem fôlego
	return mult


# --- FÍSICA LATERAL COM INÉRCIA E DERRAPAGEM ---
func _process_lateral_movement(delta: float) -> void:
	var speed_mult: float = get_speed_multiplier()
	var target_vel_x: float = velocity.x
	
	if is_slipping_oil:
		oil_slip_timer -= delta
		if oil_slip_timer <= 0.0:
			oil_slip_timer = 0.0
			is_slipping_oil = false

	var current_friction: float = 2.0 if is_slipping_oil else lateral_friction
	
	if absf(current_steer_input) > 0.01:
		# Acelera na direção do input (com bônus de 10% se estiver com a faca)
		target_vel_x += current_steer_input * lateral_acceleration * speed_mult * delta
		var max_sp: float = (max_lateral_speed * 1.35 if is_slipping_oil else max_lateral_speed) * speed_mult
		target_vel_x = clampf(target_vel_x, -max_sp, max_sp)
	else:
		# Fricção e desaceleração inercial suave (baixa fricção durante derrapagem de óleo)
		target_vel_x = lerpf(target_vel_x, 0.0, current_friction * delta)
		if absf(target_vel_x) < 0.05:
			target_vel_x = 0.0
			
	if is_slipping_oil:
		target_vel_x += oil_slip_drift_dir * 14.0 * delta

	velocity.x = target_vel_x
	
	# Avanço físico real do jogador no eixo -Z
	if not is_dead and not is_in_struggle and not is_in_ambush:
		velocity.z = -(current_road_speed * speed_mult)
	else:
		velocity.z = 0.0


# --- LIMITES DE PISTA (-8.0m a +8.0m) ---
func _enforce_lane_boundaries() -> void:
	if global_position.x < min_lane_x:
		global_position.x = min_lane_x
		if velocity.x < 0.0:
			velocity.x = -velocity.x * border_bounciness
			add_camera_shake(0.2)
	elif global_position.x > max_lane_x:
		global_position.x = max_lane_x
		if velocity.x > 0.0:
			velocity.x = -velocity.x * border_bounciness
			add_camera_shake(0.2)


# --- PULO E GRAVIDADE ---
func _process_gravity_and_jump(delta: float) -> void:
	if not is_on_floor() and position.y > 0.0:
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
		if position.y < 0.0:
			position.y = 0.0
			velocity.y = 0.0


## Impede que o impacto da colisão física com o carro empurre o jogador para baixo do chão
func _process_obstacle_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is WreckedCar or (collider and collider.is_in_group("obstacles")):
			velocity.y = maxf(0.0, velocity.y)
			if position.y < 0.0:
				position.y = 0.0
			if global_position.y < 0.0:
				global_position.y = 0.0


## Trata colisão frontal com o carro destruído: aplica desaceleração, dano e parada em Z sem alterar Y
func handle_car_collision(car: Node3D) -> void:
	if is_dead:
		return
	# Trava a coordenada Y no asfalto imediatamente (impede afundar no limbo)
	velocity.y = maxf(0.0, velocity.y)
	if position.y < 0.0:
		position.y = 0.0
	if is_inside_tree() and global_position.y < 0.0:
		global_position.y = 0.0
		
	# Afasta suavemente para a faixa lateral livre mais próxima
	var car_x: float = (car.global_position.x if car.is_inside_tree() else car.position.x) if car else 0.0
	var my_x: float = global_position.x if is_inside_tree() else position.x
	var push_dir: float = 1.0 if my_x >= car_x else -1.0
	velocity.x = push_dir * 3.5
	add_camera_shake(0.35)

	# Aplica desaceleração imediata no avanço da rodovia
	if is_inside_tree():
		var tree := get_tree()
		if tree:
			var spawner = tree.get_first_node_in_group("world_spawner")
			if not spawner:
				spawner = find_parent("WorldSpawner")
			if spawner and "current_speed" in spawner:
				spawner.current_speed = maxf(spawner.base_speed * 0.5, spawner.current_speed - 4.5)


## Trata o esbarrão lateral nos carros: mantém a corrida em Z, repele suavemente para o lado livre,
## aplica tremor rápido na câmera com retorno lerp, toca som metálico e emite faíscas
func handle_car_side_scrape(car: Node3D, contact_pos: Vector3) -> void:
	if is_dead or is_grappled or is_in_ambush:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_side_scrape_time < 0.18:
		return
	last_side_scrape_time = now

	# 1. Não travar a corrida: Mantém a velocidade de avanço no eixo Z inalterada
	# (velocity.z é preservado integralmente)

	# Impede afundar no asfalto ou atravessar o chão
	velocity.y = maxf(0.0, velocity.y)
	if position.y < 0.0:
		position.y = 0.0
	if is_inside_tree() and global_position.y < 0.0:
		global_position.y = 0.0

	# 2. Repulsão Suave: Leve empurrão lateral de reflexo (deslocando o jogador cerca de 0.3m para o lado oposto do carro)
	var car_x: float = (car.global_position.x if car.is_inside_tree() else car.position.x) if car else 0.0
	var my_x: float = global_position.x if is_inside_tree() else position.x
	var push_dir: float = 1.0 if my_x >= car_x else -1.0

	if is_inside_tree():
		global_position.x = clampf(global_position.x + push_dir * 0.3, min_lane_x, max_lane_x)
	else:
		position.x = clampf(position.x + push_dir * 0.3, min_lane_x, max_lane_x)
	velocity.x = push_dir * 3.5

	# 3. Tremor Curto: Tremor rápido na Camera3D (+/- 1.5 graus no roll Z com retorno imediato via lerp)
	if camera:
		camera.rotation_degrees.z += randf_range(-1.5, 1.5)

	# 4. Áudio de Impacto: Som seco de metal amassando / raspando lataria
	AudioManager.play_car_scrape()

	# 5. Faíscas: CPUParticles3D de faíscas metálicas no ponto de contato entre a lateral do corpo e a lataria

	_spawn_metal_sparks(contact_pos, push_dir)


func _play_metal_scrape_sound() -> void:
	if not is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.name = "MetalScrapeAudioPlayer"
	player.stream = _get_metal_scrape_audio()
	player.volume_db = -4.0
	add_child(player)
	player.play()
	player.finished.connect(func():
		if is_instance_valid(player):
			player.queue_free()
	)


static func _get_metal_scrape_audio() -> AudioStreamWAV:
	if _shared_scrape_wav != null:
		return _shared_scrape_wav

	var sample_hz: int = 22050
	var duration: float = 0.25
	var total_frames: int = int(sample_hz * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = (1.0 - (t / duration)) * exp(-t * 4.5)
		var noise: float = randf_range(-1.0, 1.0)
		var screech: float = sin(t * TAU * 1650.0) * 0.3 + sin(t * TAU * 2380.0) * 0.25 + sin(t * TAU * 3120.0) * 0.15
		var sample_val: float = (noise * 0.55 + screech * 0.45) * env * 0.85
		var sample_int16: int = int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		byte_data.encode_s16(i * 2, sample_int16)

	_shared_scrape_wav = AudioStreamWAV.new()
	_shared_scrape_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_shared_scrape_wav.mix_rate = sample_hz
	_shared_scrape_wav.stereo = false
	_shared_scrape_wav.data = byte_data
	return _shared_scrape_wav


func _spawn_metal_sparks(contact_pos: Vector3, push_dir: float) -> void:
	if not is_inside_tree():
		return
	var sparks_scene = preload("res://scenes/MetalSparks.tscn")
	var sparks = sparks_scene.instantiate() as CPUParticles3D
	if not sparks:
		return
	var parent_node: Node = get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene
	if not parent_node:
		parent_node = self
	parent_node.add_child(sparks)
	sparks.global_position = contact_pos
	sparks.direction = Vector3(push_dir * 0.8, 0.5, randf_range(-0.4, 0.4)).normalized()


func request_jump() -> void:

	if is_dead:
		return
	if is_on_floor() and not is_sliding:
		velocity.y = jump_velocity
		jumped.emit()


# --- SLIDE / AGACHAMENTO ---
func start_slide() -> void:
	if is_dead:
		return
	is_sliding = true
	slide_timer = slide_duration
	_set_collision_slide_mode(true)
	slid.emit(true)


func _process_slide(delta: float) -> void:
	var target_cam_y: float = normal_camera_height
	
	if is_sliding:
		slide_timer -= delta
		target_cam_y = slide_camera_height
		if slide_timer <= 0.0 or not is_on_floor():
			is_sliding = false
			_set_collision_slide_mode(false)
			slid.emit(false)
			
	# Interpolação suave da altura do pivot da câmera
	if camera_pivot:
		camera_pivot.position.y = lerpf(camera_pivot.position.y, target_cam_y, slide_transition_speed * delta)


func _set_collision_slide_mode(sliding: bool) -> void:
	if not collision_shape or not (collision_shape.shape is CapsuleShape3D):
		return
	var cap := collision_shape.shape as CapsuleShape3D
	if sliding:
		cap.height = 0.90
		collision_shape.position.y = 0.45
	else:
		cap.height = 1.80
		collision_shape.position.y = 0.90


# --- INCLINAÇÃO DA CÂMERA (CAMERA ROLL / TILT) E ALINHAMENTO DO HORIZONTE ---
func _process_camera_tilt(delta: float) -> void:
	if not camera or is_dead:
		return
		
	# 1. Recuperação contínua imediata via lerp para zero dos eixos X (pitch) e Y (yaw)
	# para evitar desvios permanentes decorrentes de camera recoil, shake ou ricochete
	camera.rotation.x = lerpf(camera.rotation.x, 0.0, 18.0 * delta)
	camera.rotation.y = lerpf(camera.rotation.y, 0.0, 18.0 * delta)
	if absf(camera.rotation.x) < 0.0001:
		camera.rotation.x = 0.0
	if absf(camera.rotation.y) < 0.0001:
		camera.rotation.y = 0.0
		
	# 2. Trava ou limita rigorosamente a rotação Z (Roll) da Camera3D para manter pista e horizonte horizontais
	var target_roll: float = 0.0
	if not lock_camera_roll and absf(current_steer_input) > 0.01:
		# Limita a inclinação lateral ao esquivar para no máximo +/- 0.03 radianos
		var steer_ratio: float = -current_steer_input
		target_roll = clampf(steer_ratio * max_camera_tilt_rad, -max_camera_tilt_rad, max_camera_tilt_rad)
	
	if is_slipping_oil:
		target_roll += sin(oil_slip_timer * 18.0) * 0.085
	
	# Interpolação lerp com recuperação imediata para zero quando o jogador solta o movimento lateral
	var recovery_speed: float = 20.0 if (absf(current_steer_input) <= 0.01 or lock_camera_roll) else 12.0
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, recovery_speed * delta)
	if absf(camera.rotation.z) < 0.0001 or lock_camera_roll:
		camera.rotation.z = 0.0


# --- IMERSÃO FÍSICA: HEAD BOBBING EM 8 (LISSAJOUS CURVE) E FOV DINÂMICO ---
func _process_lissajous_head_bobbing(delta: float) -> void:
	if not camera or is_dead or is_grappled:
		return

	if is_on_floor() and not is_sliding:
		var prev_step_time: float = step_time
		step_time += delta * (current_road_speed / 10.5)
		if step_time > TAU * 50.0:
			step_time = fmod(step_time, TAU)

		# Sincronização dos passos da corrida com a oscilação da câmera (Head Bobbing):
		# O vale da oscilação vertical sin(step_time * 12.0) corresponde ao impacto da sola no asfalto molhado
		var prev_phase: float = sin(prev_step_time * 12.0)
		var curr_phase: float = sin(step_time * 12.0)
		if prev_phase > -0.72 and curr_phase <= -0.72:
			AudioManager.play_wet_footstep()

		camera.position.y = default_cam_y + sin(step_time * 12.0) * 0.04
		camera.position.x = default_cam_x + cos(step_time * 6.0) * 0.025
		camera.rotation.z = -sin(step_time * 6.0) * 0.015


		# Oscilação na respiração (camera bobbing irregular ao entrar em exaustão)
		if is_exhausted:
			var panting_t: float = step_time * 3.8
			camera.position.y += sin(panting_t) * 0.038 + sin(panting_t * 2.1) * 0.018
			camera.rotation.z += sin(panting_t * 1.6) * 0.022
			camera.rotation.x += sin(panting_t) * 0.016
	else:
		camera.position.y = lerpf(camera.position.y, default_cam_y, delta * 10.0)
		camera.position.x = lerpf(camera.position.x, default_cam_x, delta * 10.0)
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, delta * 10.0)


func _process_dynamic_fov(delta: float) -> void:
	if not camera or is_dead:
		return

	var speed_bonus_fov: float = clampf((current_road_speed - 10.5) * 0.85, 0.0, 9.0)
	var target_fov: float = base_fov + speed_bonus_fov # Escala dinamicamente com a velocidade da pista
	if is_sprinting and not is_exhausted:
		target_fov = sprint_fov + 5.5 + speed_bonus_fov # Sprint máximo agressivo
	elif is_adrenaline_rush:
		target_fov = sprint_fov + 7.5 + speed_bonus_fov # Rush de adrenalina intenso
	elif absf(current_steer_input) > 0.01 or is_sliding:
		target_fov = sprint_fov + 2.0 + speed_bonus_fov
	elif is_exhausted:
		target_fov = base_fov - 3.0 # Visão cansada e ligeiramente fechada

	camera.fov = lerpf(camera.fov, target_fov, delta * 7.5)


# --- INTERPOLAÇÃO FÍSICA: RECOIL SUAVE (LERP), WEAPON BOBBING E SWAY ---
func _process_recoil_and_sway(delta: float) -> void:
	if not viewmodel_anchor:
		return
		
	# 1. Recuperação suave do recuo angular no eixo X e posicional da arma via lerp
	target_recoil_rot = target_recoil_rot.lerp(Vector3.ZERO, recoil_recovery_speed * delta)
	target_recoil_pos = target_recoil_pos.lerp(Vector3.ZERO, recoil_recovery_speed * delta)
	
	current_recoil_rot = current_recoil_rot.lerp(target_recoil_rot, recoil_snappiness * delta)
	current_recoil_pos = current_recoil_pos.lerp(target_recoil_pos, recoil_snappiness * delta)
	
	# 2. Desativação momentânea da OmniLight3D alaranjada do clarão do tiro
	if muzzle_flash_timer > 0.0:
		muzzle_flash_timer -= delta
		if muzzle_flash_timer <= 0.0 and muzzle_flash_light:
			muzzle_flash_light.visible = false
			
	# 3. Interpolação física para que o nó da arma oscile ritmicamente enquanto o jogador corre (Weapon Bobbing)
	if is_on_floor() and not is_sliding:
		weapon_bob_phase += delta * weapon_bob_frequency
		if weapon_bob_phase > TAU:
			weapon_bob_phase -= TAU
			
		var target_bob_x := cos(weapon_bob_phase) * weapon_bob_amount.x
		var target_bob_y := sin(weapon_bob_phase * 2.0) * weapon_bob_amount.y
		var target_rot_x := sin(weapon_bob_phase * 2.0) * deg_to_rad(weapon_bob_rot_degrees.x)
		var target_rot_z := -cos(weapon_bob_phase) * deg_to_rad(weapon_bob_rot_degrees.y)
		
		var target_bob_pos := Vector3(target_bob_x, target_bob_y, 0.0)
		var target_bob_rot := Vector3(target_rot_x, 0.0, target_rot_z)
		
		current_weapon_bob_pos = current_weapon_bob_pos.lerp(target_bob_pos, weapon_bob_smooth * delta)
		current_weapon_bob_rot = current_weapon_bob_rot.lerp(target_bob_rot, weapon_bob_smooth * delta)
	else:
		current_weapon_bob_pos = current_weapon_bob_pos.lerp(Vector3.ZERO, weapon_bob_smooth * delta)
		current_weapon_bob_rot = current_weapon_bob_rot.lerp(Vector3.ZERO, weapon_bob_smooth * delta)
		
	# 4. Sway inercial lateral (arma arrasta e inclina suavemente no sentido oposto ao movimento)
	var target_sway_x: float = -velocity.x * sway_intensity
	lateral_sway_offset.x = lerpf(lateral_sway_offset.x, target_sway_x, sway_smooth * delta)
	var lateral_tilt_z: float = clampf(-velocity.x * 0.012, -0.09, 0.09)
	
	# 5. Aplica posições e rotações compostas no nó da arma (viewmodel_anchor)
	var switch_offset := Vector3(0.0, weapon_switch_y_offset, 0.0)
	viewmodel_anchor.position = initial_viewmodel_pos + switch_offset + current_recoil_pos + current_weapon_bob_pos + lateral_sway_offset
	viewmodel_anchor.rotation = initial_viewmodel_rot + current_recoil_rot + current_weapon_bob_rot + Vector3(0.0, 0.0, lateral_tilt_z)

	# 6. Balanço da faca quando selecionada e não executando estocada
	if knife_view_model and active_slot == WeaponSlot.KNIFE and not knife_view_model.is_attacking:
		knife_view_model.position = knife_view_model.default_pos + current_weapon_bob_pos * 0.7 + lateral_sway_offset * 0.5
		knife_view_model.rotation = knife_view_model.default_rot + current_weapon_bob_rot * 0.7


## No disparo: aciona leve tranco vertical de recuo na câmera empinando para cima
func apply_weapon_recoil(intensity: float = 1.0) -> void:
	if camera and not is_dead:
		# -X no Godot 3D empina a visão para cima (recuo vertical do disparo)
		camera.rotation.x -= deg_to_rad(0.55 * intensity)
		camera.rotation.x = maxf(camera.rotation.x, deg_to_rad(-3.0))


func add_camera_shake(amount: float) -> void:
	if camera and not is_dead:
		camera.rotation.x += randf_range(-amount, amount) * 0.015
		camera.rotation.y += randf_range(-amount, amount) * 0.015
		if lock_camera_roll:
			camera.rotation.z = 0.0


## Reação cinemática de Near-Miss (Tremor forte, Roll direcional, suspiro ofegante e time dilation)
func trigger_near_miss(direction_sign: float, threat_zombie: Zombie = null) -> void:
	if is_dead or near_miss_cooldown > 0.0:
		return
	near_miss_cooldown = 0.35

	# 1. Tremor de impacto na câmera
	add_camera_shake(0.65)

	# 2. Jolt e inclinação lateral direcional da câmera (Roll & Lateral offset)
	if camera:
		var roll_impulse: float = deg_to_rad(2.5 * direction_sign)
		camera.rotation.z += roll_impulse

		var cam_tw := create_tween()
		var cam_offset_x: float = 0.08 * direction_sign
		cam_tw.tween_property(camera, "position:x", cam_offset_x, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		cam_tw.tween_property(camera, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# 3. Áudio de deslocamento de ar e suspiro de susto do jogador
	AudioManager.play_near_miss_whoosh()
	AudioManager.play_player_gasp()

	# 4. Micro Time Dilation cinematográfico (80ms de tempo desacelerado para adrenalina)
	Engine.time_scale = 0.78
	var slowmo_tw := create_tween()
	slowmo_tw.tween_interval(0.08)
	slowmo_tw.tween_property(Engine, "time_scale", 1.0, 0.12).set_trans(Tween.TRANS_QUAD)

	# 5. Ativa estado temporário de adrenalina no jogador
	is_adrenaline_rush = true

	near_miss_occurred.emit(direction_sign, threat_zombie)


# --- DISPARO E COMBATE ---
func trigger_primary_action() -> void:
	if is_dead or is_switching_weapon or is_quick_melee or is_in_struggle:
		return
	if active_slot == WeaponSlot.GLOCK:
		trigger_shoot()
	elif active_slot == WeaponSlot.KNIFE:
		trigger_knife_attack()


func trigger_knife_attack() -> void:
	if knife_view_model and not knife_view_model.is_attacking:
		knife_view_model.stab_attack()


## Executa golpe rápido com a faca tática:
## Se Glock empunhada: Glock abaixa rapidamente (0.08s), faca entra e executa estocada, Glock retorna à mira (0.12s)
## Se Faca já empunhada: executa a estocada diretamente
func trigger_quick_melee() -> void:
	if is_dead or is_quick_melee or is_switching_weapon or is_in_struggle:
		return

	if active_slot == WeaponSlot.KNIFE:
		trigger_knife_attack()
		return

	if not knife_view_model or not viewmodel_anchor:
		return

	is_quick_melee = true
	quick_melee_triggered.emit()

	# 1. Glock abaixa rapidamente (0.08s)
	var lower_tw := create_tween()
	lower_tw.tween_property(self, "weapon_switch_y_offset", -0.55, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lower_tw.chain().tween_callback(func():
		if not is_instance_valid(viewmodel_anchor) or not is_instance_valid(knife_view_model):
			is_quick_melee = false
			return
		viewmodel_anchor.visible = false
		knife_view_model.visible = true
		knife_view_model.position = knife_view_model.default_pos
		knife_view_model.rotation = knife_view_model.default_rot

		# 2. Faca executa a estocada procedural com MeleeRay e impacto de sangue
		knife_view_model.stab_attack(func():
			if not is_instance_valid(viewmodel_anchor) or not is_instance_valid(knife_view_model):
				is_quick_melee = false
				return
			# 3. Faca se recolhe e Glock retorna imediatamente à mira/tiro (0.12s)
			var knife_hide_tw := knife_view_model.lower_knife(0.06)
			knife_hide_tw.chain().tween_callback(func():
				if not is_instance_valid(viewmodel_anchor):
					is_quick_melee = false
					return
				viewmodel_anchor.visible = true
				if weapon_manager and is_instance_valid(weapon_manager):
					weapon_manager.visible = true
					if weapon_manager.has_method("ensure_weapon_visible"):
						weapon_manager.ensure_weapon_visible()
				var raise_tw := create_tween()
				raise_tw.tween_property(self, "weapon_switch_y_offset", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				raise_tw.chain().tween_callback(func():
					is_quick_melee = false
				)
			)
		)
	)


## Alterna ciclicamente entre Glock e Faca
func toggle_weapon_slot() -> void:
	if active_slot == WeaponSlot.GLOCK:
		switch_to_slot(WeaponSlot.KNIFE)
	else:
		switch_to_slot(WeaponSlot.GLOCK)


## Troca de arma ativa com transição visual polida
func switch_to_slot(new_slot: WeaponSlot) -> void:
	if GameController.mutator_melee_only and new_slot == WeaponSlot.GLOCK:
		return
	if new_slot == active_slot or is_switching_weapon or is_quick_melee or is_dead or is_in_struggle:
		return

	is_switching_weapon = true

	if new_slot == WeaponSlot.KNIFE:
		# Glock abaixa e faca sobe
		var lower_tw := create_tween()
		lower_tw.tween_property(self, "weapon_switch_y_offset", -0.55, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		lower_tw.chain().tween_callback(func():
			if is_instance_valid(viewmodel_anchor):
				viewmodel_anchor.visible = false
			active_slot = WeaponSlot.KNIFE
			weapon_switched.emit(active_slot)
			if knife_view_model and is_instance_valid(knife_view_model):
				var raise_tw := knife_view_model.raise_knife(0.12)
				raise_tw.chain().tween_callback(func():
					is_switching_weapon = false
				)
			else:
				is_switching_weapon = false
		)
	else:
		# Faca abaixa e Glock sobe
		if knife_view_model and is_instance_valid(knife_view_model):
			var lower_tw := knife_view_model.lower_knife(0.10)
			lower_tw.chain().tween_callback(func():
				active_slot = WeaponSlot.GLOCK
				weapon_switched.emit(active_slot)
				if is_instance_valid(viewmodel_anchor):
					viewmodel_anchor.visible = true
				if weapon_manager and is_instance_valid(weapon_manager):
					weapon_manager.visible = true
					if weapon_manager.has_method("ensure_weapon_visible"):
						weapon_manager.ensure_weapon_visible()
				var raise_tw := create_tween()
				raise_tw.tween_property(self, "weapon_switch_y_offset", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				raise_tw.chain().tween_callback(func():
					is_switching_weapon = false
				)
			)
		else:
			active_slot = WeaponSlot.GLOCK
			weapon_switched.emit(active_slot)
			if is_instance_valid(viewmodel_anchor):
				viewmodel_anchor.visible = true
			if weapon_manager and is_instance_valid(weapon_manager):
				weapon_manager.visible = true
				if weapon_manager.has_method("ensure_weapon_visible"):
					weapon_manager.ensure_weapon_visible()
			weapon_switch_y_offset = 0.0
			is_switching_weapon = false


func trigger_shoot() -> void:
	if is_dead:
		return
	if weapon_manager and weapon_manager.has_method("shoot"):
		var fired: bool = weapon_manager.shoot()
		if fired:
			fired_weapon.emit()
			# Pega o recuo da arma se configurado no WeaponManager
			var recoil_mult: float = 1.0
			if "current_weapon_recoil" in weapon_manager:
				recoil_mult = weapon_manager.current_weapon_recoil
			apply_weapon_recoil(recoil_mult)


func _check_continuous_fire() -> void:
	if is_dead or is_switching_weapon or is_quick_melee:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if active_slot == WeaponSlot.GLOCK:
			if weapon_manager and "is_automatic" in weapon_manager and weapon_manager.is_automatic:
				trigger_shoot()


# --- RECEBER DANO E CURA ---
func take_damage(amount: float, _source_name: String = "") -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	add_camera_shake(0.35)
	
	if health <= 0.0:
		die()


## Cura o jogador ao coletar Kit Médico Militar
func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("flash_heal_feedback"):
		hud_node.flash_heal_feedback(int(amount))


## Ativa o modo de Adrenalina Máxima (fôlego infinito e aumento de velocidade)
func trigger_adrenaline_rush(duration: float = 4.5) -> void:
	if is_dead:
		return
	is_adrenaline_rush = true
	adrenaline_timer = maxf(adrenaline_timer, duration)
	current_stamina = max_stamina
	is_exhausted = false
	stamina_changed.emit(current_stamina, max_stamina, is_exhausted)
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("flash_adrenaline_pickup"):
		hud_node.flash_adrenaline_pickup(duration)


## Ativa a derrapagem inercial descontrolada por mancha de óleo
func trigger_oil_slip(duration: float = 1.6) -> void:
	if is_dead or is_in_struggle or is_in_ambush:
		return
	is_slipping_oil = true
	oil_slip_timer = duration
	oil_slip_drift_dir = (1.0 if randf() > 0.5 else -1.0) if absf(velocity.x) < 0.5 else signf(velocity.x)
	velocity.x += oil_slip_drift_dir * 4.5
	add_camera_shake(0.28)
	if AudioManager.instance:
		AudioManager.instance.play_oil_skid()
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("flash_oil_slip_alert"):
		hud_node.flash_oil_slip_alert()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_grappled = false
	Engine.time_scale = 1.0

	# 1. Congela a progressão global do mundo e entidades
	GameManager.is_game_over = true
	GameController.is_game_over = true

	# 2. Trava movimentação e entradas
	velocity = Vector3.ZERO
	current_steer_input = 0.0

	# 3. Animação de queda física da arma (desce em Y e gira para fora em 0.25s)
	_drop_weapon_on_death()

	# 4. Transição cinemática de queda da câmera 3D
	play_camera_death_fall()

	player_died.emit()

	# 5. Notifica o GameController para transição e tela de Game Over
	if GameController.instance and is_instance_valid(GameController.instance):
		GameController.instance.trigger_game_over()


## Queda rápida da arma da mão ao morrer (descendo no eixo Y e girando para fora da tela em 0.25s)
func _drop_weapon_on_death() -> void:
	var weapon_node: Node3D = viewmodel_anchor if (viewmodel_anchor and viewmodel_anchor.visible) else (weapon_manager as Node3D)
	if weapon_node and weapon_node.visible:
		var drop_tween := create_tween()
		drop_tween.set_parallel(true)
		drop_tween.tween_property(weapon_node, "position:y", weapon_node.position.y - 0.75, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		drop_tween.tween_property(weapon_node, "rotation_degrees:x", weapon_node.rotation_degrees.x - 45.0, 0.25)
		drop_tween.tween_property(weapon_node, "rotation_degrees:z", weapon_node.rotation_degrees.z + 30.0, 0.25)
		drop_tween.chain().tween_callback(func():
			if is_instance_valid(weapon_node):
				weapon_node.visible = false
		)

	if knife_view_model and knife_view_model.visible:
		var knife_drop := create_tween()
		knife_drop.set_parallel(true)
		knife_drop.tween_property(knife_view_model, "position:y", knife_view_model.position.y - 0.75, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		knife_drop.tween_property(knife_view_model, "rotation_degrees:x", knife_view_model.rotation_degrees.x - 45.0, 0.25)
		knife_drop.chain().tween_callback(func():
			if is_instance_valid(knife_view_model):
				knife_view_model.visible = false
		)


## Transição de queda da Camera3D: decai Y de 1.6m para 0.25m em 0.4s e inclina Z em 65 graus
func play_camera_death_fall() -> void:
	if not camera:
		return
	if camera_pivot:
		camera_pivot.position.y = 0.0
	camera.position.y = 1.6

	var fall_tween := create_tween()
	fall_tween.set_parallel(true)
	# camera.position.y decai de 1.6m para 0.25m em 0.4s (corpo caindo no chão)
	fall_tween.tween_property(camera, "position:y", 0.25, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# camera.rotation_degrees.z inclina para 65 graus (visão tombando de lado no asfalto)
	fall_tween.tween_property(camera, "rotation_degrees:z", 65.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ==============================================================================
# CUTSCENE CINEMÁTICA DE AGARRÃO E REAÇÃO DE FACA TÁTICA (GRAPPLE CUTSCENE)
# ==============================================================================

## Inicia o estado de agarrão cinemático em primeira pessoa quando o zumbi colide frontalmente
func start_zombie_grapple(zombie: Node3D) -> void:
	if is_dead or is_grappled or is_in_ambush or is_resolving_grapple:
		return

	is_grappled = true
	is_in_struggle = true
	current_grapple_zombie = zombie
	grapple_time_remaining = GRAPPLE_DURATION # 1.6 segundos em tempo real
	is_resolving_grapple = false
	has_played_heartbeat_warning = false

	# 1. Trave a corrida e a velocidade do Player
	velocity = Vector3.ZERO
	current_steer_input = 0.0

	# 2. Oculte imediatamente o Viewmodel da Glock e as luvas
	if viewmodel_anchor:
		viewmodel_anchor.visible = false
	if weapon_manager:
		weapon_manager.visible = false
	if knife_view_model:
		knife_view_model.visible = false

	# 3. Traga o zumbi colidido para frente imediata da Camera3D:
	# Posição: 0.75m à frente da câmera no eixo -Z, com a cabeça na altura da linha de visão
	# Rotação: voltado 100% de frente para o jogador
	if zombie and is_instance_valid(zombie):
		if zombie.has_method("enter_grapple_cutscene"):
			zombie.enter_grapple_cutscene(camera)
		else:
			var cam_pos: Vector3 = camera.global_position if camera else global_position + Vector3(0, 1.65, 0)
			var fwd: Vector3 = -camera.global_transform.basis.z if camera else Vector3(0, 0, -1)
			fwd.y = 0.0
			fwd = fwd.normalized()
			if fwd.length_squared() < 0.01:
				fwd = Vector3(0.0, 0.0, -1.0)
			var target_pos: Vector3 = cam_pos + fwd * 0.75
			target_pos.y = maxf(0.0, cam_pos.y - 1.58)
			zombie.global_position = target_pos
			zombie.global_rotation = Vector3.ZERO

	# 4. Altere a escala de tempo para desaceleração dramática: Engine.time_scale = 0.25 (tempo de leitura e reação justa)
	Engine.time_scale = 0.25

	# 5. Exiba no centro da tela indicador de ação emergencial estilizado com barra circular
	var hud_node: GameHUD = _get_hud_node()
	if hud_node:
		if hud_node.has_method("show_grapple_qte"):
			hud_node.show_grapple_qte(GRAPPLE_DURATION)
		elif hud_node.has_method("show_emergency_prompt"):
			hud_node.show_emergency_prompt(GRAPPLE_DURATION)

	emergency_struggle_started.emit(GRAPPLE_DURATION)
	qte_grapple_started.emit(GRAPPLE_DURATION, 1)


## Processa tremor corporal da câmera (+/- 2 graus), trava zumbi a 0.75m e esgota o tempo em 1.6s real
func _process_grapple_struggle(delta: float) -> void:
	if is_resolving_grapple or is_dead:
		return

	# 1. Tremor contínuo na Camera3D simulando a luta corporal (+/- 2 graus nos eixos X e Z)
	if camera:
		var struggle_pitch: float = deg_to_rad(randf_range(-2.0, 2.0))
		var struggle_roll: float = deg_to_rad(randf_range(-2.0, 2.0))
		camera.rotation.x = struggle_pitch
		camera.rotation.z = struggle_roll

	# 2. Mantém o zumbi colidido a 0.75m à frente da câmera voltado 100% de frente
	if current_grapple_zombie and is_instance_valid(current_grapple_zombie):
		var cam_pos: Vector3 = camera.global_position if camera else global_position + Vector3(0, 1.65, 0)
		var fwd: Vector3 = -camera.global_transform.basis.z if camera else Vector3(0, 0, -1)
		fwd.y = 0.0
		fwd = fwd.normalized()
		if fwd.length_squared() < 0.01:
			fwd = Vector3(0.0, 0.0, -1.0)
		var target_pos: Vector3 = cam_pos + fwd * 0.75
		target_pos.y = maxf(0.0, cam_pos.y - 1.58)
		current_grapple_zombie.global_position = target_pos
		current_grapple_zombie.global_rotation = Vector3.ZERO

	# 3. Temporizador de 1.6s em tempo real sob Engine.time_scale = 0.25
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	grapple_time_remaining -= real_delta

	# Pulso sonoro de aviso (batimento cardíaco alto) aos 0.4s restantes
	if grapple_time_remaining <= 0.4 and not has_played_heartbeat_warning:
		has_played_heartbeat_warning = true
		AudioManager.play_heartbeat_warning()

	var hud_node: GameHUD = _get_hud_node()
	if hud_node:
		if hud_node.has_method("update_grapple_timer"):
			hud_node.update_grapple_timer(grapple_time_remaining, GRAPPLE_DURATION)
		elif hud_node.has_method("update_emergency_timer"):
			hud_node.update_emergency_timer(grapple_time_remaining, GRAPPLE_DURATION)

	qte_progress_updated.emit(1, 1, maxf(0.0, grapple_time_remaining))

	# Falha se o tempo de 1.6s real expirar sem ação do jogador
	if grapple_time_remaining <= 0.0:
		resolve_grapple_qte(false)


## Resolução do QTE: Sucesso com faca tática vs Derrota fatal
func resolve_grapple_qte(success: bool) -> void:
	if not is_grappled or is_resolving_grapple:
		return

	is_resolving_grapple = true

	var hud_node: GameHUD = _get_hud_node()
	if hud_node:
		if hud_node.has_method("hide_grapple_qte"):
			hud_node.hide_grapple_qte()
		elif hud_node.has_method("hide_emergency_prompt"):
			hud_node.hide_emergency_prompt()

	if success:
		# SUCESSO:
		# 1. Torne visível o modelo da faca ("tactical knife 3d model.glb") subindo rapidamente pelo canto inferior direito da tela.
		# 2. Execute a estocada procedural frontal com o Tween cravando a lâmina no peito/queixo do zumbi.
		# 3. Instancie o efeito de sangue BloodImpact.tscn no ponto da lâmina com gotas espirrando na lente.
		# 4. Dispare no zumbi a animação de queda para trás ("zombie falling.glb") e empurre-o fisicamente para trás.
		if knife_view_model and is_instance_valid(knife_view_model):
			knife_view_model.execute_grapple_stab(
				func():
					# Ápice da cravada da lâmina
					var hit_pos: Vector3 = (current_grapple_zombie.global_position + Vector3(0.0, 1.40, -0.05)) if (current_grapple_zombie and is_instance_valid(current_grapple_zombie)) else (camera.global_position + -camera.global_transform.basis.z * 0.65)
					_spawn_knife_blood_impact(hit_pos)

					# Som de lâmina cortando carne + borrifo líquido + corpo do zumbi caindo no asfalto
					AudioManager.play_knife_stab()

					# Gotas espirrando na lente
					if hud_node and hud_node.has_method("show_blood_lens_splatter"):
						hud_node.show_blood_lens_splatter()

					# Animação de queda para trás e empurrão físico no zumbi
					if current_grapple_zombie and is_instance_valid(current_grapple_zombie):
						if current_grapple_zombie.has_method("resolve_grapple_death"):
							current_grapple_zombie.resolve_grapple_death(2.2)
						elif current_grapple_zombie.has_method("die"):
							current_grapple_zombie.die(false)

					add_camera_shake(0.45),
				func():
					_finish_grapple_success()
			)
		else:

			if current_grapple_zombie and is_instance_valid(current_grapple_zombie):
				if current_grapple_zombie.has_method("resolve_grapple_death"):
					current_grapple_zombie.resolve_grapple_death(2.2)
				elif current_grapple_zombie.has_method("die"):
					current_grapple_zombie.die(false)
			_finish_grapple_success()
	else:
		# FALHA: Tempo esgota sem o golpe
		_execute_grapple_failure()


## Finalização do sucesso: restaura escala de tempo 1.0, Glock retorna em 0.3s e retoma a corrida
func _finish_grapple_success() -> void:
	# Restaura escala de tempo
	Engine.time_scale = 1.0

	# Glock volta para as mãos do jogador em 0.3s
	_restore_glock_after_grapple()

	# Restaura inclinação da câmera
	if camera:
		camera.rotation.x = 0.0
		camera.rotation.z = 0.0

	is_grappled = false
	is_in_struggle = false
	is_resolving_grapple = false
	current_grapple_zombie = null

	emergency_struggle_ended.emit(true)
	qte_grapple_ended.emit(true)

	# Dá um impulso leve para a frente na corrida
	velocity.x = randf_range(-0.6, 0.6)
	if is_inside_tree():
		var spawner = get_tree().get_first_node_in_group("world_spawner")
		if not spawner:
			spawner = get_tree().get_first_node_in_group("spawner")
		if spawner and "current_speed" in spawner:
			spawner.current_speed = minf(spawner.max_speed, spawner.current_speed + 1.8)


## Faz a arma/Glock voltar para as mãos do jogador em 0.3s
func _restore_glock_after_grapple() -> void:
	if active_slot == WeaponSlot.GLOCK:
		if viewmodel_anchor:
			viewmodel_anchor.visible = true
		if weapon_manager:
			weapon_manager.visible = true
			if weapon_manager.has_method("ensure_weapon_visible"):
				weapon_manager.ensure_weapon_visible()
		weapon_switch_y_offset = -0.55
		var raise_tw := create_tween()
		raise_tw.tween_property(self, "weapon_switch_y_offset", 0.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elif active_slot == WeaponSlot.KNIFE:
		if knife_view_model:
			knife_view_model.visible = true
			knife_view_model.position = knife_view_model.default_pos
			knife_view_model.rotation = knife_view_model.default_rot


## Instancia efeito de sangue no ponto exato da lâmina com gotas espirrando na lente
func _spawn_knife_blood_impact(hit_pos: Vector3) -> void:
	var blood_scene := preload("res://scenes/BloodImpact.tscn")
	var blood: CPUParticles3D = blood_scene.instantiate() as CPUParticles3D
	if not blood:
		return
	var parent_node: Node = get_parent() if get_parent() else self
	parent_node.add_child(blood)
	blood.global_position = hit_pos
	blood.direction = Vector3(0.0, 0.35, 1.0) # Espirra contra a lente da câmera


## Execução da derrota quando o tempo esgota: puxão violento para baixo, mordida fatal e Game Over
func _execute_grapple_failure() -> void:
	Engine.time_scale = 1.0

	# 1. A tela sofre um puxão violento para baixo
	if camera:
		var pull_tw := create_tween()
		pull_tw.set_parallel(true)
		pull_tw.tween_property(camera, "rotation_degrees:x", -32.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		pull_tw.tween_property(camera, "position:y", 0.45, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# 2. O zumbi cobre toda a visão
	if current_grapple_zombie and is_instance_valid(current_grapple_zombie):
		var cam_p: Vector3 = camera.global_position if camera else global_position + Vector3(0, 1.65, 0)
		current_grapple_zombie.global_position = cam_p + Vector3(0.0, -0.28, -0.32)

	# 3. Toca som de mordida letal
	_play_bite_sound()

	# 4. Flash na vinheta de dano
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("flash_damage_vignette"):
		hud_node.flash_damage_vignette(0.95)

	emergency_struggle_ended.emit(false)
	qte_grapple_ended.emit(false)

	is_grappled = false
	is_in_struggle = false
	is_resolving_grapple = false
	current_grapple_zombie = null

	# 5. Dispara a transição de "Você Não Sobreviveu"
	take_damage(999.0, "Zombie Fatal Bite")
	die()


# Métodos de compatibilidade com chamadas prévias
func start_emergency_struggle(zombie: Node3D) -> void:
	start_zombie_grapple(zombie)

func execute_emergency_knife_strike() -> void:
	resolve_grapple_qte(true)

func _fail_emergency_struggle() -> void:
	resolve_grapple_qte(false)

func handle_qte_press() -> void:
	resolve_grapple_qte(true)

func resolve_grapple(success: bool) -> void:
	resolve_grapple_qte(success)


# ==============================================================================
# LIMPEZA DE PARTÍCULAS NA VISÃO (TELA 100% LIMPA E NÍTIDA)
# ==============================================================================

func _remove_unwanted_particles() -> void:
	# Localiza e remove nós residuais de vento/poeira indesejados
	var nodes_to_check: Array[Node] = []
	if camera:
		nodes_to_check.append_array(camera.get_children())
	nodes_to_check.append_array(get_children())
	
	for node in nodes_to_check:
		if node.name.begins_with("WindParticles") or node.name.begins_with("DustParticles"):
			node.queue_free()


## Recuperação suave do Screen Shake / Recoil de pitch da câmera (Camera3D.rotation.x) de volta ao repouso
func _process_camera_recoil_recovery(delta: float) -> void:
	if camera and not is_dead and not is_grappled:
		camera.rotation.x = lerpf(camera.rotation.x, 0.0, delta * 18.0)
		if absf(camera.rotation.x) < 0.0001:
			camera.rotation.x = 0.0


# ==============================================================================
# EMBOSCADA CINEMÁTICA E QTE DE EMERGÊNCIA (SISTEMA ANTI-CAMPER)
# ==============================================================================

## Dispara emboscada de zumbi por ficar preso/camperando
func trigger_ambush_qte() -> void:
	if is_dead or is_in_ambush or is_in_struggle:
		return

	is_in_ambush = true
	is_in_struggle = true
	ambush_time_remaining = AMBUSH_DURATION # 0.9s em tempo real
	velocity = Vector3.ZERO
	current_steer_input = 0.0

	# Reduz a escala de tempo global
	Engine.time_scale = 0.3

	# Indicador de perigo crítico conforme arsenal
	ambush_requires_knife = (knife_charges > 0)
	var prompt_text: String = "[F] APUNHALAR AGORA!" if ambush_requires_knife else "[ESPAÇO] EMPURRÃO DE EMERGÊNCIA"

	# Instancia um zumbi diretamente a 1.2m na frente da câmera (ou subindo pelo capô do carro)
	_spawn_ambush_zombie()

	# Exibe na tela o indicador de perigo crítico
	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("show_ambush_prompt"):
		hud_node.show_ambush_prompt(prompt_text, AMBUSH_DURATION)

	add_camera_shake(0.4)


func _spawn_ambush_zombie() -> void:
	var z_scene := preload("res://scenes/Zombie.tscn")
	ambush_zombie = z_scene.instantiate() as Zombie
	ambush_zombie.name = "AmbushZombie"
	ambush_zombie.is_pooled = false
	ambush_zombie.speed = 0.0
	ambush_zombie.road_speed = 0.0

	# Posição diretamente a 1.2m na frente da câmera
	var cam_pos: Vector3 = camera.global_position if camera else global_position + Vector3(0, 1.6, 0)
	var fwd: Vector3 = -camera.global_transform.basis.z if camera else Vector3(0, 0, -1)
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3(0, 0, -1)

	var spawn_pos: Vector3 = global_position + fwd * 1.2
	spawn_pos.y = 0.0

	# Virado de frente em postura agressiva
	ambush_zombie.position = spawn_pos
	ambush_zombie.rotation_degrees = Vector3(0.0, 0.0, 0.0)

	if get_parent():
		get_parent().add_child(ambush_zombie)
		ambush_zombie.global_position = spawn_pos

	if ambush_zombie.animation_player:
		if ambush_zombie.animation_player.has_animation("zombie running fast"):
			ambush_zombie.animation_player.play("zombie running fast")
		elif ambush_zombie.animation_player.has_animation("undead zombie walking"):
			ambush_zombie.animation_player.play("undead zombie walking")


func _process_ambush_struggle(delta: float) -> void:
	# Janela de reação rápida: 0.9 segundos em tempo real
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	ambush_time_remaining -= real_delta

	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("update_ambush_timer"):
		hud_node.update_ambush_timer(ambush_time_remaining, AMBUSH_DURATION)

	if ambush_time_remaining <= 0.0:
		resolve_ambush_qte(false)


func resolve_ambush_qte(success: bool) -> void:
	if not is_in_ambush:
		return

	var hud_node: GameHUD = _get_hud_node()
	if hud_node and hud_node.has_method("hide_ambush_prompt"):
		hud_node.hide_ambush_prompt()

	if success:
		Engine.time_scale = 1.0

		if ambush_requires_knife:
			knife_charges = max(0, knife_charges - 1)
			knife_charges_changed.emit(knife_charges)
			if knife_view_model and is_instance_valid(knife_view_model):
				knife_view_model.visible = true
				knife_view_model.stab_attack()
			if ambush_zombie and is_instance_valid(ambush_zombie):
				ambush_zombie.take_damage(999.0, ambush_zombie.global_position + Vector3(0.0, 1.4, 0.0), Vector3(0.0, 0.0, 1.0), true)
		else:
			# Empurrão de emergência com sangue
			if ambush_zombie and is_instance_valid(ambush_zombie):
				ambush_zombie.take_damage(999.0, ambush_zombie.global_position + Vector3(0.0, 1.2, 0.0), Vector3(0.0, 0.4, 1.0), false)

		add_camera_shake(0.35)

		# Desvencilha-se do carro com um recuo automático para o lado livre da pista
		var side_push: float = -8.0 if global_position.x >= 0.0 else 8.0
		velocity.x = side_push
		# Recuo em Z para descolar da lataria do veículo imediatamente
		global_position.z += 0.8

		stuck_timer = 0.0
		is_in_ambush = false
		is_in_struggle = false
		ambush_zombie = null
	else:
		# Falhou ou não reagiu no tempo de 0.9s: o zumbi agarra a visão, toca o som de mordida e executa Game Over
		Engine.time_scale = 1.0
		if ambush_zombie and is_instance_valid(ambush_zombie):
			var cam_p: Vector3 = camera.global_position if camera else global_position + Vector3(0, 1.6, 0)
			ambush_zombie.global_position = cam_p + Vector3(0.0, -0.4, -0.45)

		_play_bite_sound()
		is_in_ambush = false
		is_in_struggle = false
		ambush_zombie = null
		take_damage(999.0, "Ambush Zombie Fatal Bite")
		die()


func _play_bite_sound() -> void:
	if not is_inside_tree():
		return
	var audio_player := AudioStreamPlayer.new()
	audio_player.name = "AmbushBiteAudioPlayer"
	audio_player.stream = _create_bite_audio()
	add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(func():
		if is_instance_valid(audio_player):
			audio_player.queue_free()
	)


static func _create_bite_audio() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.35
	var total_frames: int = int(sample_hz * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 12.0)
		var noise: float = randf_range(-1.0, 1.0)
		var tone: float = sin(t * TAU * 140.0) * 0.4 + sin(t * TAU * 70.0) * 0.3
		var sample_val: float = (noise * 0.65 + tone) * env * 0.95
		var sample_int16: int = int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		byte_data.encode_s16(i * 2, sample_int16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_hz
	wav.stereo = false
	wav.data = byte_data
	return wav


func _get_hud_node() -> GameHUD:
	if is_inside_tree():
		var tree := get_tree()
		if tree:
			var h = tree.get_first_node_in_group("hud") as GameHUD
			if h:
				return h
			if get_parent():
				return get_parent().find_child("HUD", true, false) as GameHUD
	return null

