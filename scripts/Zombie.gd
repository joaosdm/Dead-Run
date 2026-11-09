class_name Zombie
extends CharacterBody3D

## Dead Run - Zombie Controller & Animation State Machine (Godot 4.3 - Web / Pooling Optimized)
## Carrega modelos 3D articulados (Clássico ou Zombie No Arm), gerencia a máquina de animações
## com AnimationLibrary compartilhada (walk, run, sprint, strafe sideways, looser e death falling),
## trata colisões imediatas, headshots, dano e suporte integral a Object Pooling.

# --- SINAIS ---
signal died(zombie: Zombie, points: int, was_headshot: bool)
signal damaged(current_hp: float, dmg: float, is_headshot: bool)

# --- TIPOS E VARIANTES ---
enum Variant { CLASSIC, NO_ARM }
enum Type { WALKER, RUNNER, FAST_RUNNER }
enum State { APPROACHING, STRAFING, LOOSER, DYING }

# --- PROPRIEDADES PRINCIPAIS ---
@export_group("Variante e Status")
@export var zombie_variant: Variant = Variant.CLASSIC
@export var zombie_type: Type = Type.WALKER
var type: Type:
	get: return zombie_type
	set(val): zombie_type = val

@export var health: float = 35.0
@export var max_health: float = 35.0
@export var speed: float = 4.2
@export var is_alive: bool = true
var is_dead: bool:
	get: return not is_alive or is_dying

@export var attack_damage: float = 22.0
@export var headshot_multiplier: float = 2.5
@export var score_points: int = 50
@export var is_pooled: bool = true ## Quando verdadeiro, não remove com queue_free(), permitindo reciclagem no pool

# --- TRAJETÓRIA FIXA, STALKER, BOTE SÚBITO (LUNGE) E RASTEJANTE (CRAWLER) ---
var fixed_lane_x: float = 0.0
var base_speed: float = 4.2
var is_stalker: bool = false
var stalker_lane_changed: bool = false
var stalker_target_x: float = 0.0
var is_crawler: bool = false
var can_lunge: bool = false
var has_lunged: bool = false
var is_lunging: bool = false
var lunge_target_x: float = 0.0
var is_sprinter: bool = false
var sprinter_eyes_mesh: MeshInstance3D = null
static var shared_sprinter_eye_mat: StandardMaterial3D = null

# --- CONFIGURAÇÃO VISUAL E MODELO 3D ---
@export_group("Modelo 3D e Animação")
@export var zombie_model_scene: PackedScene = null
@export var human_scale: Vector3 = Vector3(1.78, 1.78, 1.78)
@export var model_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0) ## Rotação Y=0 garante que o rosto e peito fiquem voltados para o jogador
@export var model_root: Node3D
@export var animation_player: AnimationPlayer
@export var body_collision: CollisionShape3D
@export var head_hitbox: Area3D
@export var head_collision: CollisionShape3D

# --- ESTADOS INTERNOS ---
var current_state: State = State.APPROACHING
var default_anim: String = "undead zombie walking"
var death_anim: String = "zombie falling"
var current_anim: String = ""
var road_speed: float = 10.5
var target_player: Node3D = null
var despawn_z: float = 18.0
var is_dying: bool = false
var is_looser: bool = false
var is_game_over: bool = false
var is_in_grapple: bool = false
var has_near_missed: bool = false

# --- ÁUDIO ESPACIAL 3D (AUDIOSTREAMPLAYER3D) ---
var audio_player_3d: AudioStreamPlayer3D = null
var growl_timer: float = 0.0

# Cena de efeito de sangue reutilizável
const BLOOD_IMPACT_SCENE: PackedScene = preload("res://scenes/BloodImpact.tscn")

# Caches estáticos de AnimationLibrary para alto desempenho (compartilhados entre instâncias sem reler GLBs)
static var _shared_classic_library: AnimationLibrary = null
static var _shared_no_arm_library: AnimationLibrary = null


