extends Node


## Dead Run - Procedural Audio Manager & 3D Spatial Audio System (Godot 4.3)
## Gerencia a síntese procedural de efeitos sonoros, disparos com cauda de reverb,
## passos rítmicos em asfalto molhado, áudio espacial 3D para zumbis e combate corporal.

# --- SINGLETON DE ACESSO ---
static var instance: AudioManager = null

# --- CACHES DE ÁUDIO PROCEDURAL (AUDIOSTREAMWAV) ---
static var _cached_glock_shot: AudioStreamWAV = null
static var _cached_dry_fire: AudioStreamWAV = null
static var _cached_footsteps: Array[AudioStreamWAV] = []
static var _cached_zombie_growls: Array[AudioStreamWAV] = []
static var _cached_knife_stab: AudioStreamWAV = null
static var _cached_car_scrape: AudioStreamWAV = null
static var _cached_heartbeat: AudioStreamWAV = null
static var _cached_sector_transition: AudioStreamWAV = null
static var _cached_record_chime: AudioStreamWAV = null
static var _cached_siren_burst: AudioStreamWAV = null
static var _cached_nightmare_pulse: AudioStreamWAV = null
static var _cached_menu_drone: AudioStreamWAV = null
static var _cached_ui_click: AudioStreamWAV = null
static var _cached_thunder: AudioStreamWAV = null
static var _cached_near_miss_whoosh: AudioStreamWAV = null
static var _cached_player_gasp: AudioStreamWAV = null
static var _cached_zombie_claw_swipe: AudioStreamWAV = null
static var _cached_headshot_ding: AudioStreamWAV = null
static var _cached_combo_up: AudioStreamWAV = null
static var _cached_medkit_pickup: AudioStreamWAV = null
static var _cached_adrenaline_surge: AudioStreamWAV = null
static var _cached_oil_skid: AudioStreamWAV = null

# --- PLAYERS DE ÁUDIO 2D REUTILIZÁVEIS ---
var _sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX_PLAYERS: int = 12
var _current_player_idx: int = 0
var _footstep_player: AudioStreamPlayer = null
var _heartbeat_player: AudioStreamPlayer = null
var _menu_ambient_player: AudioStreamPlayer = null


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS # Funciona inclusive durante hit freeze / slow motion
	_init_audio_caches()
	_init_player_pool()


func _init_audio_caches() -> void:
	if _cached_glock_shot == null:
		_cached_glock_shot = _synthesize_glock_shot()
	if _cached_dry_fire == null:
		_cached_dry_fire = _synthesize_dry_fire()
	if _cached_footsteps.is_empty():
		for i in range(3):
			_cached_footsteps.append(_synthesize_wet_footstep(i))
	if _cached_zombie_growls.is_empty():
		for i in range(3):
			_cached_zombie_growls.append(_synthesize_zombie_growl(i))
	if _cached_knife_stab == null:
		_cached_knife_stab = _synthesize_knife_stab()
	if _cached_car_scrape == null:
		_cached_car_scrape = _synthesize_car_scrape()
	if _cached_heartbeat == null:
		_cached_heartbeat = _synthesize_heartbeat()
	if _cached_sector_transition == null:
		_cached_sector_transition = _synthesize_sector_transition()
	if _cached_record_chime == null:
		_cached_record_chime = _synthesize_record_chime()
	if _cached_siren_burst == null:
		_cached_siren_burst = _synthesize_siren_burst()
	if _cached_nightmare_pulse == null:
		_cached_nightmare_pulse = _synthesize_nightmare_pulse()
	if _cached_menu_drone == null:
		_cached_menu_drone = _synthesize_menu_drone()
	if _cached_ui_click == null:
		_cached_ui_click = _synthesize_ui_click()
	if _cached_thunder == null:
		_cached_thunder = _synthesize_thunder()
	if _cached_near_miss_whoosh == null:
		_cached_near_miss_whoosh = _synthesize_near_miss_whoosh()
	if _cached_player_gasp == null:
		_cached_player_gasp = _synthesize_player_gasp()
	if _cached_zombie_claw_swipe == null:
		_cached_zombie_claw_swipe = _synthesize_zombie_claw_swipe()
	if _cached_headshot_ding == null:
		_cached_headshot_ding = _synthesize_headshot_ding()
	if _cached_combo_up == null:
		_cached_combo_up = _synthesize_combo_up()
	if _cached_medkit_pickup == null:
		_cached_medkit_pickup = _synthesize_medkit_pickup()
	if _cached_adrenaline_surge == null:
		_cached_adrenaline_surge = _synthesize_adrenaline_surge()
	if _cached_oil_skid == null:
		_cached_oil_skid = _synthesize_oil_skid()


