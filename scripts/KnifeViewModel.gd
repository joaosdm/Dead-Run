class_name KnifeViewModel
extends Node3D

## Dead Run - Tactical Knife Viewmodel & Procedural Melee System (Godot 4.3)
## Gerencia o modelo da faca tática ("assets/3D/tactical knife 3d model.glb"),
## materiais consistentes com as luvas da Glock, animação procedural de estocada (Tween),
## sensor MeleeRay (RayCast3D) e impacto com dano fatal e sangue.

signal attack_started
signal attack_hit(target: Object, hit_point: Vector3)
signal attack_completed

@export_group("Modelo da Faca")
@export_file("*.glb", "*.gltf", "*.tscn") var knife_model_path: String = "res://assets/3D/tactical knife 3d model.glb"
@export var model_holder: Node3D
@export var melee_ray: RayCast3D
@export var model_scale: Vector3 = Vector3(0.55, 0.55, 0.55)
@export var default_pos: Vector3 = Vector3(0.22, -0.42, -0.45)
@export var default_rot: Vector3 = Vector3(deg_to_rad(2.0), deg_to_rad(-6.0), deg_to_rad(-4.0))
@export var hidden_pos: Vector3 = Vector3(0.22, -0.80, -0.30)
@export var start_visible: bool = false

@export_group("Combate Corpo a Corpo")
@export var melee_damage: float = 100.0
@export var melee_range: float = 1.8

const BLOOD_IMPACT_SCENE: PackedScene = preload("res://scenes/BloodImpact.tscn")

var is_attacking: bool = false
var attack_tween: Tween = null
var active_model_instance: Node3D = null
var camera_ref: Camera3D = null


func _ready() -> void:
	_setup_hierarchy()
	if model_holder and model_holder.get_child_count() > 0:
		active_model_instance = model_holder.get_child(0) as Node3D
		if active_model_instance:
			active_model_instance.scale = model_scale
	elif knife_model_path != "":
		load_knife_model(knife_model_path)
		
	if start_visible:
		visible = true
		position = default_pos
		rotation = default_rot
	else:
		visible = false
		position = hidden_pos
		rotation = default_rot
	
	# Localiza a Camera3D pai se estiver na árvore
	if not camera_ref and is_inside_tree():
		if get_parent() is Camera3D:
			camera_ref = get_parent() as Camera3D
		else:
			camera_ref = get_viewport().get_camera_3d()


## Mostra a faca imediatamente ou com tween
func show_knife(instant: bool = false) -> void:
	visible = true
	if instant:
		position = default_pos
		rotation = default_rot
	else:
		raise_knife(0.12)


## Oculta a faca imediatamente ou com tween
func hide_knife(instant: bool = false) -> void:
	if instant:
		visible = false
		position = hidden_pos
	else:
		lower_knife(0.10)


## Eleva a faca para a posição de empunhadura
func raise_knife(duration: float = 0.12) -> Tween:
	visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", default_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", default_rot, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


## Abaixa a faca para fora da visão
func lower_knife(duration: float = 0.10) -> Tween:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", hidden_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		visible = false
	)
	return tw


func _setup_hierarchy() -> void:
	if not model_holder:
		model_holder = get_node_or_null("ModelHolder") as Node3D
		if not model_holder:
			model_holder = Node3D.new()
			model_holder.name = "ModelHolder"
			add_child(model_holder)

	if not melee_ray:
		melee_ray = get_node_or_null("MeleeRay") as RayCast3D
		if not melee_ray:
			melee_ray = RayCast3D.new()
			melee_ray.name = "MeleeRay"
			# Alcance estritamente corpo a corpo de 1.8 metros apontado para frente (-Z)
			melee_ray.target_position = Vector3(0, 0, -melee_range)
			# Camada 4 = Zumbis / Inimigos
			melee_ray.collision_mask = 4
			melee_ray.collide_with_areas = true
			melee_ray.collide_with_bodies = true
			melee_ray.enabled = true
			add_child(melee_ray)