func _ready() -> void:
	health = max_health
	is_alive = true
	is_dying = false
	is_looser = false
	has_near_missed = false
	
	# Garante que a base dos sapatos comece perfeitamente em Y = 0 (nível da pista)
	position.y = 0.0
	fixed_lane_x = position.x
	
	_configure_zombie_type_and_speed()
	_setup_collision_nodes()
	_setup_model_instance()
	_setup_animations()
	_setup_audio_nodes()
	
	if not target_player and is_inside_tree():
		target_player = get_tree().get_first_node_in_group("player") as Node3D


func _setup_audio_nodes() -> void:
	audio_player_3d = AudioManager.setup_zombie_audio(self)
	growl_timer = randf_range(0.6, 2.5)



## Define aleatoriamente o tipo de zumbi, velocidade e animação base conforme variante
func _configure_zombie_type_and_speed() -> void:
	if zombie_variant == Variant.NO_ARM:
		# Variante 2: Zombie No Arm (+20% mais rápido que zumbi comum: 4.5 * 1.2 = 5.4m/s a 6.0m/s)
		speed = 5.5
		default_anim = "zombie+no+arm++running+fast"
		death_anim = "zombie+no+arm+falling"
		max_health = 30.0
		health = max_health
		attack_damage = 25.0
		score_points = 65
	else:
		# Variante 1: Zombie Clássico (Walker, Runner, Fast Runner)
		var rand_val: int = randi() % 3
		zombie_type = rand_val as Type
		death_anim = "zombie falling"

		match zombie_type:
			Type.WALKER:
				speed = 2.5
				default_anim = "undead zombie walking"
			Type.RUNNER:
				speed = 4.5
				default_anim = "zombie running"
			Type.FAST_RUNNER:
				speed = 6.5
				default_anim = "zombie running fast"

	base_speed = speed


## Configura dinamicamente se o zumbi é um corredor rápido ou caminhante padrão (Dificuldade Dinâmica)
func set_as_fast_runner(fast: bool) -> void:
	if zombie_variant == Variant.NO_ARM:
		speed = 6.4 if fast else 4.8
		default_anim = "zombie+no+arm++running+fast"
	else:
		if fast:
			zombie_type = Type.FAST_RUNNER
			speed = randf_range(5.8, 7.2)
			default_anim = "zombie running fast"
		else:
			zombie_type = Type.WALKER
			speed = randf_range(2.8, 4.2)
			default_anim = "undead zombie walking"
	base_speed = speed
	if is_alive and not is_dying and not is_looser:
		_play_anim(default_anim, 0.2)


## Configura o zumbi como um Sprinter / Furioso de alta velocidade com olhos vermelhos
func set_as_sprinter(sprinter: bool = true) -> void:
	is_sprinter = sprinter
	set_as_fast_runner(sprinter)
	if sprinter:
		speed = randf_range(7.8, 9.4)
		base_speed = speed
		_setup_sprinter_eyes()
		if sprinter_eyes_mesh:
			sprinter_eyes_mesh.visible = true
	else:
		if sprinter_eyes_mesh:
			sprinter_eyes_mesh.visible = false


func _setup_sprinter_eyes() -> void:
	if not sprinter_eyes_mesh:
		sprinter_eyes_mesh = MeshInstance3D.new()
		sprinter_eyes_mesh.name = "SprinterEyes"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.24, 0.04, 0.06)
		if not shared_sprinter_eye_mat:
			shared_sprinter_eye_mat = StandardMaterial3D.new()
			shared_sprinter_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shared_sprinter_eye_mat.albedo_color = Color(1.0, 0.08, 0.08)
		sprinter_eyes_mesh.mesh = mesh
		sprinter_eyes_mesh.material_override = shared_sprinter_eye_mat
		sprinter_eyes_mesh.position = Vector3(0.0, 1.55, 0.28)
		add_child(sprinter_eyes_mesh)


