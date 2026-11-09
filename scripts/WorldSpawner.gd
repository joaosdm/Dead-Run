class_name WorldSpawner
extends Node3D

## Dead Run - World Spawner (Godot 4.3 - Web / Playgama High Performance Pooling)
## Gerencia esteira infinita de rodovia, pool fixo de 10 Zumbis (5 Clássicos e 5 No-Arm),
## pool fixo de 6 Carros Destruídos ("wrecked car 3d model.glb"), caixas de munição táticas a cada 200m
## e mecânica de raspão (Adrenaline Rush) com 0 alocações/GC durante o jogo.

# --- SINAIS ---
signal distance_updated(distance_meters: float)
signal speed_changed(current_speed: float)
signal zombie_killed_event(points: int, was_headshot: bool)
signal adrenaline_rush_triggered(duration: float)
signal ammo_collected(amount: int)
signal rescue_reached

# --- CONFIGURAÇÃO DA RODOVIA E POOLING ---
@export_group("Esteira Infinita da Rodovia")
@export var highway_scene: PackedScene
@export var total_modules: int = 5
@export var module_length: float = 50.0
@export var despawn_z: float = 25.0
@export var base_speed: float = 11.8 ## Velocidade inicial mais ágil e dinâmica (m/s)
@export var max_speed: float = 19.5
@export var speed_acceleration: float = 0.035
var current_speed: float = 11.8
var distance_traveled: float = 0.0
var highway_modules: Array[Node3D] = []
var shared_asphalt_material: ShaderMaterial = null
var shared_verge_mat: StandardMaterial3D = null
var shared_barrier_mat: StandardMaterial3D = null
var shared_stripe_warn_mat: StandardMaterial3D = null
var shared_pole_mat: StandardMaterial3D = null
var shared_bulb_mat: StandardMaterial3D = null
var shared_tree_mat: StandardMaterial3D = null
var shared_sign_green_mat: StandardMaterial3D = null
var extraction_beacon_node: Node3D = null
var extraction_spot: SpotLight3D = null
var extraction_rotor_phase: float = 0.0

# --- PISTAS (LANES E ACOSTAMENTOS ENTRE -6.5m E +6.5m) ---
@export_group("Pistas (Lanes)")
@export var lanes: Array[float] = [-6.5, -4.5, -2.2, 0.0, 2.2, 4.5, 6.5]
var side_lanes: Array[float] = [-6.5, -4.5, 4.5, 6.5]

# --- POOL FIXO DE ZUMBIS (EXATAMENTE 10 INSTÂNCIAS ALTERNADAS) ---
@export_group("Pool de Zumbis (10 Instâncias)")
@export var zombie_classic_scene: PackedScene = preload("res://scenes/Zombie.tscn")
@export var zombie_no_arm_scene: PackedScene = preload("res://scenes/ZombieNoArm.tscn")
const ZOMBIE_POOL_SIZE: int = 10
var zombie_pool: Array[Zombie] = []

# --- POOL FIXO DE CARROS DESTRUÍDOS (EXATAMENTE 6 INSTÂNCIAS) ---
@export_group("Pool de Carros Destruídos (6 Instâncias)")
@export var wrecked_car_scene: PackedScene = preload("res://scenes/WreckedCar.tscn")
const CAR_POOL_SIZE: int = 6
var car_pool: Array[WreckedCar] = []

# --- CAIXA DE MUNIÇÃO TÁTICA (A CADA 150m A 200m) ---
@export_group("Caixas de Munição Táticas")
@export var ammo_pickup_scene: PackedScene = preload("res://scenes/AmmoPickup.tscn")
@export var ammo_box_scene: PackedScene = preload("res://scenes/AmmoPickup.tscn")
var ammo_box_pool: Array[Node3D] = []
var next_ammo_checkpoint: float = 175.0

# --- POOL FIXO DE BARRIS DE COMBUSTÍVEL EXPLOSIVO ---
@export_group("Pool de Barris Explosivos")
@export var explosive_barrel_scene: PackedScene = preload("res://scenes/ExplosiveBarrel.tscn")
const BARREL_POOL_SIZE: int = 4
var barrel_pool: Array[Node3D] = []

# --- POOL FIXO DE BARRICADAS MILITARES ---
@export_group("Pool de Barricadas Militares")
@export var military_barricade_scene: PackedScene = preload("res://scenes/MilitaryBarricade.tscn")
const BARRICADE_POOL_SIZE: int = 2
var barricade_pool: Array[Node3D] = []

# --- POOL FIXO DE MANCHAS DE ÓLEO DIESEL (4 INSTÂNCIAS) ---
@export_group("Pool de Manchas de Óleo")
const OilSlickScript = preload("res://scripts/OilSlick.gd")
const OIL_POOL_SIZE: int = 4
var oil_slick_pool: Array[Node3D] = []
var oil_container: Node3D = null
var next_oil_checkpoint: float = 65.0

# Presets de Perigo Estruturados (Emboscada em Funil e Barricada Militar)
var next_hazard_preset_checkpoint: float = 65.0

# --- MECÂNICA DE RASPÃO (ADRENALINE RUSH) ---
var adrenaline_timer: float = 0.0
var grazed_zombies: Dictionary = {} # Instância ID -> bool para evitar múltiplos raspões no mesmo zumbi

# --- OBJETIVO DE RESGATE E FIM DE JOGO ---
@export var target_distance: float = 800.0
var rescue_triggered: bool = false
var is_game_over: bool = false

# --- REFERÊNCIA DO JOGADOR ---
@export_group("Jogador")
@export var player_node: Player = null

# Containers para organização visual
var modules_container: Node3D = null
var zombies_container: Node3D = null
var obstacles_container: Node3D = null
var pickups_container: Node3D = null
var barrels_container: Node3D = null
var barricades_container: Node3D = null
var flickering_street_lights: Array[SpotLight3D] = []