## Instancia o modelo 3D da faca tática preservando suas texturas e materiais originais de exportação
func load_knife_model(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("KnifeViewModel: Modelo não encontrado em '%s'" % path)
		return

	if active_model_instance and is_instance_valid(active_model_instance):
		active_model_instance.queue_free()
		active_model_instance = null

	var scene_res = load(path) as PackedScene
	if not scene_res:
		return

	active_model_instance = scene_res.instantiate() as Node3D
	if active_model_instance:
		model_holder.add_child(active_model_instance)
		active_model_instance.scale = model_scale
		active_model_instance.position = Vector3.ZERO
		active_model_instance.rotation = Vector3.ZERO



## Executa a animação procedural de estocada violenta frontal com detecção física de impacto
func stab_attack(on_completed: Callable = Callable()) -> void:
	if is_attacking:
		return
	is_attacking = true
	visible = true
	position = default_pos
	rotation = default_rot
	attack_started.emit()

	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	attack_tween = create_tween()

	# 1. Puxada para trás rápida (preparação): recua 0.15m (+Z) e inclina em 0.08 segundos
	var prep_pos := default_pos + Vector3(0.04, 0.02, 0.15)
	var prep_rot := default_rot + Vector3(deg_to_rad(-14.0), deg_to_rad(12.0), deg_to_rad(-8.0))

	# 2. Estocada violenta frontal: avança 0.45m (-Z) em direção ao centro da tela com rotação cortante rápida em 0.10s
	var stab_pos := default_pos + Vector3(-0.22, 0.06, -0.45)
	var stab_rot := default_rot + Vector3(deg_to_rad(16.0), deg_to_rad(-18.0), deg_to_rad(14.0))

	# FASE 1: Preparação rápida (0.08s)
	attack_tween.set_parallel(true)
	attack_tween.tween_property(self, "position", prep_pos, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(self, "rotation", prep_rot, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# FASE 2: Estocada violenta frontal (0.10s)
	attack_tween.chain().set_parallel(true)
	attack_tween.tween_property(self, "position", stab_pos, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	attack_tween.tween_property(self, "rotation", stab_rot, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# FASE 3: Ápice da estocada (após 0.10s) - Detecção de impacto e sangue
	attack_tween.chain().tween_callback(_check_melee_impact)

	# FASE 4: Retorno suave à posição de repouso (0.22s)
	attack_tween.chain().set_parallel(true)
	attack_tween.tween_property(self, "position", default_pos, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(self, "rotation", default_rot, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Finalização
	attack_tween.chain().tween_callback(func():
		is_attacking = false
		attack_completed.emit()
		if on_completed.is_valid():
			on_completed.call()
	)


## Checagem curta no momento ápice da estocada
func _check_melee_impact() -> void:
	if not melee_ray:
		return

	# Garante que o MeleeRay aponte estritamente para a frente (-Z) da visão/mira do jogador
	if not camera_ref and is_inside_tree():
		if get_parent() is Camera3D:
			camera_ref = get_parent() as Camera3D
		else:
			camera_ref = get_viewport().get_camera_3d()

	if camera_ref:
		melee_ray.global_transform.basis = camera_ref.global_transform.basis
		melee_ray.global_position = camera_ref.global_position + camera_ref.global_basis * Vector3(0.0, -0.2, -0.1)
		melee_ray.target_position = Vector3(0.0, 0.0, -melee_range)

	# Força a atualização do RayCast
	melee_ray.force_raycast_update()

	# Caso o raio NÃO colida (estocada no ar vazio): nenhum efeito de sangue ou dano é disparado
	if not melee_ray.is_colliding():
		return

	var collider = melee_ray.get_collider()
	if not collider:
		return

	var hit_pos: Vector3 = melee_ray.get_collision_point()
	var hit_norm: Vector3 = melee_ray.get_collision_normal()

	# Leve Tremor de Câmera (Impact Shake)
	if camera_ref:
		camera_ref.rotation_degrees.x -= 0.6
		camera_ref.rotation_degrees.y += randf_range(-0.3, 0.3)

	# Localiza o nó do zumbi
	var zombie: Zombie = null
	if collider is Zombie:
		zombie = collider
	elif collider is Node and "zombie" in collider and collider.zombie is Zombie:
		zombie = collider.zombie
	elif collider is Node and collider.get_parent() is Zombie:
		zombie = collider.get_parent() as Zombie
	elif collider.is_in_group("enemies") and collider is CharacterBody3D:
		zombie = collider as Zombie

	if zombie and (zombie.is_alive and not zombie.is_dying):
		# Aplica dano fatal direto (100.0) - Zombie.take_damage já instancia BloodImpact e aciona animação de queda
		zombie.take_damage(melee_damage, hit_pos, hit_norm, true)
		attack_hit.emit(zombie, hit_pos)
	elif collider.has_method("take_damage"):
		collider.take_damage(melee_damage, hit_pos, hit_norm)
		_spawn_blood_splatter(hit_pos, hit_norm)
		attack_hit.emit(collider, hit_pos)


func _spawn_blood_splatter(pos: Vector3, norm: Vector3) -> void:
	if not is_inside_tree():
		return
	var blood: CPUParticles3D = BLOOD_IMPACT_SCENE.instantiate() as CPUParticles3D
	if not blood:
		return
	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		scene_root = get_parent()
	scene_root.add_child(blood)
	blood.global_position = pos
	if norm != Vector3.ZERO:
		blood.direction = norm
	else:
		blood.direction = Vector3(0.0, 0.4, 1.0)


## Executa a estocada cinematográfica de combate corporal (Grapple Cutscene):
## 1. Torne visível o modelo da faca subindo rapidamente pelo canto inferior direito da tela.
## 2. Execute a estocada procedural frontal com o Tween cravando a lâmina no peito/queixo do zumbi.
## 3. Dispara o callback de impacto (sangue, animação de queda e empurrão).
## 4. Recolhe a faca para fora da visão e chama on_completed.
func execute_grapple_stab(on_blade_hit: Callable = Callable(), on_completed: Callable = Callable()) -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	is_attacking = true
	visible = true

	# Posição inicial no canto inferior direito da tela
	var corner_pos := Vector3(0.38, -0.65, -0.28)
	var corner_rot := Vector3(deg_to_rad(-24.0), deg_to_rad(-16.0), deg_to_rad(18.0))
	position = corner_pos
	rotation = corner_rot

	# Posição de elevação rápida (pronto para o golpe)
	var ready_pos := Vector3(0.20, -0.24, -0.38)
	var ready_rot := Vector3(deg_to_rad(-8.0), deg_to_rad(-8.0), deg_to_rad(6.0))

	# Posição cravando a lâmina frontalmente no peito/queixo do zumbi (centro da tela e profundo em -Z)
	var stab_impact_pos := Vector3(-0.04, -0.08, -0.64)
	var stab_impact_rot := Vector3(deg_to_rad(24.0), deg_to_rad(-18.0), deg_to_rad(15.0))

	attack_tween = create_tween()

	# FASE 1: Sobe rapidamente pelo canto inferior direito da tela (0.07s)
	attack_tween.set_parallel(true)
	attack_tween.tween_property(self, "position", ready_pos, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(self, "rotation", ready_rot, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# FASE 2: Estocada frontal cravando no peito/queixo (0.09s)
	attack_tween.chain().set_parallel(true)
	attack_tween.tween_property(self, "position", stab_impact_pos, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	attack_tween.tween_property(self, "rotation", stab_impact_rot, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# FASE 3: Ápice da cravada - Sangue, queda e empurrão
	attack_tween.chain().tween_callback(func():
		attack_hit.emit(null, global_position)
		if on_blade_hit.is_valid():
			on_blade_hit.call()
	)

	# FASE 4: Pausa dramática da lâmina cravada na carne (0.08s)
	attack_tween.chain().tween_interval(0.08)

	# FASE 5: Recolhimento rápido para fora da visão (0.10s)
	attack_tween.chain().set_parallel(true)
	attack_tween.tween_property(self, "position", hidden_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	attack_tween.tween_property(self, "rotation", default_rot, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# FASE 6: Finalização
	attack_tween.chain().tween_callback(func():
		visible = false
		is_attacking = false
		attack_completed.emit()
		if on_completed.is_valid():
			on_completed.call()
	)