## Configura colisores tridimensionais (Tronco e Headshot)
func _setup_collision_nodes() -> void:
	if not body_collision:
		body_collision = get_node_or_null("CollisionShape3D")
		if not body_collision:
			body_collision = CollisionShape3D.new()
			body_collision.name = "CollisionShape3D"
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.36
			capsule.height = 1.35
			body_collision.shape = capsule
			body_collision.position = Vector3(0.0, 0.72, 0.0)
			add_child(body_collision)

	if not head_hitbox:
		head_hitbox = get_node_or_null("HeadHitbox") as Area3D
		if not head_hitbox:
			head_hitbox = Area3D.new()
			head_hitbox.name = "HeadHitbox"
			head_hitbox.set_script(preload("res://scripts/HeadHitbox.gd"))
			add_child(head_hitbox)

	if not head_collision:
		head_collision = head_hitbox.get_node_or_null("HeadCol") as CollisionShape3D
		if not head_collision:
			head_collision = head_hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not head_collision:
			head_collision = CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.22
			head_collision.shape = sphere
			head_collision.position = Vector3(0.0, 1.58, -0.1)
			head_hitbox.add_child(head_collision)
		head_collision.name = "HeadCol"



## Instancia o modelo 3D articulado com calibração de rotação e pivô
func _setup_model_instance() -> void:
	if not model_root:
		model_root = get_node_or_null("ModelRoot")
		if not model_root:
			model_root = Node3D.new()
			model_root.name = "ModelRoot"
			add_child(model_root)

	model_root.scale = human_scale
	model_root.position = Vector3.ZERO
	model_root.rotation = Vector3.ZERO

	var model_instance: Node3D = model_root.get_node_or_null("UndeadZombieModel")
	if not model_instance and model_root.get_child_count() > 0:
		model_instance = model_root.get_child(0) as Node3D

	if not model_instance:
		if zombie_model_scene:
			model_instance = zombie_model_scene.instantiate()
		elif zombie_variant == Variant.NO_ARM:
			model_instance = preload("res://assets/Animation/Zombie no arm/zombie+no+arm++running+fast.glb").instantiate()
		else:
			model_instance = preload("res://assets/Animation/Zombies/undead zombie walking.glb").instantiate()

		model_instance.name = "UndeadZombieModel"
		model_root.add_child(model_instance)

	if model_instance:
		# Calibração: zumbi totalmente em pé e virado de frente para o jogador (Y=0)
		model_instance.rotation_degrees = model_rotation_degrees
		model_instance.position = Vector3.ZERO


## Obtém ou constrói a AnimationLibrary do Zumbi Clássico
static func _get_classic_anim_library() -> AnimationLibrary:
	if _shared_classic_library != null:
		return _shared_classic_library

	_shared_classic_library = AnimationLibrary.new()
	var anim_sources = {
		"undead zombie walking": "res://assets/Animation/Zombies/undead zombie walking.glb",
		"zombie running": "res://assets/Animation/Zombies/zombie running.glb",
		"zombie running fast": "res://assets/Animation/Zombies/zombie running fast.glb",
		"zombie walk sideways": "res://assets/Animation/Zombies/zombie walk sideways.glb",
		"zombi looser": "res://assets/Animation/Zombies/zombi looser.glb",
		"zombie falling": "res://assets/Animation/Zombies/zombie falling.glb"
	}

	for anim_name in anim_sources:
		var path: String = anim_sources[anim_name]
		if not ResourceLoader.exists(path):
			continue
		var sc = load(path)
		if not (sc is PackedScene):
			continue
		var temp_inst = sc.instantiate()
		var ap: AnimationPlayer = temp_inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			var orig_name = ap.get_animation_list()[0]
			var anim: Animation = ap.get_animation(orig_name).duplicate()

			if anim_name in ["undead zombie walking", "zombie running", "zombie running fast", "zombie walk sideways"]:
				anim.loop_mode = Animation.LOOP_LINEAR
			else:
				anim.loop_mode = Animation.LOOP_NONE

			# Converte animações contínuas em in-place (trava deslocamento X/Z do Hips)
			if anim_name != "zombie falling":
				for t in range(anim.get_track_count()):
					var track_path = str(anim.track_get_path(t))
					if "Hips" in track_path and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
						var first_val: Vector3 = anim.track_get_key_value(t, 0)
						for key_idx in range(anim.track_get_key_count(t)):
							var val: Vector3 = anim.track_get_key_value(t, key_idx)
							anim.track_set_key_value(t, key_idx, Vector3(first_val.x, val.y, first_val.z))

			_shared_classic_library.add_animation(anim_name, anim)
		temp_inst.free()

	return _shared_classic_library