func _init_player_pool() -> void:
	for i in range(MAX_SFX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.name = "FootstepPlayer"
	_footstep_player.bus = "Master"
	_footstep_player.volume_db = -8.0
	add_child(_footstep_player)

	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.name = "HeartbeatPlayer"
	_heartbeat_player.bus = "Master"
	_heartbeat_player.volume_db = 2.0
	add_child(_heartbeat_player)

	_menu_ambient_player = AudioStreamPlayer.new()
	_menu_ambient_player.name = "MenuAmbientPlayer"
	_menu_ambient_player.bus = "Master"
	_menu_ambient_player.volume_db = -5.0
	add_child(_menu_ambient_player)


# ==============================================================================
# SÍNTESE PROCEDURAL DE ÁUDIO (22050 Hz - LEVE E ULTRA RÁPIDO)
# ==============================================================================

## 1. Disparo da Pistola Glock: estalo seco inicial, soco grave e cauda de reverberação leve
static func _synthesize_glock_shot() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.38
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# Transiente de estalo explosivo seco (primeiros 15ms)
		var snap_env: float = exp(-t * 95.0)
		var snap_noise: float = randf_range(-1.0, 1.0) * snap_env

		# Punch grave balístico (pitch sweep 240Hz -> 50Hz)
		var punch_freq: float = 50.0 + 190.0 * exp(-t * 40.0)
		var punch_env: float = exp(-t * 22.0)
		var punch_tone: float = sin(t * TAU * punch_freq) * punch_env

		# Cauda de reverberação tática
		var tail_env: float = (1.0 - (t / duration)) * exp(-t * 7.5)
		var tail_noise: float = randf_range(-0.5, 0.5) * tail_env * sin(t * TAU * 110.0)

		# Combinação e saturação suave
		var raw_val: float = snap_noise * 0.75 + punch_tone * 0.85 + tail_noise * 0.35
		var sample_val: float = clampf(raw_val * 1.25, -1.0, 1.0)
		var sample_int16: int = int(sample_val * 32767.0)
		byte_data.encode_s16(i * 2, sample_int16)

	return _build_wav(byte_data, sample_hz)


## 2. Dry Fire: clique metálico seco de gatilho/percussor sem bala
static func _synthesize_dry_fire() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.12
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# Clique duplo metálico rápido (sear + hammer strike aos 0.015s)
		var c1: float = exp(-t * 90.0) * sin(t * TAU * 2200.0)
		var t2: float = t - 0.016
		var c2: float = 0.0
		if t2 > 0.0:
			c2 = exp(-t2 * 110.0) * (sin(t2 * TAU * 3100.0) * 0.8 + randf_range(-0.4, 0.4) * 0.4)

		var raw_val: float = c1 * 0.6 + c2 * 0.85
		var sample_val: float = clampf(raw_val, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 3. Passo da Corrida: sola batendo no asfalto molhado com espirro de água/poça
static func _synthesize_wet_footstep(variant_seed: int = 0) -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.18
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	var thud_freq: float = 85.0 + float(variant_seed) * 15.0
	var splash_mult: float = 1.0 + float(variant_seed) * 0.15

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# Impacto surdo da sola no asfalto (primeiros 40ms)
		var sole_env: float = exp(-t * 36.0)
		var sole_thud: float = sin(t * TAU * (thud_freq - t * 180.0)) * sole_env

		# Respingos e espirros de água em poça d'água
		var wet_env: float = exp(-t * 24.0) * (1.0 - exp(-t * 120.0))
		var wet_noise: float = randf_range(-1.0, 1.0) * wet_env * splash_mult
		var wet_droplets: float = sin(t * TAU * 1850.0) * exp(-t * 45.0) * 0.35

		var raw_val: float = sole_thud * 0.7 + wet_noise * 0.45 + wet_droplets * 0.3
		var sample_val: float = clampf(raw_val * 0.85, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 4. Rosnado e Respiração Agressiva de Zumbi: gemidos guturais graves e chiado de garganta
static func _synthesize_zombie_growl(variant_seed: int = 0) -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 1.45
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	var base_freq: float = 78.0 + float(variant_seed) * 16.0
	var rasp_tremolo: float = 10.5 + float(variant_seed) * 2.0

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# Envelope de respiração pesada (sobe suavemente e cai)
		var breath_env: float = sin((t / duration) * PI) * (0.8 + 0.2 * sin(t * TAU * 1.8))

		# Tremolo gutural de cordas vocais corrompidas (vocal fry)
		var fry_mod: float = 0.5 + 0.5 * sin(t * TAU * rasp_tremolo)

		# Tom grave gutural com modulação de frequência
		var pitch_shift: float = sin(t * TAU * 2.2) * 14.0
		var vocal_tone: float = sin(t * TAU * (base_freq + pitch_shift)) * fry_mod

		# Respiração áspera / ar na garganta
		var rasp_noise: float = randf_range(-0.6, 0.6) * (0.4 + 0.6 * fry_mod)

		var raw_val: float = (vocal_tone * 0.65 + rasp_noise * 0.35) * breath_env
		var sample_val: float = clampf(raw_val * 0.90, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 5. Golpe de Faca e Queda Pesada: corte de carne + borrifo líquido + impacto de corpo no asfalto
static func _synthesize_knife_stab() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.55
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# FASE A: Lâmina cortando carne (fricção e estocada afiada 0.0s - 0.12s)
		var blade_env: float = exp(-t * 28.0)
		var blade_freq: float = 2400.0 - t * 8000.0
		var blade_slice: float = sin(t * TAU * maxf(600.0, blade_freq)) * blade_env * 0.55

		# FASE B: Borrifo líquido de sangue e estalo de osso/carne
		var squelch_noise: float = randf_range(-1.0, 1.0) * exp(-t * 18.0) * (0.6 + 0.4 * sin(t * TAU * 450.0))

		# FASE C: Corpo do zumbi caindo pesado no asfalto (0.16s adiante)
		var t_thud: float = t - 0.16
		var body_thud: float = 0.0
		if t_thud > 0.0:
			var thud_env: float = exp(-t_thud * 16.0)
			var thud_freq: float = 65.0 - t_thud * 40.0
			body_thud = (sin(t_thud * TAU * maxf(35.0, thud_freq)) + randf_range(-0.4, 0.4) * 0.35) * thud_env * 0.95

		var raw_val: float = blade_slice * 0.7 + squelch_noise * 0.65 + body_thud * 0.90
		var sample_val: float = clampf(raw_val, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 6. Esbarrão no Carro: chapa de aço amassando / raspando lataria
static func _synthesize_car_scrape() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.28
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = (1.0 - (t / duration)) * exp(-t * 4.2)
		var noise: float = randf_range(-1.0, 1.0)
		var screech: float = sin(t * TAU * 1650.0) * 0.30 + sin(t * TAU * 2380.0) * 0.25 + sin(t * TAU * 3120.0) * 0.18
		var sample_val: float = (noise * 0.55 + screech * 0.45) * env * 0.90
		byte_data.encode_s16(i * 2, int(clampf(sample_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 7. Pulso de Batimento Cardíaco (Aviso Crítico de QTE nos últimos 0.4s)
static func _synthesize_heartbeat() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.55
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)

		# Batimento 1 (LUB aos 0.0s)
		var b1_env: float = exp(-t * 22.0)
		var b1_tone: float = sin(t * TAU * (58.0 - t * 30.0)) * b1_env

		# Batimento 2 (DUB aos 0.18s)
		var t2: float = t - 0.18
		var b2_tone: float = 0.0
		if t2 > 0.0:
			var b2_env: float = exp(-t2 * 25.0)
			b2_tone = sin(t2 * TAU * (48.0 - t2 * 25.0)) * b2_env * 0.85

		var raw_val: float = (b1_tone + b2_tone) * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 8. Transição de Setor / Zona Militar: acorde marcial descendente e firme (440Hz -> 330Hz + subgrave)
static func _synthesize_sector_transition() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.45
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = (1.0 - (t / duration)) * exp(-t * 3.5)
		var freq1: float = 440.0 if t < 0.20 else 330.0
		var tone1: float = sin(t * TAU * freq1) * 0.55
		var sub_tone: float = sin(t * TAU * 110.0) * 0.45 * exp(-t * 2.0)
		var raw_val: float = (tone1 + sub_tone) * env * 0.95
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 9. Sino Triunfante de Novo Recorde Pessoal: 3 notas ascendentes cristalinas (Dó-Mi-Sol)
static func _synthesize_record_chime() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.58
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 4.5)
		var val: float = 0.0
		# Nota 1: Dó 523Hz (0.0s)
		val += sin(t * TAU * 523.25) * exp(-t * 6.0) * 0.45
		# Nota 2: Mi 659Hz (0.12s)
		var t2: float = t - 0.12
		if t2 > 0.0:
			val += sin(t2 * TAU * 659.25) * exp(-t2 * 6.0) * 0.45
		# Nota 3: Sol 784Hz (0.24s)
		var t3: float = t - 0.24
		if t3 > 0.0:
			val += sin(t3 * TAU * 783.99) * exp(-t3 * 5.0) * 0.55

		byte_data.encode_s16(i * 2, int(clampf(val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 10. Sirene de Quarentena / Evacuação Militar (Pitch sweep com distorção ríspida)
static func _synthesize_siren_burst() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.65
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = sin((t / duration) * PI)
		var freq: float = 520.0 + sin(t * TAU * 2.8) * 160.0
		var tone: float = sin(t * TAU * freq)
		# Harmônico distorcido
		var grit: float = sin(t * TAU * freq * 2.0) * 0.35
		var raw_val: float = (tone + grit) * env * 0.85
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 11. Pulso Opressor do Modo Pesadelo: estrondo sub-grave (45Hz) e distorção
static func _synthesize_nightmare_pulse() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.85
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 2.5) * (1.0 - (t / duration))
		var sub: float = sin(t * TAU * (46.0 - t * 12.0)) * 0.85
		var rumble: float = randf_range(-0.35, 0.35) * exp(-t * 5.0)
		var raw_val: float = (sub + rumble) * env * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 12. Drone Ambience de Menu (Tensão Soturna em 48Hz com vento e sub-grave)
static func _synthesize_menu_drone() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 3.5
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var sub: float = sin(t * TAU * 48.0) * 0.42 + sin(t * TAU * 50.5) * 0.22
		var wind_noise: float = randf_range(-0.14, 0.14) * (0.8 + 0.2 * sin(t * TAU * 0.35))
		var dark_tone: float = sin(t * TAU * 123.5) * 0.14 * (0.6 + 0.4 * sin(t * TAU * 0.25))
		var raw_val: float = (sub + wind_noise + dark_tone) * 0.85
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	var wav := _build_wav(byte_data, sample_hz)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_frames
	return wav


## 13. Clique Tátil de Interface Militar (UI Click)
static func _synthesize_ui_click() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.04
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 120.0)
		var click_tone: float = sin(t * TAU * 1400.0) * env
		var click_noise: float = randf_range(-0.6, 0.6) * exp(-t * 220.0)
		var sample_val: float = (click_tone * 0.6 + click_noise * 0.4)
		byte_data.encode_s16(i * 2, int(clampf(sample_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 14. Trovão Distante / Relâmpago na Tempestade
static func _synthesize_thunder() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 1.4
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = (1.0 - (t / duration)) * exp(-t * 2.2)
		var low_rumble: float = sin(t * TAU * (42.0 - t * 8.0)) * 0.70
		var crackle: float = randf_range(-0.4, 0.4) * exp(-t * 4.0)
		var raw_val: float = (low_rumble + crackle) * env * 1.2
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 15. Deslocamento de Ar e Raspar Quase-Fatal (Near-Miss Whoosh)
static func _synthesize_near_miss_whoosh() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.24
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = sin((t / duration) * PI)
		var freq: float = 850.0 - (t / duration) * 650.0 # Pitch sweep descendente rápido
		var tone: float = sin(t * TAU * freq) * 0.35
		var noise: float = randf_range(-0.8, 0.8) * 0.65
		var snap: float = randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.4
		var raw_val: float = (tone + noise + snap) * env * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 16. Suspiro / Respiração Súbita de Susto do Jogador (Player Gasp)
static func _synthesize_player_gasp() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.28
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		# Ataque rápido (primeiros 60ms) e expiração tensa
		var env: float = (t / 0.06) if t < 0.06 else exp(-(t - 0.06) * 11.0)
		var breath_noise: float = randf_range(-0.7, 0.7)
		var throat_formant: float = sin(t * TAU * 360.0) * 0.25 + sin(t * TAU * 720.0) * 0.15
		var raw_val: float = (breath_noise * 0.75 + throat_formant) * env * 0.95
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 17. Unhada Violenta e Rosnado Agressivo no Ar do Zumbi (Zombie Claw Swipe)
static func _synthesize_zombie_claw_swipe() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.32
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 6.5) * (1.0 - (t / duration))
		var claw_slice: float = randf_range(-0.9, 0.9) * exp(-t * 22.0) * 0.7
		# Rosnado gutural rápido modulado
		var growl_freq: float = 115.0 + sin(t * TAU * 35.0) * 30.0
		var growl_tone: float = sin(t * TAU * growl_freq) * 0.55
		var hiss: float = randf_range(-0.4, 0.4) * 0.35
		var raw_val: float = (claw_slice + growl_tone + hiss) * env * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 18. Ding Metálico e Crunch Visceral de Headshot Cirúrgico
static func _synthesize_headshot_ding() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.42
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		# 1. Crunch inicial (0.0 a 0.05s): estalo de impacto visceral
		var crunch_val: float = 0.0
		if t < 0.05:
			var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 90.0)
			var sub_thump: float = sin(t * TAU * 130.0) * exp(-t * 70.0)
			crunch_val = noise * 0.45 + sub_thump * 0.55

		# 2. Ding metálico cirúrgico ressonante (2200Hz fundamental + 3520Hz harmônico)
		var bell_env: float = exp(-t * 11.0)
		var bell_tone: float = (sin(t * TAU * 2200.0) * 0.55 + sin(t * TAU * 3520.0) * 0.35 + sin(t * TAU * 4840.0) * 0.15) * bell_env

		var raw_val: float = (crunch_val * 0.7 + bell_tone * 0.8) * 1.25
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 19. Notificação Tática de Subida de Combo (Arpejo e Sintetizador Ascendente)
static func _synthesize_combo_up() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.38
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = exp(-t * 7.0)
		var sweep_freq: float = 340.0 + (t / duration) * 420.0
		var tone: float = sin(t * TAU * sweep_freq) * 0.6
		var overtone: float = sin(t * TAU * sweep_freq * 1.5) * 0.3
		var raw_val: float = (tone + overtone) * env * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 20. Coleta de Kit Médico Militar (Acorde Maior Consonante de Alívio/Restauração)
static func _synthesize_medkit_pickup() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.45
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = (1.0 - exp(-t * 35.0)) * exp(-t * 5.5)
		var tone: float = sin(t * TAU * 330.0) * 0.4 + sin(t * TAU * 392.0) * 0.35 + sin(t * TAU * 493.8) * 0.25
		var raw_val: float = tone * env * 1.2
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 21. Descarga de Adrenalina Máxima (Whoosh Elétrico + Batimento Acelerado)
static func _synthesize_adrenaline_surge() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.50
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var whoosh: float = sin(t * TAU * (85.0 + t * 220.0)) * exp(-t * 4.0)
		var hiss: float = (randf() * 2.0 - 1.0) * exp(-t * 11.0) * 0.35
		var raw_val: float = (whoosh * 0.75 + hiss) * 1.15
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## 22. Derrapagem Descontrolada em Óleo Diesel (Wet Rubber Tire & Boot Skid)
static func _synthesize_oil_skid() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.48
	var total_frames: int = int(sample_hz * duration)
	var byte_data := PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		var env: float = sin((t / duration) * PI) * exp(-t * 2.5)
		var skid_freq: float = 850.0 + sin(t * TAU * 14.0) * 320.0 + (1.0 - (t / duration)) * 400.0
		var tone: float = sin(t * TAU * skid_freq) * 0.45
		var noise: float = (randf() * 2.0 - 1.0) * 0.55
		var raw_val: float = (tone + noise) * env * 1.05
		byte_data.encode_s16(i * 2, int(clampf(raw_val, -1.0, 1.0) * 32767.0))

	return _build_wav(byte_data, sample_hz)


## Empacota os bytes em AudioStreamWAV estéreo/mono
static func _build_wav(bytes: PackedByteArray, sample_hz: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_hz
	wav.stereo = false
	wav.data = bytes
	return wav


# ==============================================================================
# REPRODUÇÃO DE ÁUDIO GLOBAL E CONEXÃO DE EVENTOS
# ==============================================================================

## Obtém ou toca em um player SFX do pool
func _play_sfx_stream(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not stream or _sfx_players.is_empty():
		return

	var p: AudioStreamPlayer = _sfx_players[_current_player_idx]
	_current_player_idx = (_current_player_idx + 1) % _sfx_players.size()

	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Disparo da Glock
func play_glock_shot() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_glock_shot, 0.0, randf_range(0.96, 1.04))


## Clique seco sem munição (Dry fire)
func play_dry_fire() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_dry_fire, -2.0, randf_range(0.95, 1.05))


## Passo rítmico no asfalto molhado sincronizado com head bobbing
func play_wet_footstep() -> void:
	_init_audio_caches()
	if _cached_footsteps.is_empty() or not _footstep_player:
		return

	var stream = _cached_footsteps[randi() % _cached_footsteps.size()]
	_footstep_player.stream = stream
	_footstep_player.pitch_scale = randf_range(0.90, 1.10)
	_footstep_player.volume_db = randf_range(-9.0, -6.0)
	_footstep_player.play()


## Golpe da faca cravando no zumbi com borrifo e queda
func play_knife_stab() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_knife_stab, 2.5, randf_range(0.97, 1.03))


## Esbarrão lateral nos carros
func play_car_scrape() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_car_scrape, -2.0, randf_range(0.92, 1.08))


## Pulso cardíaco de aviso do QTE
func play_heartbeat_warning() -> void:
	_init_audio_caches()
	if not _heartbeat_player:
		return
	_heartbeat_player.stream = _cached_heartbeat
	_heartbeat_player.pitch_scale = randf_range(0.98, 1.02)
	_heartbeat_player.play()


## Transição de setor militar com tom marcante
func play_sector_transition() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_sector_transition, 1.0, 1.0)


## Sino triunfante ao bater novo recorde de distância/pontuação
func play_record_chime() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_record_chime, 2.5, 1.0)


## Sirene militar de evacuação / quarentena
func play_siren_burst() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_siren_burst, 0.5, randf_range(0.95, 1.05))


## Pulso profundo e opressor ao ultrapassar fronteira para o Pesadelo
func play_nightmare_pulse() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_nightmare_pulse, 3.0, 0.98)


## Toca a ambiência soturna do menu principal em loop suave
func play_menu_ambience() -> void:
	_init_audio_caches()
	if not _menu_ambient_player:
		return
	if _menu_ambient_player.playing:
		return
	_menu_ambient_player.stream = _cached_menu_drone
	_menu_ambient_player.volume_db = -5.0
	_menu_ambient_player.play()


## Interrompe a ambiência do menu
func stop_menu_ambience() -> void:
	if _menu_ambient_player and _menu_ambient_player.playing:
		_menu_ambient_player.stop()


## Clique tátil de interface militar
func play_ui_click() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_ui_click, -4.0, randf_range(0.95, 1.05))


## Trovão distante acompanhando relâmpago
func play_thunder() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_thunder, 1.5, randf_range(0.92, 1.05))