func _ready() -> void:
	current_speed = base_speed
	_setup_containers()
	_init_highway_modules()
	_init_fixed_zombie_pool()
	_init_fixed_car_pool()
	_init_ammo_box_pool()
	_init_fixed_barrel_pool()
	_init_fixed_barricade_pool()
	_init_fixed_oil_pool()

	if not player_node and is_inside_tree():
		player_node = get_tree().get_first_node_in_group("player") as Player
		if not player_node and get_parent() is Player:
			player_node = get_parent() as Player


func _setup_containers() -> void:
	modules_container = Node3D.new()
	modules_container.name = "HighwayModules"
	add_child(modules_container)

	zombies_container = Node3D.new()
	zombies_container.name = "ZombiesPool"
	add_child(zombies_container)

	obstacles_container = Node3D.new()
	obstacles_container.name = "CarsPool"
	add_child(obstacles_container)

	pickups_container = Node3D.new()
	pickups_container.name = "PickupsPool"
	add_child(pickups_container)

	barrels_container = Node3D.new()
	barrels_container.name = "BarrelsPool"
	add_child(barrels_container)

	barricades_container = Node3D.new()
	barricades_container.name = "BarricadesPool"
	add_child(barricades_container)

	oil_container = Node3D.new()
	oil_container.name = "OilSlicksPool"
	add_child(oil_container)


# ==============================================================================
# 1. POOLING E RECICLAGEM DOS MÓDULOS DE RODOVIA
# ==============================================================================

func _init_highway_modules() -> void:
	for i in range(total_modules):
		var module: Node3D = null
		if highway_scene:
			module = highway_scene.instantiate() as Node3D
		else:
			module = _create_procedural_highway_module(module_length)

		module.name = "HighwayModule_%d" % i
		# Começa com 1 módulo em +50 cobrindo a retaguarda inicial e os demais à frente (0, -50, -100...)
		module.position.z = (1 - i) * module_length
		modules_container.add_child(module)
		highway_modules.append(module)


func _update_highway_modules(_delta: float, _run_speed: float = -1.0) -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	for module in highway_modules:
		# A reciclagem de blocos em Z depende estritamente da distância relativa entre o nó da pista e a global_position.z do Player:
		# Um bloco de estrada só é movido para frente quando estiver a mais de 15 metros ATRÁS da posição Z atual da câmera/jogador.
		# A borda frontal do módulo em direção ao avanço (-Z) é: position.z - (module_length * 0.5)
		if (module.position.z - (module_length * 0.5)) > player_z + 15.0:
			var furthest_z: float = player_z
			for other in highway_modules:
				if other.position.z < furthest_z:
					furthest_z = other.position.z
			module.position.z = furthest_z - module_length


func _init_shared_road_materials() -> void:
	if not shared_asphalt_material:
		shared_asphalt_material = ShaderMaterial.new()
		shared_asphalt_material.shader = preload("res://shaders/wet_asphalt.gdshader")
	if not shared_verge_mat:
		shared_verge_mat = StandardMaterial3D.new()
		shared_verge_mat.albedo_color = Color(0.04, 0.045, 0.05)
		shared_verge_mat.roughness = 0.95
	if not shared_barrier_mat:
		shared_barrier_mat = StandardMaterial3D.new()
		shared_barrier_mat.albedo_color = Color(0.28, 0.29, 0.31)
		shared_barrier_mat.roughness = 0.88
	if not shared_stripe_warn_mat:
		shared_stripe_warn_mat = StandardMaterial3D.new()
		shared_stripe_warn_mat.albedo_color = Color(0.95, 0.62, 0.08)
		shared_stripe_warn_mat.emission_enabled = true
		shared_stripe_warn_mat.emission = Color(0.95, 0.55, 0.05)
		shared_stripe_warn_mat.emission_energy_multiplier = 0.8
	if not shared_pole_mat:
		shared_pole_mat = StandardMaterial3D.new()
		shared_pole_mat.albedo_color = Color(0.2, 0.22, 0.25)
		shared_pole_mat.metallic = 0.75
		shared_pole_mat.roughness = 0.55
	if not shared_bulb_mat:
		shared_bulb_mat = StandardMaterial3D.new()
		shared_bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shared_bulb_mat.albedo_color = Color(1.0, 0.9, 0.65)
	if not shared_tree_mat:
		shared_tree_mat = StandardMaterial3D.new()
		shared_tree_mat.albedo_color = Color(0.08, 0.07, 0.06)
		shared_tree_mat.roughness = 0.95
	if not shared_sign_green_mat:
		shared_sign_green_mat = StandardMaterial3D.new()
		shared_sign_green_mat.albedo_color = Color(0.10, 0.34, 0.18)
		shared_sign_green_mat.roughness = 0.5


