class_name GameController
extends Node3D

## Dead Run - Main Game Controller & Objectives Manager (Godot 4.3 - Web / Playgama)
## Controla o loop de jogo jogável, meta de resgate (800m), contadores em destaque no HUD,
## vinheta de Adrenaline Rush e tela de Evacuação Concluída.

@export var target_distance: float = 800.0

@export_group("Referências de Nós")
@export var player: Player
@export var spawner: WorldSpawner
@export var world_environment: WorldEnvironment
@export var hud: GameHUD
@export var distance_label: Label
@export var ammo_label: Label
@export var health_bar: ProgressBar
@export var speed_label: Label

# --- ENUMS DE MODOS DE JOGO E ZONAS NARRATIVAS ---
enum GameMode {
	CAMPAIGN = 0,          ## 800m até o comboio de resgate
	ENDLESS_NIGHTMARE = 1  ## Sem fim, escalonamento infinito de dificuldade
}

enum SectorZone {
	NONE = 0,
	SECTOR_1_SHOCK = 1,          ## 0m - 250m: O Choque
	SECTOR_2_QUARANTINE = 2,     ## 250m - 500m: Zona de Quarentena
	SECTOR_3_HIGHWAY_HELL = 3,   ## 500m - 750m: O Inferno na Rodovia
	SECTOR_4_EXTRACTION = 4,     ## 750m - 800m: A Extração Final
	NIGHTMARE_DEEP = 5           ## 800m+: Pesadelo Sem Fim
}

# Instância global e flag de Game Over para congelamento imediato de entidades
static var instance: GameController = null
static var is_game_over: bool = false

# --- CONFIGURAÇÕES DE PARTIDA SELECIONADAS (PERSISTENTES ENTRE RELOADS) ---
static var selected_game_mode: GameMode = GameMode.CAMPAIGN
static var mutator_no_flashlight: bool = false
static var mutator_all_runners: bool = false
static var mutator_melee_only: bool = false

# --- SINAIS DE EVENTOS ---
signal sector_entered(sector_id: int, sector_title: String, sector_subtitle: String)
signal new_best_record_achieved(new_distance: float)
signal nightmare_tier_promoted(tier: int, current_distance: float)
signal combo_changed(multiplier: int, count: int, timer_ratio: float, combo_title: String)

# Elementos do HUD criados/gerenciados programaticamente (fallback)
var hud_root: CanvasLayer = null
var adrenaline_vignette: ColorRect = null
var ammo_notify_label: Label = null
var victory_panel: PanelContainer = null
var game_over_panel: PanelContainer = null

# Estatísticas de jogo e sessão
var total_score: int = 0
var zombies_killed: int = 0
var headshots_count: int = 0
var score_multiplier: float = 1.0
var game_finished: bool = false
var run_survival_time: float = 0.0

# --- SISTEMA DINÂMICO DE COMBO MULTIPLIER ---
var combo_count: int = 0
var combo_multiplier: int = 1
var combo_timer: float = 0.0
const COMBO_MAX_TIME: float = 3.6

# --- SISTEMA DE HORDA RELÂMPAGO (SWARM SURGE) ---
var is_swarm_active: bool = false
var swarm_timer: float = 0.0
var next_swarm_checkpoint: float = 220.0
const SWARM_DURATION: float = 6.0

# Estado das Zonas e Pesadelo
var current_sector: SectorZone = SectorZone.NONE
var has_breached_nightmare: bool = false
var last_nightmare_tier: int = 0
var has_beaten_previous_record: bool = false
var starting_best_distance: float = 0.0

# --- SISTEMA DINÂMICO DE TEMPESTADE E RELÂMPAGOS ---
var directional_light: DirectionalLight3D = null
var lightning_timer: float = 12.0
var base_dir_light_energy: float = 0.22
var base_dir_light_color: Color = Color(0.45, 0.56, 0.78)


