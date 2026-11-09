class_name ExplosiveBarrel
extends StaticBody3D

## Dead Run - Barril de Combustível Explosivo (Godot 4.3)
## Obstáculo tático inflamável. Ao receber dano de tiro da Glock:
## detona com clarão, partículas de fogo, tremor de câmera e eliminação em área (4.5m) de zumbis.

signal exploded(barrel: ExplosiveBarrel)

@export var max_health: float = 20.0
@export var explosion_radius: float = 4.5
@export var explosion_damage: float = 999.0

var current_health: float = 20.0
var is_exploded: bool = false
var is_active: bool = true

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_mesh: Node3D = $VisualMesh
@onready var explosion_light: OmniLight3D = $ExplosionLight
@onready var fire_particles: GPUParticles3D = $FireParticles


func _ready() -> void:
	add_to_group("obstacles")
	add_to_group("explosive_barrels")
	add_to_group("destructibles")
	current_health = max_health
	is_exploded = false
	is_active = true

	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not visual_mesh:
		visual_mesh = get_node_or_null("VisualMesh") as Node3D
	if not explosion_light:
		explosion_light = get_node_or_null("ExplosionLight") as OmniLight3D
	if not fire_particles:
		fire_particles = get_node_or_null("FireParticles") as GPUParticles3D

	if explosion_light:
		explosion_light.visible = false
		explosion_light.light_energy = 0.0


## Recebe tiro da Glock ou dano externo
func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO, _hit_normal: Vector3 = Vector3.ZERO) -> void:
	if is_exploded or not is_active:
		return

	current_health -= amount
	if current_health <= 0.0 or amount >= 20.0:
		explode()


## Detonação imediata do combustível
func explode() -> void:
	if is_exploded:
		return
	is_exploded = true
	is_active = false
	exploded.emit(self)

	# 1. Desativa colisão física para não travar o jogador
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	# 2. Oculta a malha intacta do barril
	if visual_mesh:
		visual_mesh.visible = false

	# 3. Clarão estroboscópico alaranjado de fogo
	if explosion_light:
		explosion_light.visible = true
		explosion_light.light_energy = 8.5
		var light_tw := create_tween()
		light_tw.tween_property(explosion_light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Efeito de partículas de explosão e labaredas
	if fire_particles:
		fire_particles.emitting = true

	# 5. Efeito sonoro estrondoso procedural
	_play_explosion_audio()

	# 6. Tremor de tela na câmera do jogador se estiver perto
	var player: Player = null
	if is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Player
	if player and is_instance_valid(player):
		var dist_to_player: float = global_position.distance_to(player.global_position)
		if dist_to_player < 22.0:
			var shake_intensity: float = clampf((22.0 - dist_to_player) / 22.0 * 0.7, 0.25, 0.7)
			player.add_camera_shake(shake_intensity)
		if dist_to_player < 3.2:
			player.take_damage(25.0, "Explosion Blast")

	# 7. Elimina todos os zumbis no raio de 4.5 metros com animação "zombie falling" e sangue
	_eliminate_zombies_in_radius()

	# 8. Desativa após término dos efeitos visuais sem dar queue_free (mantém a instância viva no Object Pool!)
	if is_inside_tree():
		get_tree().create_timer(0.65).timeout.connect(func():
			if is_instance_valid(self) and is_exploded:
				visible = false
				if fire_particles:
					fire_particles.emitting = false
		)



func _eliminate_zombies_in_radius() -> void:
	if not is_inside_tree():
		return

	# Busca todos os zumbis na cena através de grupos e hierarquia
	var target_zombies: Array[Zombie] = []
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Zombie and node.is_alive:
			target_zombies.append(node)

	# Fallback através do Spawner se os zumbis estiverem em pool
	var spawner = get_tree().get_first_node_in_group("world_spawner")
	if not spawner:
		spawner = get_tree().get_first_node_in_group("spawner")
	if spawner and "zombie_pool" in spawner:
		for z in spawner.zombie_pool:
			if is_instance_valid(z) and z is Zombie and z.is_alive and not z in target_zombies:
				target_zombies.append(z)

	var my_pos: Vector3 = global_position
	for z in target_zombies:
		if not is_instance_valid(z) or not z.is_alive or z.is_dying:
			continue
		var dist: float = my_pos.distance_to(z.global_position)
		if dist <= explosion_radius:
			var hit_dir: Vector3 = (z.global_position - my_pos).normalized()
			hit_dir.y = 0.35
			var hit_point: Vector3 = z.global_position + Vector3(0.0, 1.2, 0.0)
			# take_damage com 999.0 de dano fatal aciona no Zombie o sangue e a queda "zombie falling.glb"
			z.take_damage(explosion_damage, hit_point, hit_dir, true)


func _play_explosion_audio() -> void:
	if not is_inside_tree():
		return
	var audio_player := AudioStreamPlayer3D.new()
	audio_player.name = "ExplosionAudioPlayer"
	audio_player.stream = _create_explosion_sound()
	audio_player.max_distance = 65.0
	audio_player.unit_size = 12.0
	add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(func():
		if is_instance_valid(audio_player):
			audio_player.queue_free()
	)


static func _create_explosion_sound() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.6
	var total_frames: int = int(sample_hz * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 6.5)
		var noise: float = randf_range(-1.0, 1.0)
		var sub_bass: float = sin(t * TAU * (65.0 * (1.0 - t * 0.8))) * 0.7
		var mid_blast: float = sin(t * TAU * 110.0) * 0.4
		var sample_val: float = (noise * 0.75 + sub_bass + mid_blast) * env * 0.95
		var sample_int16: int = int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		byte_data.encode_s16(i * 2, sample_int16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_hz
	wav.stereo = false
	wav.data = byte_data
	return wav