func _create_procedural_highway_module(length: float) -> Node3D:
	_init_shared_road_materials()
	var module := Node3D.new()

	# 1. Asfalto Molhado + Faixas Amarelas/Brancas + Olhos de Gato em 1 ÚNICO MeshInstance3D (1 Draw Call!)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadBody"
	var road_col := CollisionShape3D.new()
	var road_box := BoxShape3D.new()
	road_box.size = Vector3(20.0, 0.4, length)
	road_col.shape = road_box
	road_col.position = Vector3(0.0, -0.2, 0.0)
	road_body.add_child(road_col)

	var road_mesh := MeshInstance3D.new()
	var road_mesh_box := BoxMesh.new()
	road_mesh_box.size = Vector3(20.0, 0.4, length)
	road_mesh_box.material = shared_asphalt_material
	road_mesh.mesh = road_mesh_box
	road_mesh.position = Vector3(0.0, -0.2, 0.0)
	road_body.add_child(road_mesh)

	# Terreno único largo embaixo da pista cobrindo as duas margens (1 Draw Call em vez de 2)
	var verge := MeshInstance3D.new()
	var v_box := BoxMesh.new()
	v_box.size = Vector3(54.0, 0.35, length)
	v_box.material = shared_verge_mat
	verge.mesh = v_box
	verge.position = Vector3(0.0, -0.26, 0.0)
	module.add_child(verge)
	module.add_child(road_body)

	# 2. Muretas Jersey nas Laterais + Balizador Emissivo de Velocidade (Apenas 4 nós leves)
	for bx in [-8.8, 8.8]:
		var barrier_body := StaticBody3D.new()
		var barrier_col := CollisionShape3D.new()
		var b_box := BoxShape3D.new()
		b_box.size = Vector3(0.6, 1.2, length)
		barrier_col.shape = b_box
		barrier_col.position = Vector3(bx, 0.6, 0.0)
		barrier_body.add_child(barrier_col)

		var barrier_mesh := MeshInstance3D.new()
		var b_mesh_box := BoxMesh.new()
		b_mesh_box.size = Vector3(0.6, 1.2, length)
		b_mesh_box.material = shared_barrier_mat
		barrier_mesh.mesh = b_mesh_box
		barrier_mesh.position = Vector3(bx, 0.6, 0.0)
		barrier_body.add_child(barrier_mesh)
		module.add_child(barrier_body)

		for p_i in range(2):
			var post_marker := MeshInstance3D.new()
			var pm_box := BoxMesh.new()
			pm_box.size = Vector3(0.18, 0.55, 0.25)
			pm_box.material = shared_stripe_warn_mat
			post_marker.mesh = pm_box
			post_marker.position = Vector3(bx, 1.4, -12.5 + float(p_i) * 25.0)
			module.add_child(post_marker)

	# 3. Cenário Periférico Otimizado (Low-Draw-Call: apenas 3 silhuetas por módulo)
	_populate_roadside_scenery(module, length)

	# 4. Poste de Luz Caído (Sem SpotLight3D pesado — usa malha emissiva brilhante com Glow!)
	var pole_root := Node3D.new()
	var pole_side: float = -9.3 if randf() < 0.5 else 9.3
	pole_root.position = Vector3(pole_side, 0.0, randf_range(-length * 0.3, length * 0.3))
	pole_root.rotation_degrees = Vector3(0.0, 0.0, -22.0 if pole_side > 0 else 22.0)

	var pole_mesh := MeshInstance3D.new()
	var pole_cyl := CylinderMesh.new()
	pole_cyl.top_radius = 0.08
	pole_cyl.bottom_radius = 0.13
	pole_cyl.height = 6.4
	pole_cyl.radial_segments = 6 # Low-poly cilindro (6 lados apenas!)
	pole_cyl.rings = 1
	pole_cyl.material = shared_pole_mat
	pole_mesh.mesh = pole_cyl
	pole_mesh.position = Vector3(0.0, 3.0, 0.0)
	pole_root.add_child(pole_mesh)

	var bulb_mesh := MeshInstance3D.new()
	var bulb_box := BoxMesh.new()
	bulb_box.size = Vector3(0.55, 0.18, 0.30)
	bulb_box.material = shared_bulb_mat
	bulb_mesh.mesh = bulb_box
	bulb_mesh.position = Vector3(0.0, 6.1, 0.0)
	pole_root.add_child(bulb_mesh)
	module.add_child(pole_root)

	return module


## Cenário periférico ultra-leve (apenas 2 árvores low-poly de 6 lados e 1 placa/pórtico alternado por módulo)
func _populate_roadside_scenery(module: Node3D, length: float) -> void:
	for i in range(2):
		var side_sign: float = -1.0 if (i == 0) else 1.0
		var tx: float = side_sign * randf_range(10.8, 14.5)
		var tz: float = -12.0 + float(i) * 24.0

		var trunk := MeshInstance3D.new()
		var trunk_cyl := CylinderMesh.new()
		var h: float = randf_range(5.5, 7.5)
		trunk_cyl.top_radius = 0.10
		trunk_cyl.bottom_radius = 0.28
		trunk_cyl.height = h
		trunk_cyl.radial_segments = 5 # Apenas 5 lados!
		trunk_cyl.rings = 1
		trunk_cyl.material = shared_tree_mat
		trunk.mesh = trunk_cyl
		trunk.position = Vector3(tx, h * 0.5, tz)
		trunk.rotation_degrees = Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-8.0, 8.0))
		module.add_child(trunk)

	# Placa rodoviária simples (1 único MeshInstance3D)
	var board := MeshInstance3D.new()
	var b_box := BoxMesh.new()
	b_box.size = Vector3(2.2, 1.4, 0.1)
	b_box.material = shared_sign_green_mat
	board.mesh = b_box
	var sign_side: float = -9.8 if randf() < 0.5 else 9.8
	board.position = Vector3(sign_side, 2.2, randf_range(-10.0, 10.0))
	board.rotation_degrees.z = randf_range(-10.0, 10.0)
	module.add_child(board)


# ==============================================================================
# LEITURA DA PISTA E BRECHAS GARANTIDAS (3 SETORES DE CORREDORES)
# ==============================================================================

## Retorna o setor do corredor (0 = Esquerda, 1 = Centro, 2 = Direita) correspondente a uma coordenada X
func _get_corridor_sector(x: float) -> int:
	if x < -3.3:
		return 0 # Setor Esquerdo [-6.5, -4.5]
	elif x > 3.3:
		return 2 # Setor Direito [4.5, 6.5]
	else:
		return 1 # Setor Centro [-2.2, 2.2]