## Efeito de deslocamento de ar ao raspar perigosamente por um zumbi
func play_near_miss_whoosh() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_near_miss_whoosh, 2.0, randf_range(0.95, 1.05))


## Suspiro tenso / respiração de susto do jogador
func play_player_gasp() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_player_gasp, 0.5, randf_range(0.95, 1.05))


## Unhada violenta no ar do zumbi ao errar o golpe
func play_zombie_swipe(player_3d: AudioStreamPlayer3D = null) -> void:
	_init_audio_caches()
	if player_3d and is_instance_valid(player_3d):
		player_3d.stream = _cached_zombie_claw_swipe
		player_3d.volume_db = 2.5
		player_3d.pitch_scale = randf_range(0.94, 1.06)
		player_3d.play()
	else:
		_play_sfx_stream(_cached_zombie_claw_swipe, 2.0, randf_range(0.94, 1.06))


## Ding metálico e estalo de Headshot
func play_headshot_ding() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_headshot_ding, 3.2, randf_range(0.98, 1.02))


## Notificação de avanço de combo de adrenalina (pitch sobe por multiplicador)
func play_combo_up(multiplier: int = 2) -> void:
	_init_audio_caches()
	var pitch: float = 1.0
	if multiplier == 3:
		pitch = 1.15
	elif multiplier == 4:
		pitch = 1.30
	elif multiplier >= 5:
		pitch = 1.48
	_play_sfx_stream(_cached_combo_up, 2.8, pitch)