## Obtém ou constrói a AnimationLibrary do Zombie No Arm
static func _get_no_arm_anim_library() -> AnimationLibrary:
	if _shared_no_arm_library != null:
		return _shared_no_arm_library

	_shared_no_arm_library = AnimationLibrary.new()
	var anim_sources = {
		"zombie+no+arm++running+fast": "res://assets/Animation/Zombie no arm/zombie+no+arm++running+fast.glb",
		"zombie+no+arm+falling": "res://assets/Animation/Zombie no arm/zombie+no+arm+falling.glb"
	}

	for anim_name in anim_sources:
		var path: String = anim_sources[anim_name]
		if not ResourceLoader.exists(path):
			continue
		var sc = load(path)
		if not (sc is PackedScene):
			continue
		var temp_inst = sc.instantiate()
		var ap: AnimationPlayer = temp_inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			var orig_name = ap.get_animation_list()[0]
			var anim: Animation = ap.get_animation(orig_name).duplicate()

			if anim_name == "zombie+no+arm++running+fast":
				anim.loop_mode = Animation.LOOP_LINEAR
				# Trava deslocamento X/Z do Hips para ser in-place
				for t in range(anim.get_track_count()):
					var track_path = str(anim.track_get_path(t))
					if "Hips" in track_path and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
						var first_val: Vector3 = anim.track_get_key_value(t, 0)
						for key_idx in range(anim.track_get_key_count(t)):
							var val: Vector3 = anim.track_get_key_value(t, key_idx)
							anim.track_set_key_value(t, key_idx, Vector3(first_val.x, val.y, first_val.z))
			else:
				anim.loop_mode = Animation.LOOP_NONE

			_shared_no_arm_library.add_animation(anim_name, anim)
		temp_inst.free()

	return _shared_no_arm_library


## Configura o AnimationPlayer com a AnimationLibrary correspondente à variante
func _setup_animations() -> void:
	if not animation_player and model_root:
		animation_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer

	if animation_player:
		var lib: AnimationLibrary = null
		if zombie_variant == Variant.NO_ARM:
			lib = _get_no_arm_anim_library()
		else:
			lib = _get_classic_anim_library()

		if animation_player.has_animation_library(""):
			animation_player.remove_animation_library("")
		animation_player.add_animation_library("", lib)

		_play_anim(default_anim, 0.0)


## Executa transição suave de animações
func _play_anim(anim_name: String, blend_time: float = 0.2) -> void:
	if current_anim == anim_name:
		return
	current_anim = anim_name
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name, blend_time)


# ==============================================================================
# FÍSICA E MÁQUINA DE ESTADOS
# ==============================================================================