## Identifica quais setores de corredor estão ocupados por carros ativos ou zumbis vivos na fatia [target_z - 8.0, target_z + 8.0]
func _get_occupied_sectors_in_slice(target_z: float, exclude_node: Node = null) -> Array[int]:
	var occupied: Array[int] = []
	var z_window: float = 8.0

	# 1. Carros ativos
	for car in car_pool:
		if car == exclude_node or not is_instance_valid(car) or not car.is_active:
			continue
		var car_z: float = car.global_position.z if car.is_inside_tree() else car.position.z
		if absf(car_z - target_z) <= z_window:
			var sec: int = _get_corridor_sector(car.global_position.x if car.is_inside_tree() else car.position.x)
			if sec not in occupied:
				occupied.append(sec)

	# 2. Zumbis vivos
	for z in zombie_pool:
		if z == exclude_node or not is_instance_valid(z) or not z.is_alive or z.is_dying:
			continue
		var z_z: float = z.global_position.z if z.is_inside_tree() else z.position.z
		if absf(z_z - target_z) <= z_window:
			var sec: int = _get_corridor_sector(z.global_position.x if z.is_inside_tree() else z.position.x)
			if sec not in occupied:
				occupied.append(sec)

	return occupied


## Sorteia uma coordenada X garantindo que pelo menos um dos 3 setores de corredor permaneça 100% livre
func _get_valid_lane_with_breach(target_z: float, candidate_lanes: Array[float], exclude_node: Node = null) -> float:
	var occupied: Array[int] = _get_occupied_sectors_in_slice(target_z, exclude_node)

	# Se já há 2 ou mais setores ocupados na janela de +/- 8m, só podemos colocar o novo obstáculo
	# em um setor JÁ ocupado, garantindo que o setor restante permaneça 100% aberto como rota de fuga!
	if occupied.size() >= 2:
		var safe_candidates: Array[float] = []
		for lx in candidate_lanes:
			var sec: int = _get_corridor_sector(lx)
			if sec in occupied:
				safe_candidates.append(lx)
		if safe_candidates.size() > 0:
			return safe_candidates.pick_random()

	# Caso haja 0 ou 1 setor ocupado, qualquer candidate_lane preservará ao menos 1 setor desobstruído
	return candidate_lanes.pick_random()


# ==============================================================================
# 2. POOL FIXO DE ZUMBIS (10 INSTÂNCIAS ALTERNANDO VARIANTES)
# ==============================================================================

func _init_fixed_zombie_pool() -> void:
	zombie_pool.clear()
	var initial_z_spacing: float = 7.5

	for i in range(ZOMBIE_POOL_SIZE):
		var z_inst: Zombie = null
		# Alterna entre Variante 1 (Clássico) e Variante 2 (No-Arm)
		if i % 2 == 0:
			z_inst = zombie_classic_scene.instantiate() as Zombie
		else:
			z_inst = zombie_no_arm_scene.instantiate() as Zombie

		z_inst.name = "PooledZombie_%d" % i
		z_inst.is_pooled = true
		z_inst.target_player = player_node
		z_inst.road_speed = current_speed
		z_inst.died.connect(_on_zombie_died)

		zombies_container.add_child(z_inst)
		zombie_pool.append(z_inst)

		# Posicionamento inicial escalonado à frente do jogador com garantia de brechas
		var init_z: float = -38.0 - (i * initial_z_spacing)
		var lane_x: float = _get_valid_lane_with_breach(init_z, lanes, z_inst)
		z_inst.recycle(Vector3(lane_x, 0.0, init_z), current_speed)


func _on_zombie_died(_zombie: Zombie, points: int, was_headshot: bool = false) -> void:
	zombie_killed_event.emit(points, was_headshot)


# ==============================================================================
# 3. POOL FIXO DE CARROS DESTRUÍDOS (6 INSTÂNCIAS)
# ==============================================================================

func _init_fixed_car_pool() -> void:
	car_pool.clear()
	var initial_z_spacing: float = 18.0

	for i in range(CAR_POOL_SIZE):
		var car_inst = wrecked_car_scene.instantiate() as WreckedCar
		car_inst.name = "PooledCar_%d" % i
		obstacles_container.add_child(car_inst)
		car_pool.append(car_inst)

		# Posicionamento inicial escalonado em faixas laterais e acostamentos com brecha garantida
		var init_z: float = -25.0 - (i * initial_z_spacing)
		var side_x: float = _get_valid_lane_with_breach(init_z, side_lanes, car_inst)
		var rot_y: float = randf_range(-25.0, 25.0)
		car_inst.activate(Vector3(side_x, 0.0, init_z), rot_y)


# ==============================================================================
# 4. POOL DE CAIXAS DE MUNIÇÃO TÁTICAS
# ==============================================================================

func _init_ammo_box_pool() -> void:
	ammo_box_pool.clear()
	for i in range(6):
		var scene_to_use = ammo_pickup_scene if ammo_pickup_scene else ammo_box_scene
		var box = scene_to_use.instantiate() as Node3D
		box.name = "PooledTacticalPickup_%d" % i
		if box.has_signal("collected"):
			box.collected.connect(func(amount):
				ammo_collected.emit(amount)
				var hud = get_tree().get_first_node_in_group("hud")
				if hud and hud.has_method("show_ammo_collected"):
					if "pickup_type" in box and box.pickup_type == AmmoPickup.PickupType.AMMO:
						hud.show_ammo_collected(amount)
			)
		pickups_container.add_child(box)
		if box.has_method("deactivate"):
			box.deactivate()
		else:
			box.visible = false
		ammo_box_pool.append(box)