## Som de cura e alívio ao coletar Kit Médico
func play_medkit_pickup() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_medkit_pickup, 2.0, randf_range(0.98, 1.02))


## Surto de Adrenalina Máxima
func play_adrenaline_surge() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_adrenaline_surge, 3.0, randf_range(0.96, 1.04))


## Derrapagem / Perda de tração em mancha de óleo
func play_oil_skid() -> void:
	_init_audio_caches()
	_play_sfx_stream(_cached_oil_skid, 2.2, randf_range(0.94, 1.06))


# ==============================================================================
# ÁUDIO ESPACIAL 3D PARA ZUMBIS (AUDIOSTREAMPLAYER3D)
# ==============================================================================

## Configura e anexa um nó AudioStreamPlayer3D a uma instância de zumbi
static func setup_zombie_audio(zombie: Node3D) -> AudioStreamPlayer3D:
	if not zombie or not is_instance_valid(zombie):
		return null

	var player_3d = zombie.get_node_or_null("ZombieAudio3D") as AudioStreamPlayer3D
	if not player_3d:
		player_3d = AudioStreamPlayer3D.new()
		player_3d.name = "ZombieAudio3D"
		# Atenuação de distância e panning espacial lateral nítido
		player_3d.max_distance = 35.0
		player_3d.unit_size = 3.5
		player_3d.max_db = 1.0
		player_3d.panning_strength = 1.2 # Enfatiza posicionamento esquerda/direita na rodovia
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
		zombie.add_child(player_3d)

	return player_3d


## Toca gemido grave de zumbi no AudioStreamPlayer3D com variação e volume dinâmico
static func play_zombie_growl(player_3d: AudioStreamPlayer3D, is_close: bool = false) -> void:
	if not player_3d or not is_instance_valid(player_3d):
		return

	if _cached_zombie_growls.is_empty():
		for i in range(3):
			_cached_zombie_growls.append(_synthesize_zombie_growl(i))

	var stream = _cached_zombie_growls.pick_random()
	player_3d.stream = stream
	player_3d.pitch_scale = randf_range(0.88, 1.12)
	player_3d.volume_db = 1.5 if is_close else -1.5
	player_3d.play()