func _physics_process(delta: float) -> void:
	# 0. Interrupção imediata de avanço no eixo Z quando o jogo acaba
	if is_game_over or GameManager.is_game_over or GameController.is_game_over:
		speed = 0.0
		road_speed = 0.0
		return

	# 1. Se em cutscene de agarrão, movimentação é travada e controlada pelo Player
	if is_in_grapple:
		speed = 0.0
		road_speed = 0.0
		return

	# 2. Se em queda de morte, permanece na pista no local onde tombou
	if is_dying:
		return

	# 3. Se em reação de frustração (looser), para o avanço frontal e permanece na pista
	if is_looser:
		return

	if not is_alive:
		return

	var player_z: float = 0.0
	var player_x: float = 0.0
	if target_player and is_instance_valid(target_player):
		player_z = target_player.global_position.z if target_player.is_inside_tree() else target_player.position.z
		player_x = target_player.global_position.x if target_player.is_inside_tree() else target_player.position.x

	var my_z: float = global_position.z if is_inside_tree() else position.z
	var my_x: float = global_position.x if is_inside_tree() else position.x

	# 4. Checagem de colisão frontal direta com o jogador -> Inicia Cutscene de Agarrão (exceto se o jogador estiver saltando sobre um Crawler!)
	if target_player and is_instance_valid(target_player) and not target_player.get("is_dead"):
		if not target_player.get("is_grappled") and not target_player.get("is_in_ambush"):
			var d_z: float = absf(my_z - player_z)
			var d_x: float = absf(my_x - player_x)
			var player_y: float = target_player.global_position.y if target_player.is_inside_tree() else target_player.position.y
			var jumped_over_crawler: bool = (is_crawler and player_y > 0.65)
			if d_z < 1.15 and d_x < 0.85 and not jumped_over_crawler:
				# Durante Adrenalina Máxima, o jogador atropela o zumbi com impacto cinético letal
				if target_player.get("is_adrenaline_rush"):
					take_damage(999.0, global_position + Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.2, -1.0), false, true)
					if target_player.has_method("add_camera_shake"):
						target_player.add_camera_shake(0.25)
					return
				if target_player.has_method("start_zombie_grapple"):
					target_player.start_zombie_grapple(self)
					return

	# 5. Se o jogador passou raspando pelo zumbi e o deixou para trás sem colisão direta
	if my_z > player_z + 1.2:
		_trigger_looser()
		return

	# 6. Movimento de perseguição frontal (+Z em rota de colisão direta com o jogador)
	var forward_step: float = speed * delta
	if is_inside_tree():
		global_position.z += forward_step
	else:
		position.z += forward_step

	var dist_to_player_z: float = absf(my_z - player_z)

	# 6.5. Mecânica de Bote Súbito (Lunge Attack): a 5m-11m de distância, zumbis agressivos dão um bote lateral tentando interceptar o jogador!
	if can_lunge and not has_lunged and not is_crawler and dist_to_player_z < 11.0 and dist_to_player_z > 4.5:
		var lateral_dist: float = absf(player_x - my_x)
		if lateral_dist > 0.6 and lateral_dist <= 3.0:
			has_lunged = true
			is_lunging = true
			var lunge_dir: float = signf(player_x - my_x)
			lunge_target_x = clampf(my_x + lunge_dir * 1.85, -6.5, 6.5)
			speed = base_speed * 1.35
			if audio_player_3d:
				AudioManager.play_zombie_swipe(audio_player_3d)
			if model_root:
				var ltw := create_tween()
				ltw.tween_property(model_root, "rotation:z", deg_to_rad(-14.0 * lunge_dir), 0.12)
				ltw.tween_property(model_root, "rotation:z", 0.0, 0.22)

	if is_lunging:
		my_x = move_toward(my_x, lunge_target_x, delta * 7.5)
		if is_inside_tree():
			global_position.x = my_x
		else:
			position.x = my_x
		if absf(my_x - lunge_target_x) < 0.05:
			fixed_lane_x = lunge_target_x
			is_lunging = false

	# 5. Trajetória reta dos zumbis e mecânica de Stalker (mudança única e antecipada a Z > 35m)
	elif is_stalker and not stalker_lane_changed:
		if dist_to_player_z > 35.0:
			current_state = State.STRAFING
			my_x = move_toward(my_x, stalker_target_x, delta * 2.2)
			if is_inside_tree():
				global_position.x = my_x
			else:
				position.x = my_x
			if zombie_variant == Variant.CLASSIC:
				_play_anim("zombie walk sideways", 0.22)
			if absf(my_x - stalker_target_x) < 0.05:
				fixed_lane_x = stalker_target_x
				stalker_lane_changed = true
				current_state = State.APPROACHING
				_play_anim(default_anim, 0.25)
		else:
			# Chegou a menos de 35m (ou < 20m) sem terminar a troca -> trava imediatamente na coordenada atual!
			fixed_lane_x = my_x
			stalker_lane_changed = true
			current_state = State.APPROACHING
			_play_anim(default_anim, 0.25)
	else:
		# Zumbi padrão (85% ou stalker estabilizado): TRAVA EIXO X RIGOROSAMENTE
		# Sem perseguição contínua/imã lateral, avanço 100% em linha reta
		if is_inside_tree():
			global_position.x = fixed_lane_x
		else:
			position.x = fixed_lane_x
		if current_state != State.APPROACHING:
			current_state = State.APPROACHING
			_play_anim(default_anim, 0.25)

	# 6. Despawn caso ultrapasse o limite de visualização e não esteja em pool gerenciado
	if not is_pooled and (global_position.z if is_inside_tree() else position.z) > despawn_z:
		queue_free()

	# 7. Rosnados e respiração agressiva 3D com variação de volume e atenuação a 35m
	if is_alive and not is_dying and not is_looser and not is_in_grapple:
		growl_timer -= delta
		if growl_timer <= 0.0:
			var dist_to_player: float = absf(my_z - player_z)
			if dist_to_player <= 35.0:
				var is_close: bool = (dist_to_player < 9.0)
				AudioManager.play_zombie_growl(audio_player_3d, is_close)
				growl_timer = randf_range(1.2, 2.2) if is_close else randf_range(2.6, 4.5)
			else:
				growl_timer = randf_range(1.5, 3.0)