func _spawn_tactical_ammo_box(player_z: float) -> void:
	for box in ammo_box_pool:
		if ("is_active" in box and not box.is_active) or not box.visible:
			# Posiciona intencionalmente perto de um obstáculo (como próximo à traseira de um carro destruído)
			var target_car: WreckedCar = null
			for car in car_pool:
				if car.is_active and car.global_position.z < player_z - 25.0 and car.global_position.z > player_z - 75.0:
					target_car = car
					break

			var spawn_pos := Vector3.ZERO
			if target_car:
				# Perto da traseira do carro destruído com ligeiro desvio lateral (+2.0 a +3.2m em Z)
				var car_pos = target_car.global_position
				var side_offset: float = 1.15 if car_pos.x >= 0.0 else -1.15
				spawn_pos = Vector3(car_pos.x + side_offset, 0.0, car_pos.z + randf_range(2.0, 3.2))
			else:
				# Se não houver carro na janela imediata, posiciona nas faixas laterais de risco
				var lane_x: float = side_lanes.pick_random()
				spawn_pos = Vector3(lane_x, 0.0, player_z - randf_range(50.0, 65.0))

			# Determina tipo inteligente de drop (Medkit priorizado se com vida baixa)
			var chosen_type = AmmoPickup.PickupType.AMMO
			var roll: float = randf()
			var is_low_health: bool = (player_node and player_node.health < (player_node.max_health * 0.55))
			if is_low_health:
				if roll < 0.50:
					chosen_type = AmmoPickup.PickupType.MEDKIT
				elif roll < 0.80:
					chosen_type = AmmoPickup.PickupType.AMMO
				else:
					chosen_type = AmmoPickup.PickupType.ADRENALINE
			else:
				if roll < 0.50:
					chosen_type = AmmoPickup.PickupType.AMMO
				elif roll < 0.75:
					chosen_type = AmmoPickup.PickupType.MEDKIT
				else:
					chosen_type = AmmoPickup.PickupType.ADRENALINE

			if box.has_method("activate"):
				box.activate(spawn_pos, current_speed, chosen_type)
			else:
				box.global_position = spawn_pos
				box.visible = true
			return


# ==============================================================================
# POOLS DE BARRIS EXPLOSIVOS E BARRICADAS MILITARES
# ==============================================================================

func _init_fixed_barrel_pool() -> void:
	barrel_pool.clear()
	for i in range(BARREL_POOL_SIZE):
		var barrel = explosive_barrel_scene.instantiate() as Node3D
		barrel.name = "PooledBarrel_%d" % i
		barrels_container.add_child(barrel)
		barrel_pool.append(barrel)

		# Posiciona os primeiros barris à frente na rodovia
		var spawn_z: float = -45.0 - (i * 35.0)
		var lane_x: float = [-2.2, 0.0, 2.2].pick_random()
		_activate_barrel(barrel, Vector3(lane_x, 0.0, spawn_z))


func _activate_barrel(barrel: Node3D, pos: Vector3) -> void:
	if not is_instance_valid(barrel):
		return
	barrel.global_position = pos
	barrel.visible = true
	if "is_exploded" in barrel:
		barrel.is_exploded = false
	if "is_active" in barrel:
		barrel.is_active = true
	if "current_health" in barrel:
		barrel.current_health = barrel.max_health
	var col = barrel.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.set_deferred("disabled", false)
	var visual = barrel.get_node_or_null("VisualMesh") as Node3D
	if visual:
		visual.visible = true


func _init_fixed_barricade_pool() -> void:
	barricade_pool.clear()
	for i in range(BARRICADE_POOL_SIZE):
		var bar = military_barricade_scene.instantiate() as Node3D
		bar.name = "PooledBarricade_%d" % i
		barricades_container.add_child(bar)
		barricade_pool.append(bar)
		if bar.has_method("deactivate"):
			bar.deactivate()


func _init_fixed_oil_pool() -> void:
	oil_slick_pool.clear()
	for i in range(OIL_POOL_SIZE):
		var slick = OilSlickScript.new()
		slick.name = "PooledOilSlick_%d" % i
		oil_container.add_child(slick)
		slick.deactivate()
		oil_slick_pool.append(slick)


func _spawn_tactical_oil_slick(player_z: float) -> void:
	for slick in oil_slick_pool:
		if not slick.is_active or not slick.visible:
			var lane_x: float = lanes.pick_random()
			var spawn_pos = Vector3(lane_x, 0.0, player_z - randf_range(48.0, 72.0))
			slick.activate(spawn_pos, current_speed)
			return


func _process_oil_slicks(_delta: float) -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	if distance_traveled >= next_oil_checkpoint:
		_spawn_tactical_oil_slick(player_z)
		next_oil_checkpoint += randf_range(80.0, 130.0)

	for slick in oil_slick_pool:
		if slick.is_active and slick.global_position.z > player_z + 15.0:
			slick.deactivate()


## Aciona a Horda Relâmpago (Swarm Surge): recicla 3 a 4 zumbis em formação de cunha em alta velocidade (Sprinters)
func trigger_swarm_surge() -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0
	var player_x: float = player_node.global_position.x if (player_node and player_node.is_inside_tree()) else 0.0

	var candidates: Array[Zombie] = []
	for z in zombie_pool:
		if is_instance_valid(z) and (not z.is_alive or z.global_position.z > player_z + 10.0):
			candidates.append(z)
			if candidates.size() >= 4:
				break

	if candidates.size() < 3:
		for z in zombie_pool:
			if not z in candidates:
				candidates.append(z)
				if candidates.size() >= 3:
					break

	# Distribui os zumbis em formação de cunha na frente do jogador
	var surge_lanes = [-2.2, 0.0, 2.2]
	for i in range(mini(candidates.size(), 3)):
		var z = candidates[i]
		var lane_x: float = surge_lanes[i]
		var z_dist: float = player_z - 38.0 - (float(i) * 5.0)
		z.recycle(Vector3(lane_x, 0.0, z_dist), current_speed)
		if z.has_method("set_as_sprinter"):
			z.set_as_sprinter(true)
		elif z.has_method("set_as_fast_runner"):
			z.set_as_fast_runner(true)

	if candidates.size() >= 4:
		var z4 = candidates[3]
		var flank_x: float = -4.5 if player_x >= 0.0 else 4.5
		z4.recycle(Vector3(flank_x, 0.0, player_z - 46.0), current_speed)
		if z4.has_method("set_as_sprinter"):
			z4.set_as_sprinter(true)


## Retorna o fator de dificuldade progressiva de 0.0 (início) a 1.0 (resgate/800m) e além no Modo Pesadelo
func get_difficulty_factor() -> float:
	if GameController.selected_game_mode == GameController.GameMode.ENDLESS_NIGHTMARE and distance_traveled > 750.0:
		return 1.0 + ((distance_traveled - 750.0) / 1000.0)
	return clampf(distance_traveled / 750.0, 0.0, 1.0)