func _ready() -> void:
	add_to_group("game_controller")
	instance = self
	is_game_over = false
	GameController.is_game_over = false
	GameManager.is_game_over = false

	starting_best_distance = HighScoreManager.get_best_distance()
	_configure_cinematic_environment()
	
	if not player:
		player = get_node_or_null("Player") as Player
	if not spawner:
		spawner = get_node_or_null("WorldSpawner") as WorldSpawner
	if not hud:
		hud = get_node_or_null("HUD") as GameHUD
		
	_setup_hud_effects()
	
	if hud:
		hud.target_distance = target_distance
		if hud.has_method("set_best_record_display"):
			hud.set_best_record_display(starting_best_distance)
		if hud.has_method("configure_mode_indicators"):
			hud.configure_mode_indicators(selected_game_mode, mutator_no_flashlight, mutator_all_runners, mutator_melee_only)
		
	if player:
		player.health_changed.connect(_on_player_health_changed)
		if player.has_signal("player_died"):
			player.player_died.connect(trigger_game_over)
		if player.has_signal("near_miss_occurred"):
			player.near_miss_occurred.connect(_on_player_near_miss)
		if hud:
			player.qte_grapple_started.connect(hud.show_qte_overlay)
			player.qte_progress_updated.connect(hud.update_qte_progress)
			player.qte_grapple_ended.connect(hud.hide_qte_overlay)
			hud.update_health(player.health, player.max_health)
			
		if player.weapon_manager:
			player.weapon_manager.ammo_updated.connect(_on_ammo_updated)
			_on_ammo_updated(player.weapon_manager.current_ammo, player.weapon_manager.reserve_ammo)
			
	if spawner:
		spawner.target_distance = target_distance
		spawner.distance_updated.connect(_on_distance_updated)
		spawner.speed_changed.connect(_on_speed_changed)
		spawner.zombie_killed_event.connect(_on_zombie_killed)
		spawner.adrenaline_rush_triggered.connect(_on_adrenaline_rush)
		spawner.ammo_collected.connect(_on_ammo_collected)
		spawner.rescue_reached.connect(_on_rescue_reached)
		
		if player and not spawner.player_node:
			spawner.player_node = player

	# Inicializa no Setor 1
	_check_sector_transition(0.0)
	lightning_timer = randf_range(9.0, 18.0)
	if AudioManager.instance:
		AudioManager.instance.play_menu_ambience()


func _process(delta: float) -> void:
	if not game_finished and not is_game_over:
		run_survival_time += delta
		_process_combo_decay(delta)
		_process_dynamic_thunderstorm(delta)
		_process_swarm_surge(delta)


func _process_swarm_surge(delta: float) -> void:
	if not spawner:
		return

	if not is_swarm_active and spawner.distance_traveled >= next_swarm_checkpoint and not is_game_over:
		_start_swarm_surge()
		next_swarm_checkpoint += randf_range(220.0, 290.0)

	if is_swarm_active:
		swarm_timer -= delta
		if swarm_timer <= 0.0:
			_complete_swarm_surge()


func _start_swarm_surge() -> void:
	is_swarm_active = true
	swarm_timer = SWARM_DURATION
	if AudioManager.instance:
		AudioManager.instance.play_siren_burst()
	if hud and hud.has_method("show_swarm_surge_alert"):
		hud.show_swarm_surge_alert(SWARM_DURATION)
	if spawner and spawner.has_method("trigger_swarm_surge"):
		spawner.trigger_swarm_surge()


func _complete_swarm_surge() -> void:
	is_swarm_active = false
	swarm_timer = 0.0
	var bonus: int = int(300 * score_multiplier)
	total_score += bonus
	register_combo_action(2, "SWARM_SURVIVED")
	if AudioManager.instance:
		AudioManager.instance.play_record_chime()
	if hud and hud.has_method("show_swarm_survived_feedback"):
		hud.show_swarm_survived_feedback(bonus)


func _process_combo_decay(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - delta)
		var ratio: float = combo_timer / COMBO_MAX_TIME
		if hud and hud.has_method("update_combo_timer"):
			hud.update_combo_timer(ratio)
		if combo_timer <= 0.0:
			_reset_combo()


func _reset_combo() -> void:
	combo_count = 0
	combo_multiplier = 1
	combo_timer = 0.0
	score_multiplier = 1.0
	combo_changed.emit(combo_multiplier, combo_count, 0.0, "")
	if hud and hud.has_method("hide_combo_display"):
		hud.hide_combo_display()