## Executa o bote agressivo e unhada violenta no ar na direção em que o jogador raspou
func trigger_near_miss_swipe(is_player_on_right: bool) -> void:
	if has_near_missed or is_dying or not is_alive or is_in_grapple:
		return
	has_near_missed = true

	# Toca som visceral de unhada e rosnado rasgando o ar
	if audio_player_3d:
		AudioManager.play_zombie_swipe(audio_player_3d)
	else:
		AudioManager.play_zombie_swipe(null)

	# Bote corporal procedural com torção do tronco e projeção dos braços no ar
	if model_root and is_inside_tree():
		var swipe_rot_y: float = deg_to_rad(28.0 if is_player_on_right else -28.0)
		var swipe_lunge_x: float = 0.32 if is_player_on_right else -0.32

		var tw := create_tween()
		# Fase 1: Golpe rápido e agressivo tentando arranhar o jogador no ar (0.07s)
		tw.set_parallel(true)
		tw.tween_property(model_root, "position", Vector3(swipe_lunge_x, 0.05, 0.28), 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(model_root, "rotation:y", swipe_rot_y, 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		# Fase 2: Pausa dramática no ápice do corte no ar (0.04s)
		tw.chain().tween_interval(0.04)

		# Fase 3: Retorno suave à postura original (0.18s)
		tw.chain().set_parallel(true)
		tw.tween_property(model_root, "position", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(model_root, "rotation:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# Ao errar o golpe no vazio, o zumbi transiciona para a reação de frustração
		tw.chain().tween_callback(func():
			if is_alive and not is_dying:
				_trigger_looser()
		)
	else:
		_trigger_looser()


## Acionado quando o jogador desvia com sucesso e deixa o zumbi para trás
func _trigger_looser() -> void:
	if is_looser or is_dying:
		return
	is_looser = true
	current_state = State.LOOSER
	speed = 0.0 # Para o avanço frontal

	if audio_player_3d and audio_player_3d.playing:
		audio_player_3d.stop()


	if zombie_variant == Variant.CLASSIC and animation_player and animation_player.has_animation("zombi looser"):
		_play_anim("zombi looser", 0.2)

	if not is_pooled:
		if is_inside_tree():
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(self):
					queue_free()
			)


# ==============================================================================
# COMBATE E MORTE
# ==============================================================================

## Recebe dano com multiplicador crítico para Headshots e gera respingos de sangue no ponto de impacto
func take_damage(amount: float, hit_point: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO, is_headshot: bool = false, is_point_blank: bool = false) -> void:
	if not is_alive or is_dying:
		return

	# Instancia BloodImpact.tscn no ponto exato do impacto (cabeça ou peito), ampliado se for tiro à queima-roupa
	_spawn_blood_impact(hit_point, hit_normal, is_headshot, is_point_blank)

	health -= amount
	damaged.emit(health, amount, is_headshot)

	# Flinch e Knockback físico visceral ao receber impacto de projétil
	if health > 0.0 and amount < 35.0:
		if is_inside_tree():
			global_position.z -= 0.45
		if model_root:
			var ftw := create_tween()
			ftw.tween_property(model_root, "rotation_degrees:x", -16.0, 0.05)
			ftw.tween_property(model_root, "rotation_degrees:x", 0.0, 0.14)

	# Se for tiro crítico na cabeça à queima-roupa ou dano >= 35.0 ou vida zerada, morte instantânea
	if (is_headshot and is_point_blank) or health <= 0.0 or amount >= 35.0:
		if is_inside_tree():
			# Empurrão cinético na direção do tiro ao tombar morto
			var knockback_tw := create_tween()
			knockback_tw.tween_property(self, "global_position:z", global_position.z - (1.4 if is_headshot else 0.85), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		die(is_headshot)


func _spawn_blood_impact(hit_point: Vector3, hit_normal: Vector3, is_headshot: bool, is_amplified: bool = false) -> void:
	if not is_inside_tree():
		return

	var spawn_pos: Vector3 = hit_point
	if spawn_pos == Vector3.ZERO:
		if is_headshot and head_collision:
			spawn_pos = head_collision.global_position
		elif body_collision:
			spawn_pos = body_collision.global_position + Vector3(0.0, 0.35, 0.0)
		else:
			spawn_pos = global_position + Vector3(0.0, 1.25, 0.0)

	var blood: CPUParticles3D = BLOOD_IMPACT_SCENE.instantiate() as CPUParticles3D
	if not blood:
		return

	if is_amplified:
		# Efeito de sangue ampliado no ponto de impacto à queima-roupa
		blood.amount = 60
		blood.scale_amount_min = 1.6
		blood.scale_amount_max = 2.8
		blood.initial_velocity_min = 6.0
		blood.initial_velocity_max = 11.0
		blood.scale = Vector3.ONE * 1.5

	var parent_node: Node = get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene
	if not parent_node:
		parent_node = self

	parent_node.add_child(blood)
	blood.global_position = spawn_pos

	if hit_normal != Vector3.ZERO:
		blood.direction = hit_normal
	else:
		blood.direction = Vector3(0.0, 0.3, -1.0) # Espirra contra a trajetória do projétil



## Morte do zumbi: desativa colisores imediatamente, interrompe avanço e toca animação de queda
func die(is_headshot: bool = false) -> void:
	if is_dying:
		return
	is_dying = true
	is_alive = false
	current_state = State.DYING
	speed = 0.0

	if audio_player_3d and audio_player_3d.playing:
		audio_player_3d.stop()

	# 1. Desativa CollisionShape3Ds imediatamente para não travar a passagem do jogador
	if body_collision:
		body_collision.set_deferred("disabled", true)
		body_collision.disabled = true
	if head_collision:
		head_collision.set_deferred("disabled", true)
		head_collision.disabled = true
	if head_hitbox:
		head_hitbox.monitoring = false
		head_hitbox.monitorable = false

	collision_layer = 0
	collision_mask = 0

	var final_points: int = score_points * (2 if is_headshot else 1)
	died.emit(self, final_points, is_headshot)

	# 2. Executa animação de queda / morte correspondente sem loop
	_play_anim(death_anim, 0.12)

	# 3. Se não for gerenciado por pool, remove após o término
	if not is_pooled:
		if is_inside_tree():
			get_tree().create_timer(1.2).timeout.connect(func():
				if is_instance_valid(self):
					queue_free()
			)
		else:
			queue_free()


## Entra no estado de agarrão cinemático em 1ª pessoa:
## Posiciona 0.75m à frente da câmera no eixo -Z, com a cabeça na altura da linha de visão
## Rotação voltado 100% de frente para o jogador e animação de avanço rápido/ataque
func enter_grapple_cutscene(camera_3d: Camera3D) -> void:
	is_in_grapple = true
	speed = 0.0
	road_speed = 0.0
	current_state = State.APPROACHING

	if audio_player_3d and audio_player_3d.playing:
		audio_player_3d.stop()


	if camera_3d:
		var cam_pos: Vector3 = camera_3d.global_position
		var cam_fwd: Vector3 = -camera_3d.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		if cam_fwd.length_squared() < 0.01:
			cam_fwd = Vector3(0.0, 0.0, -1.0)

		# Posição: 0.75m à frente da câmera no eixo -Z, com a cabeça na altura da linha de visão
		var target_pos: Vector3 = cam_pos + cam_fwd * 0.75
		# A colisão da cabeça (head_collision) está a Y = 1.58m da base dos pés
		target_pos.y = maxf(0.0, cam_pos.y - 1.58)
		global_position = target_pos

		# Rotação: voltado 100% de frente para o jogador (Y=0 graus)
		global_rotation = Vector3.ZERO

	# Animação de avanço rápido / ataque frontal com os braços projetados
	if zombie_variant == Variant.NO_ARM:
		_play_anim("zombie+no+arm++running+fast", 0.1)
	else:
		_play_anim("zombie running fast", 0.1)


## Resolução do agarrão com faca: queda para trás imediata e empurrão físico
func resolve_grapple_death(push_distance: float = 2.2) -> void:
	is_in_grapple = false
	is_dying = true
	is_alive = false
	speed = 0.0
	road_speed = 0.0
	current_state = State.DYING

	if body_collision:
		body_collision.set_deferred("disabled", true)
		body_collision.disabled = true
	if head_collision:
		head_collision.set_deferred("disabled", true)
		head_collision.disabled = true
	if head_hitbox:
		head_hitbox.monitoring = false
		head_hitbox.monitorable = false

	collision_layer = 0
	collision_mask = 0

	# Dispara no zumbi a animação de queda para trás ("zombie falling.glb")
	_play_anim(death_anim, 0.1)

	# Empurra-o fisicamente para trás
	var push_tw := create_tween()
	push_tw.tween_property(self, "global_position:z", global_position.z + push_distance, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	died.emit(self, score_points, false)

	if not is_pooled:
		if is_inside_tree():
			get_tree().create_timer(1.8).timeout.connect(func():
				if is_instance_valid(self):
					queue_free()
			)
		else:
			queue_free()


## Recicla o zumbi para reaproveitamento em Object Pooling (sem instantiate nem queue_free)
func recycle(spawn_position: Vector3, new_road_speed: float) -> void:
	if is_inside_tree():
		global_position = spawn_position
	else:
		position = spawn_position

	fixed_lane_x = spawn_position.x
	speed = base_speed
	road_speed = new_road_speed
	health = max_health
	is_alive = true
	is_dying = false
	is_looser = false
	is_in_grapple = false
	has_near_missed = false
	is_sprinter = false
	if sprinter_eyes_mesh:
		sprinter_eyes_mesh.visible = false
	current_state = State.APPROACHING

	if model_root:
		model_root.position = Vector3.ZERO
		model_root.rotation = Vector3.ZERO

	growl_timer = randf_range(0.6, 2.5)
	if audio_player_3d and audio_player_3d.playing:
		audio_player_3d.stop()

	# 15% dos zumbis clássicos são "stalkers", 14% são "crawlers" (rastejantes no asfalto) e 25% têm bote (lunge)
	is_stalker = (zombie_variant == Variant.CLASSIC and randf() < 0.22)
	stalker_lane_changed = false
	if is_stalker:
		var shift: float = 2.2 if randf() < 0.5 else -2.2
		stalker_target_x = clampf(fixed_lane_x + shift, -6.5, 6.5)

	is_crawler = (not is_stalker and randf() < 0.14)
	can_lunge = (not is_crawler and randf() < 0.30)
	has_lunged = false
	is_lunging = false

	if model_root:
		if is_crawler:
			# Postura rastejante rente ao asfalto (exige PULO [Espaço] ou tiro baixo!)
			model_root.rotation_degrees = Vector3(72.0, 0.0, 0.0)
			model_root.position = Vector3(0.0, 0.22, 0.0)
			speed = base_speed * 0.75
		else:
			model_root.rotation_degrees = Vector3.ZERO
			model_root.position = Vector3.ZERO

	if body_collision:
		body_collision.disabled = false
	if head_collision:
		head_collision.disabled = false
	if head_hitbox:
		head_hitbox.monitoring = true
		head_hitbox.monitorable = true

	collision_layer = 4
	collision_mask = 3

	visible = true
	_play_anim(default_anim, 0.0)