## Ajusta velocidade e escalonamento de dificuldade para os tiers do Modo Pesadelo
func apply_nightmare_tier(tier: int) -> void:
	base_speed = minf(22.0, 10.5 + float(tier) * 1.2)
	current_speed = maxf(current_speed, base_speed)
	max_speed = minf(26.0, 18.0 + float(tier) * 1.5)
	speed_changed.emit(current_speed)


## Presets de Perigo Estruturados (Emboscada em Funil e Barricada Militar)
func _process_hazard_presets() -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	if distance_traveled >= next_hazard_preset_checkpoint:
		var diff: float = get_difficulty_factor()
		next_hazard_preset_checkpoint += lerpf(120.0, 75.0, diff)

		var spawn_z: float = player_z - randf_range(55.0, 75.0)
		if randf() < 0.5:
			_trigger_funnel_ambush(spawn_z)
		else:
			_trigger_military_barricade_preset(spawn_z)


## Preset "Emboscada em Funil": 2 carros bloqueando faixas 1 e 3, forçando passagem na faixa 2 com zumbi corredor
func _trigger_funnel_ambush(spawn_z: float) -> void:
	var chosen_cars: Array[WreckedCar] = []
	for car in car_pool:
		if is_instance_valid(car) and not car.is_active:
			chosen_cars.append(car)
			if chosen_cars.size() >= 2:
				break

	if chosen_cars.size() < 2:
		for car in car_pool:
			if not car in chosen_cars:
				chosen_cars.append(car)
				if chosen_cars.size() >= 2:
					break

	if chosen_cars.size() >= 2:
		# Bloqueia faixas laterais 1 e 3 (esquerda: -4.5 e direita: 4.5)
		chosen_cars[0].activate(Vector3(-4.5, 0.0, spawn_z), randf_range(-12.0, 12.0))
		chosen_cars[1].activate(Vector3(4.5, 0.0, spawn_z), randf_range(-12.0, 12.0))

	# Zumbi corredor de frente no centro (faixa 2, X = 0.0) na boca do funil
	for z in zombie_pool:
		if is_instance_valid(z) and (not z.is_alive or z.global_position.z > (player_node.global_position.z if player_node else 0.0) + 15.0):
			z.recycle(Vector3(0.0, 0.0, spawn_z + 4.5), current_speed)
			if z.has_method("set_as_fast_runner"):
				z.set_as_fast_runner(true)
			break

	# Posiciona barril explosivo na beirada para opção tática
	_spawn_tactical_barrel_near_zombies(spawn_z)


## Preset "Barricada Militar": cerca de arame e concreto exigindo desvio brusco de pista
func _trigger_military_barricade_preset(spawn_z: float) -> void:
	var barricade: Node3D = null
	for bar in barricade_pool:
		if is_instance_valid(bar) and not bar.get("is_active"):
			barricade = bar
			break
	if not barricade and barricade_pool.size() > 0:
		barricade = barricade_pool[0]

	if barricade and barricade.has_method("activate"):
		var side_x: float = -3.8 if randf() < 0.5 else 3.8
		barricade.activate(Vector3(side_x, 0.0, spawn_z))

		# Ocasionalmente posiciona barril explosivo próximo à barricada
		if randf() < 0.70:
			_spawn_tactical_barrel_near_zombies(spawn_z + randf_range(-3.0, 3.0))


## Posiciona barril de combustível explosivo estrategicamente próximo a aglomerações de zumbis
func _spawn_tactical_barrel_near_zombies(target_z: float) -> void:
	for b in barrel_pool:
		if is_instance_valid(b) and ("is_exploded" in b and (b.is_exploded or not b.visible)):
			var lane_x: float = [-2.2, 0.0, 2.2].pick_random()
			_activate_barrel(b, Vector3(lane_x, 0.0, target_z + randf_range(-2.0, 2.0)))
			return


func _process_barrels_pool() -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	for b in barrel_pool:
		if not is_instance_valid(b):
			continue
		if b.global_position.z > player_z + 15.0:
			var diff: float = get_difficulty_factor()
			var new_z: float = player_z - randf_range(lerpf(45.0, 30.0, diff), 75.0)
			var lane_x: float = [-2.2, 0.0, 2.2].pick_random()
			_activate_barrel(b, Vector3(lane_x, 0.0, new_z))


func _process_barricades_pool() -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	for bar in barricade_pool:
		if not is_instance_valid(bar) or not bar.is_active:
			continue
		if bar.global_position.z > player_z + 15.0:
			bar.deactivate()


# ==============================================================================
# 5. LOOP DE PROCESSAMENTO E RECICLAGEM PROCEDURAL (ZERO ALOCAÇÕES)
# ==============================================================================