func register_combo_action(weight: int = 1, action_tag: String = "") -> void:
	if game_finished or is_game_over:
		return

	combo_count += weight
	combo_timer = COMBO_MAX_TIME

	var old_mult: int = combo_multiplier
	var new_mult: int = 1
	var combo_title: String = ""

	if combo_count >= 14:
		new_mult = 5
		combo_title = "GODLIKE"
	elif combo_count >= 9:
		new_mult = 4
		combo_title = "RELENTLESS"
	elif combo_count >= 5:
		new_mult = 3
		combo_title = "UNSTOPPABLE"
	elif combo_count >= 2:
		new_mult = 2
		combo_title = "RAMPAGE"
	else:
		new_mult = 1
		combo_title = ""

	combo_multiplier = new_mult
	score_multiplier = float(combo_multiplier)

	if new_mult > old_mult and new_mult >= 2:
		if AudioManager.instance:
			AudioManager.instance.play_combo_up(new_mult)
		if hud and hud.has_method("trigger_combo_burst"):
			hud.trigger_combo_burst(new_mult, combo_title)

	combo_changed.emit(combo_multiplier, combo_count, 1.0, combo_title)
	if hud and hud.has_method("update_combo_display"):
		hud.update_combo_display(combo_multiplier, combo_count, 1.0, combo_title)


func _process_dynamic_thunderstorm(delta: float) -> void:
	lightning_timer -= delta
	if lightning_timer <= 0.0:
		lightning_timer = randf_range(12.0, 24.0)
		_trigger_lightning_strike()


func _trigger_lightning_strike() -> void:
	if not directional_light:
		directional_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if directional_light:
		var ltw := create_tween()
		# Flash duplo de relâmpago branco-azulado projetando sombras dramáticas na pista
		directional_light.light_color = Color(0.82, 0.90, 1.0)
		ltw.tween_property(directional_light, "light_energy", 2.8, 0.04)
		ltw.tween_property(directional_light, "light_energy", 0.35, 0.06)
		ltw.tween_property(directional_light, "light_energy", 3.6, 0.05)
		ltw.tween_property(directional_light, "light_energy", base_dir_light_energy, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ltw.tween_callback(func():
			if directional_light:
				directional_light.light_color = base_dir_light_color
		)

	# Estrondo de trovão após 0.35s + leve tremor atmosférico na câmera
	if is_inside_tree():
		get_tree().create_timer(0.35).timeout.connect(func():
			if AudioManager.instance:
				AudioManager.instance.play_thunder()
			if player and is_instance_valid(player) and not player.is_dead:
				player.add_camera_shake(0.22)
		)


func _setup_hud_effects() -> void:
	hud_root = get_node_or_null("HUD") as CanvasLayer
	if not hud_root:
		return

	# 1. Vinheta rápida para Adrenaline Rush (raspão em zumbi vivo)
	adrenaline_vignette = hud_root.get_node_or_null("AdrenalineVignette") as ColorRect
	if not adrenaline_vignette:
		adrenaline_vignette = ColorRect.new()
		adrenaline_vignette.name = "AdrenalineVignette"
		adrenaline_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		adrenaline_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Tom ciano / azul elétrico sutil com transparência inicial 0
		adrenaline_vignette.color = Color(0.15, 0.75, 1.0, 0.0)
		hud_root.add_child(adrenaline_vignette)
		hud_root.move_child(adrenaline_vignette, 0) # Fica atrás dos textos

	# 2. Notificação visual de coleta de munição (+6 BALAS)
	ammo_notify_label = hud_root.get_node_or_null("AmmoNotifyLabel") as Label
	if not ammo_notify_label:
		ammo_notify_label = Label.new()
		ammo_notify_label.name = "AmmoNotifyLabel"
		ammo_notify_label.set_anchors_preset(Control.PRESET_CENTER)
		ammo_notify_label.position = Vector2(-100, 40)
		ammo_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ammo_notify_label.add_theme_font_size_override("font_size", 26)
		ammo_notify_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.0))
		ammo_notify_label.text = "+6 BALAS (MUNIÇÃO TÁTICA)"
		hud_root.add_child(ammo_notify_label)


func _on_distance_updated(dist: float) -> void:
	if game_finished:
		return

	# 1. Checa se o jogador superou seu recorde histórico durante a corrida
	if not has_beaten_previous_record and starting_best_distance > 50.0 and dist > starting_best_distance:
		has_beaten_previous_record = true
		new_best_record_achieved.emit(dist)
		if hud and hud.has_method("show_new_record_banner"):
			hud.show_new_record_banner(dist)
		if AudioManager.instance:
			AudioManager.instance.play_record_chime()

	# 2. Monitora transição de setores narrativos da corrida
	_check_sector_transition(dist)
		
	# 3. Atualiza o HUD Tático de Missão
	if hud:
		if selected_game_mode == GameMode.CAMPAIGN:
			hud.update_mission_progress(dist, target_distance)
		else:
			hud.update_mission_progress(dist, -1.0) # Modo Pesadelo Infinito
		
	# Fallback para rótulo legatário
	if distance_label:
		if selected_game_mode == GameMode.CAMPAIGN:
			var remaining: float = maxf(0.0, target_distance - dist)
			distance_label.text = "EXTRAÇÃO: %dm" % int(remaining)
			if remaining <= 100.0:
				distance_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			distance_label.text = "PESADELO: %dm" % int(dist)
			distance_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))


## Monitora a entrada nos 4 Setores Narrativos de Tensão
func _check_sector_transition(dist: float) -> void:
	var new_sec: SectorZone = current_sector
	var title: String = ""
	var sub: String = ""

	if dist < 250.0:
		new_sec = SectorZone.SECTOR_1_SHOCK
		title = "SETOR 1: O CHOQUE"
		sub = "Rodovia Deserta • Visibilidade Média"
	elif dist < 500.0:
		new_sec = SectorZone.SECTOR_2_QUARANTINE
		title = "SETOR 2: ZONA DE QUARENTENA"
		sub = "Barricadas Militares • Frequência de Corredores Alta"
	elif dist < 750.0:
		new_sec = SectorZone.SECTOR_3_HIGHWAY_HELL
		title = "SETOR 3: O INFERNO NA RODOVIA"
		sub = "Carros em Chamas • Nevoeiro Negro • Perigo Extremo"
	elif dist < 800.0:
		new_sec = SectorZone.SECTOR_4_EXTRACTION
		if selected_game_mode == GameMode.CAMPAIGN:
			title = "SETOR 4: EXTRAÇÃO FINAL"
			sub = "Sinalizadores de Resgate • Alcance a Zona Segura!"
		else:
			title = "SETOR 4: FRONTEIRA DO PESADELO"
			sub = "Aproximando-se da Zona Vermelha Infindável..."
	else:
		new_sec = SectorZone.NIGHTMARE_DEEP

	if new_sec != current_sector and new_sec != SectorZone.NONE:
		current_sector = new_sec
		_apply_sector_environment(current_sector)
		if title != "":
			sector_entered.emit(int(current_sector), title, sub)
			if hud and hud.has_method("show_sector_banner"):
				hud.show_sector_banner(title, sub)
			if AudioManager.instance:
				AudioManager.instance.play_sector_transition()
				if current_sector == SectorZone.SECTOR_2_QUARANTINE or current_sector == SectorZone.SECTOR_4_EXTRACTION:
					AudioManager.instance.play_siren_burst()


## Aplica transições climáticas e visuais nos setores (usando Depth Fog ultra-leve para Web/Mobile!)
func _apply_sector_environment(sec: SectorZone) -> void:
	if not world_environment or not world_environment.environment:
		return
	var env := world_environment.environment

	var tween := create_tween().set_parallel(true)
	match sec:
		SectorZone.SECTOR_1_SHOCK:
			tween.tween_property(env, "fog_density", 0.020, 2.0)
			tween.tween_property(env, "fog_light_color", Color("#101419"), 2.0)
		SectorZone.SECTOR_2_QUARANTINE:
			tween.tween_property(env, "fog_density", 0.026, 2.5)
			tween.tween_property(env, "fog_light_color", Color("#0c1015"), 2.5)
		SectorZone.SECTOR_3_HIGHWAY_HELL:
			# Fumaça escura avermelhada de incêndios
			tween.tween_property(env, "fog_density", 0.032, 2.5)
			tween.tween_property(env, "fog_light_color", Color(0.18, 0.07, 0.06), 2.5)
		SectorZone.SECTOR_4_EXTRACTION:
			# Resgate / Flares avermelhados
			tween.tween_property(env, "fog_density", 0.035, 2.0)
			tween.tween_property(env, "fog_light_color", Color(0.24, 0.07, 0.07), 2.0)
		SectorZone.NIGHTMARE_DEEP:
			# Breu profundo do Modo Pesadelo
			tween.tween_property(env, "fog_density", 0.042, 2.5)
			tween.tween_property(env, "fog_light_color", Color(0.06, 0.04, 0.08), 2.5)