func _physics_process(delta: float) -> void:
	# Interrupção imediata da progressão do mundo em Game Over
	if is_game_over or GameManager.is_game_over or GameController.is_game_over:
		current_speed = 0.0
		for z in zombie_pool:
			if is_instance_valid(z):
				z.speed = 0.0
				z.road_speed = 0.0
		return

	# Multiplicador de velocidade (ex: +10% com a faca em punho)
	var speed_mult: float = 1.0
	if player_node and player_node.has_method("get_speed_multiplier"):
		speed_mult = player_node.get_speed_multiplier()
	var effective_speed: float = current_speed * speed_mult

	# Atualiza aceleração e velocidade se não estiver em resgate nem em agarrão/emboscada QTE
	if not rescue_triggered and (not player_node or not player_node.is_grappled):
		current_speed = minf(max_speed, current_speed + speed_acceleration * delta)
		if GameManager.instance and "distance_traveled" in GameManager.instance:
			distance_traveled = GameManager.instance.distance_traveled
		distance_updated.emit(distance_traveled)
		speed_changed.emit(effective_speed)

	# Atualiza timer do Adrenaline Rush
	if adrenaline_timer > 0.0:
		adrenaline_timer -= delta
		if adrenaline_timer <= 0.0:
			# Retorna suavemente para a velocidade normal
			current_speed = maxf(base_speed, current_speed - 3.5)

	# Sincroniza estado de velocidade e adrenalina com o Player para FOV dinâmico e Bobbing em 8
	if player_node:
		player_node.current_road_speed = effective_speed
		player_node.is_adrenaline_rush = (adrenaline_timer > 0.0)

	# 1. Movimenta módulos de rodovia
	_update_highway_modules(delta, effective_speed)

	# 2. Monitora e recicla Zumbis no pool
	_process_zombies_pool(delta, effective_speed)

	# 3. Monitora e recicla Carros no pool
	_process_cars_pool(delta, effective_speed)

	# 4. Monitora caixas de munição táticas
	_process_ammo_boxes(delta)

	# 4.5. Monitora manchas de óleo diesel deslizantes
	_process_oil_slicks(delta)

	# 5. Monitora barris de combustível explosivo
	_process_barrels_pool()

	# 6. Monitora barricadas militares
	_process_barricades_pool()

	# 7. Monitora presets de perigo estruturados (Dificuldade Dinâmica)
	_process_hazard_presets()

	# 8. Oscilação das luzes dos postes caídos (curto-circuito)
	_process_street_lights_flicker()

	# 8.5. Clímax de Extração Visual (700m a 800m): Sinalizadores carmesins e holofote militar varrendo o asfalto
	_process_extraction_beacon(delta)

	# 9. Verifica objetivo de Resgate (800m) exclusivamente no Modo Campanha
	if distance_traveled >= target_distance and not rescue_triggered:
		if GameController.selected_game_mode == GameController.GameMode.CAMPAIGN:
			rescue_triggered = true
			rescue_reached.emit()


## Cria e atualiza a Zona de Pouso / Extração Militar aos 700m-800m (Sinalizadores Vermelhos e Holofote de Helicóptero)
func _process_extraction_beacon(delta: float) -> void:
	if GameController.selected_game_mode != GameController.GameMode.CAMPAIGN:
		return
	if distance_traveled >= 680.0 and not extraction_beacon_node:
		_spawn_extraction_zone()
	if extraction_beacon_node and is_instance_valid(extraction_beacon_node):
		extraction_rotor_phase += delta * 4.5
		if extraction_spot and is_instance_valid(extraction_spot):
			extraction_spot.rotation_degrees.y = sin(extraction_rotor_phase) * 35.0


func _spawn_extraction_zone() -> void:
	extraction_beacon_node = Node3D.new()
	extraction_beacon_node.name = "ExtractionZoneVisual"
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else -distance_traveled
	var remaining_dist: float = maxf(25.0, target_distance - distance_traveled)
	extraction_beacon_node.position = Vector3(0.0, 0.0, player_z - remaining_dist)
	add_child(extraction_beacon_node)

	# Sinalizadores de Fumaça Carmesim (Flares) nas duas laterais da Zona de Pouso
	for fx in [-5.2, 5.2]:
		var flare_light := OmniLight3D.new()
		flare_light.position = Vector3(fx, 0.6, 0.0)
		flare_light.light_color = Color(1.0, 0.12, 0.12)
		flare_light.light_energy = 6.5
		flare_light.light_volumetric_fog_energy = 5.0
		flare_light.omni_range = 18.0
		extraction_beacon_node.add_child(flare_light)

		var flare_particles := GPUParticles3D.new()
		flare_particles.position = Vector3(fx, 0.2, 0.0)
		flare_particles.amount = 32
		flare_particles.lifetime = 1.6
		var fmat := ParticleProcessMaterial.new()
		fmat.direction = Vector3(0, 1, 0)
		fmat.spread = 18.0
		fmat.initial_velocity_min = 2.5
		fmat.initial_velocity_max = 4.8
		fmat.gravity = Vector3(0, 1.2, 0)
		fmat.scale_min = 0.5
		fmat.scale_max = 1.4
		fmat.color = Color(1.0, 0.18, 0.18, 0.65)
		flare_particles.process_material = fmat

		var quad := QuadMesh.new()
		quad.size = Vector2(0.7, 0.7)
		var qmat := StandardMaterial3D.new()
		qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qmat.albedo_color = Color(1.0, 0.2, 0.2, 0.55)
		quad.material = qmat
		flare_particles.draw_pass_1 = quad
		extraction_beacon_node.add_child(flare_particles)

	# Holofote Militar de Helicóptero varrendo o asfalto do alto
	extraction_spot = SpotLight3D.new()
	extraction_spot.name = "HelicopterSearchlight"
	extraction_spot.position = Vector3(0.0, 16.0, -4.0)
	extraction_spot.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	extraction_spot.light_color = Color(0.88, 0.95, 1.0)
	extraction_spot.light_energy = 9.0
	extraction_spot.light_volumetric_fog_energy = 6.5
	extraction_spot.spot_range = 45.0
	extraction_spot.spot_angle = 32.0
	extraction_beacon_node.add_child(extraction_spot)


## Oscilação estocástica das luzes dos postes de iluminação (efeito de luz falhando/curto-circuito)
func _process_street_lights_flicker() -> void:
	for light in flickering_street_lights:
		if is_instance_valid(light) and light.is_inside_tree():
			if randf() < 0.16:
				light.light_energy = randf_range(0.0, 0.4)
			else:
				light.light_energy = randf_range(2.0, 4.2)