## Processa marcos do Modo Pesadelo a cada 200m além dos 800m
func _process_nightmare_milestones(dist: float) -> void:
	if selected_game_mode != GameMode.ENDLESS_NIGHTMARE:
		return

	if dist >= 800.0 and not has_breached_nightmare:
		has_breached_nightmare = true
		if hud and hud.has_method("show_sector_banner"):
			hud.show_sector_banner(
				"★ FRONTEIRA DE EVACUAÇÃO PERDIDA ★",
				"ZONA VERMELHA INFINDÁVEL — VOCÊ ESTÁ POR CONTA PRÓPRIA"
			)
		if AudioManager.instance:
			AudioManager.instance.play_nightmare_pulse()

	if dist >= 800.0:
		var tier = int((dist - 800.0) / 200.0) + 1
		if tier > last_nightmare_tier:
			last_nightmare_tier = tier
			nightmare_tier_promoted.emit(tier, dist)
			if hud and hud.has_method("show_sector_banner"):
				hud.show_sector_banner(
					"★ PESADELO NÍVEL %d (%dm) ★" % [tier, int(dist)],
					"Velocidade +1.2m/s • Escuridão Adensada • Munição Escassa"
				)
			if spawner and spawner.has_method("apply_nightmare_tier"):
				spawner.apply_nightmare_tier(tier)
			if AudioManager.instance:
				AudioManager.instance.play_nightmare_pulse()
			_apply_nightmare_environment(tier)


func _apply_nightmare_environment(tier: int) -> void:
	if not world_environment or not world_environment.environment:
		return
	var env := world_environment.environment
	var target_density := minf(0.055, 0.038 + tier * 0.003)
	var tween := create_tween()
	tween.tween_property(env, "fog_density", target_density, 3.0)


func _on_speed_changed(speed: float) -> void:
	if speed_label:
		speed_label.text = "%.1f km/h" % (speed * 3.6)


func _on_ammo_updated(current: int, reserve: int) -> void:
	if hud:
		hud.update_ammo(current, reserve)
		
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, reserve]
		if current == 0 and reserve == 0:
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		else:
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))


func _on_player_health_changed(current: float, max_val: float) -> void:
	if hud:
		hud.update_health(current, max_val)
		
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current

	if current <= 0.0 and not game_finished:
		trigger_game_over()


func _on_zombie_killed(points: int, was_headshot: bool = false) -> void:
	total_score += int(points * score_multiplier)
	zombies_killed += 1
	if was_headshot:
		headshots_count += 1
		register_combo_action(2, "HEADSHOT")
	else:
		register_combo_action(1, "KILL")


## Bônus de pontuação e adrenalina por Near-Miss (Raspão Quase-Fatal)
func _on_player_near_miss(direction_sign: float, _threat_zombie: Zombie) -> void:
	total_score += int(50 * score_multiplier)
	register_combo_action(1, "NEAR_MISS")
	if hud and hud.has_method("show_near_miss_feedback"):
		hud.show_near_miss_feedback(direction_sign, int(50 * score_multiplier))


## Ativa vinheta rápida de Adrenaline Rush na tela
func _on_adrenaline_rush(_duration: float) -> void:
	if hud:
		hud.flash_adrenaline_vignette()
		return
		
	if not adrenaline_vignette:
		return

	var tween := create_tween()
	tween.tween_property(adrenaline_vignette, "color:a", 0.28, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(adrenaline_vignette, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Notificação de munição coletada
func _on_ammo_collected(amount: int) -> void:
	if hud:
		hud.show_ammo_collected(amount)
		return
		
	if not ammo_notify_label:
		return

	ammo_notify_label.text = "+%d BALAS (MUNIÇÃO)" % amount
	var tween := create_tween()
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.2, 1.0, 0.4, 1.0), 0.15)
	tween.tween_property(ammo_notify_label, "position:y", 20.0, 0.45)
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.2, 1.0, 0.4, 0.0), 0.35)
	tween.tween_callback(func(): ammo_notify_label.position.y = 40.0)


## Tela de Evacuação Concluída (quando chega a 0m restantes / 800m percorridos)
func _on_rescue_reached() -> void:
	if game_finished:
		return
	game_finished = true

	var run_record: Dictionary = HighScoreManager.save_run_result(
		target_distance,
		total_score + 1000,
		zombies_killed,
		headshots_count,
		run_survival_time,
		true
	)

	if hud:
		hud.show_victory_screen(int(target_distance), zombies_killed, total_score + 1000, run_record)
		return

	if not hud_root:
		return

	victory_panel = PanelContainer.new()
	victory_panel.name = "VictoryPanel"
	victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	victory_panel.custom_minimum_size = Vector2(460, 320)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.12, 0.1, 0.94)
	panel_style.border_color = Color(0.2, 0.85, 0.4, 1.0)
	panel_style.border_width_bottom = 3
	panel_style.border_width_top = 3
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	victory_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "★ EVACUAÇÃO CONCLUÍDA! ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Você alcançou o comboio de resgate com vida!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(subtitle)

	var is_new_record: bool = bool(run_record.get("is_new_distance", false))
	var record_str: String = " (★ NOVO RECORDE!)" if is_new_record else ""
	var stats := Label.new()
	stats.text = "Distância Percorrida: %dm%s\nZumbis Eliminados: %d\nPontuação Final: %d" % [int(target_distance), record_str, zombies_killed, total_score + 1000]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(stats)

	var restart_btn := Button.new()
	restart_btn.text = "JOGAR NOVAMENTE"
	restart_btn.custom_minimum_size = Vector2(220, 46)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(restart_btn)

	victory_panel.add_child(vbox)
	hud_root.add_child(victory_panel)

	# Libera cursor do mouse para clicar no botão
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Interrupção imediata do mundo e entidades, iniciando a transição de Game Over
func trigger_game_over() -> void:
	if game_finished:
		return
	game_finished = true
	is_game_over = true
	GameController.is_game_over = true
	GameManager.is_game_over = true

	# Congele a movimentação do spawner (pista e carros)
	if spawner:
		spawner.is_game_over = true
		spawner.current_speed = 0.0

	# Trava o jogador e aciona animação de morte se necessário
	if player and not player.is_dead:
		player.die()

	_show_game_over_screen()


## Tela de Game Over e Transição Cinemática
func _show_game_over_screen() -> void:
	game_finished = true
	var traveled: int = int(spawner.distance_traveled) if spawner else 0
	
	var run_record: Dictionary = HighScoreManager.save_run_result(
		float(traveled),
		total_score,
		zombies_killed,
		headshots_count,
		run_survival_time,
		false
	)

	if hud:
		hud.play_death_transition(player, traveled, zombies_killed, total_score, run_record)
		return

	if not hud_root:
		return

	game_over_panel = PanelContainer.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.custom_minimum_size = Vector2(440, 280)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.05, 0.05, 0.95)
	panel_style.border_color = Color(0.85, 0.2, 0.2, 1.0)
	panel_style.border_width_bottom = 3
	panel_style.border_width_top = 3
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	game_over_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "VOCÊ NÃO SOBREVIVEU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	vbox.add_child(title)

	var stats := Label.new()
	stats.text = "Distância Percorrida: %dm\nZumbis Eliminados: %d\nPontos: %d" % [traveled, zombies_killed, total_score]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	vbox.add_child(stats)

	var restart_btn := Button.new()
	restart_btn.text = "TENTAR NOVAMENTE"
	restart_btn.custom_minimum_size = Vector2(220, 46)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(restart_btn)

	game_over_panel.add_child(vbox)
	hud_root.add_child(game_over_panel)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Configuração programática do WorldEnvironment Cinematográfico Otimizado (60 FPS em Web / Playgama / Mobile)
func _configure_cinematic_environment() -> void:
	if not world_environment:
		world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
		
	if not world_environment:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)
		
	var env: Environment = world_environment.environment
	if not env:
		env = Environment.new()
		world_environment.environment = env
		
	# 1. Tonemapping ACES (Alto contraste cinematográfico a custo zero de GPU)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssr_enabled = false # Desativado para performance máxima em Web/Mobile
	env.ssao_enabled = false # Desativado para eliminar peso de fragment shader
	env.volumetric_fog_enabled = false # Substituído por Depth Fog exponencial ultra-rápido
	env.ambient_light_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_energy = 0.55

	if not directional_light:
		directional_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if directional_light:
		directional_light.light_color = base_dir_light_color
		directional_light.light_energy = 0.28
		directional_light.shadow_enabled = false
	
	# 2. Fog de profundidade atmosférico (custo próximo de zero, funde o horizonte com perfeição)
	env.fog_enabled = true
	env.fog_light_color = Color("#101419")
	env.fog_density = 0.020
	env.fog_sky_affect = 1.0
	
	# 3. Glow leve otimizado
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.75
	env.glow_strength = 0.95
	env.glow_bloom = 0.20
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.90
	env.glow_hdr_scale = 1.8