## Monitora os 10 zumbis: teletransporta e recicla com dificuldade dinâmica
func _process_zombies_pool(_delta: float, run_speed: float = -1.0) -> void:
	var speed_to_use: float = run_speed if run_speed >= 0.0 else current_speed
	var player_pos: Vector3 = player_node.global_position if (player_node and player_node.is_inside_tree()) else Vector3.ZERO
	var player_z: float = player_pos.z

	for z in zombie_pool:
		if not is_instance_valid(z):
			continue

		z.road_speed = speed_to_use

		# Teletransporte e reciclagem: ultrapassou a mais de 15 metros atrás do jogador
		if z.global_position.z > player_z + 15.0:
			var diff: float = get_difficulty_factor()
			var new_z: float = player_z - randf_range(lerpf(45.0, 32.0, clampf(diff, 0.0, 1.0)), 75.0)
			var new_x: float = _get_valid_lane_with_breach(new_z, lanes, z)
			z.recycle(Vector3(new_x, 0.0, new_z), speed_to_use)

			# Dificuldade Dinâmica e Mutator Horda Voraz
			var fast_chance: float = lerpf(0.20, 0.85, clampf(diff, 0.0, 1.0))
			if GameController.mutator_all_runners:
				fast_chance = 1.0
			elif diff > 1.0:
				fast_chance = clampf(0.85 + (diff - 1.0) * 0.05, 0.85, 0.98)

			if z.has_method("set_as_fast_runner"):
				z.set_as_fast_runner(randf() < fast_chance)

			grazed_zombies.erase(z.get_instance_id())
			continue

		if not z.is_alive or z.is_dying:
			continue

		# Checagem de colisão e mecânica de raspão (Adrenaline Rush)
		if player_node and not player_node.is_dead:
			var dist_z: float = absf(z.global_position.z - player_pos.z)
			var dist_x: float = absf(z.global_position.x - player_pos.x)

			if dist_z < 1.15 and dist_x < 0.85:
				# Colisão frontal direta -> Aciona QTE Zombie Grapple se jogador não estiver engajado
				if not player_node.is_grappled and not player_node.get("is_in_ambush"):
					if player_node.has_method("start_zombie_grapple"):
						player_node.start_zombie_grapple(z)
				continue
			elif dist_z < 1.45 and dist_x >= 0.85 and dist_x < 1.85:
				# Sistema de Near-Miss (Raspão Quase-Fatal no Estilo Into the Dead 2)
				var z_id = z.get_instance_id()
				if not grazed_zombies.has(z_id):
					grazed_zombies[z_id] = true
					var player_is_on_right: bool = (player_pos.x > z.global_position.x)
					var dir_sign: float = 1.0 if player_is_on_right else -1.0

					# 1. Zumbi desfere unhada agressiva no ar
					if z.has_method("trigger_near_miss_swipe"):
						z.trigger_near_miss_swipe(player_is_on_right)

					# 2. Jogador sofre tremor, jolt de câmera, suspiro e micro time-dilation
					if player_node.has_method("trigger_near_miss"):
						player_node.trigger_near_miss(dir_sign, z)

					_trigger_adrenaline_rush()


## Ativa Adrenaline Rush: velocidade extra temporária e vinheta rápida
func _trigger_adrenaline_rush() -> void:
	adrenaline_timer = 1.5
	current_speed = minf(max_speed + 3.5, current_speed + 3.5)
	adrenaline_rush_triggered.emit(1.5)


## Monitora os 6 carros: obstáculos fixos que reciclam com intervalo reduzido conforme dificuldade
func _process_cars_pool(_delta: float, _run_speed: float = -1.0) -> void:
	var player_pos: Vector3 = player_node.global_position if (player_node and player_node.is_inside_tree()) else Vector3.ZERO
	var player_z: float = player_pos.z

	for car in car_pool:
		if not is_instance_valid(car) or not car.is_active:
			continue

		# Carros são carcaças fixas na pista (não se movem por esteira rolante cega).
		# Reciclagem: um bloco de estrada ou obstáculo só é movido para frente quando estiver a mais de 15 metros ATRÁS da posição Z atual da câmera/jogador.
		if car.global_position.z > player_z + 15.0:
			car.deactivate()
			var diff: float = get_difficulty_factor()
			# Dificuldade Dinâmica: reduz gradualmente o intervalo entre spawns de obstáculos conforme a distância avança
			var min_spawn_dist: float = lerpf(45.0, 26.0, diff)
			var max_spawn_dist: float = lerpf(75.0, 50.0, diff)
			var new_z: float = player_z - randf_range(min_spawn_dist, max_spawn_dist)
			var new_x: float = _get_valid_lane_with_breach(new_z, side_lanes, car)
			var rot_y: float = randf_range(-25.0, 25.0)
			car.activate(Vector3(new_x, 0.0, new_z), rot_y)
			continue

		# Checagem de colisão com o jogador
		if player_node and not player_node.is_dead:
			var dist_z: float = absf(car.global_position.z - player_pos.z)
			var dist_x: float = absf(car.global_position.x - player_pos.x)

			if dist_z < 2.3 and dist_x < 1.25 and not car.has_hit_player:
				car.has_hit_player = true
				if player_node.has_method("handle_car_collision"):
					player_node.handle_car_collision(car)
				player_node.take_damage(35.0, "Car Crash")


## Monitora caixas de munição táticas a cada 150 a 200 metros (mais escassas no Pesadelo)
func _process_ammo_boxes(_delta: float) -> void:
	var player_z: float = player_node.global_position.z if (player_node and player_node.is_inside_tree()) else 0.0

	# A cada 100 a 145m percorridos, gera drops táticos (Munição, Kit Médico ou Adrenalina)
	if distance_traveled >= next_ammo_checkpoint:
		_spawn_tactical_ammo_box(player_z)
		var interval_min: float = 100.0
		var interval_max: float = 145.0
		if GameController.selected_game_mode == GameController.GameMode.ENDLESS_NIGHTMARE and distance_traveled > 750.0:
			var n_mult = 1.0 + ((distance_traveled - 750.0) / 450.0)
			interval_min *= n_mult
			interval_max *= n_mult
		next_ammo_checkpoint += randf_range(interval_min, interval_max)

	for box in ammo_box_pool:
		if ("is_active" in box and box.is_active) and box.global_position.z > player_z + 15.0:
			if box.has_method("deactivate"):
				box.deactivate()
			else:
				box.visible = false
