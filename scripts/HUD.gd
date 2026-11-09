class_name GameHUD
extends CanvasLayer

## Dead Run - Tactical Survival HUD (Godot 4.3 - Web / Playgama)
## Gerencia a interface de sobrevivência: barra de vida tática com tremor e vinheta de dano,
## ícone médico pulsante, painel de munição 9mm com aviso de recarga, barra de progresso da missão
## e o overlay visual de Quick Time Event (QTE - Zombie Grapple).

# --- SINAIS ---
signal restart_requested

# --- REFERÊNCIAS DO TOPO (PROGRESSO DA MISSÃO) ---
@export_group("Progresso da Missão")
@export var mission_progress_bar: ProgressBar
@export var distance_label: Label
@export var runner_icon_label: Label
@export var rescue_icon_label: Label

# --- REFERÊNCIAS DE VIDA ---
@export_group("Barra de Vida")
@export var health_bar: ProgressBar
@export var health_icon: Label
@export var health_label: Label
var health_bar_initial_pos: Vector2 = Vector2.ZERO
var health_shake_tween: Tween = null
var heart_pulse_tween: Tween = null
var is_pulsing_heart: bool = false

# --- REFERÊNCIAS DE VIGOR/FÔLEGO ---
@export_group("Barra de Vigor/Fôlego")
@export var stamina_bar: ProgressBar
@export var stamina_icon: Label
@export var stamina_label: Label

# --- REFERÊNCIAS DE MUNIÇÃO ---
@export_group("Painel de Munição")
@export var ammo_label: Label
@export var ammo_icon_label: Label
@export var reload_warning_label: Label
var reload_blink_tween: Tween = null

# --- VINHETAS DE TELA ---
@export_group("Vinhetas de Efeito")
@export var damage_vignette: ColorRect
@export var adrenaline_vignette: ColorRect
@export var struggle_vignette: TextureRect
@export var ammo_notify_label: Label
var struggle_vignette_tween: Tween = null

# --- EFEITOS DE CLIMA E HEADSHOT ---
@export_group("Efeitos de Clima e Headshot")
@export var screen_rain_overlay: ColorRect
@export var headshot_vignette: TextureRect
@export var headshot_label: Label
var headshot_tween: Tween = null
var hitmarker_label: Label = null
var hitmarker_tween: Tween = null


# --- QUICK TIME EVENT (QTE OVERLAY) ---
@export_group("QTE Zombie Grapple")
@export var qte_container: Control
@export var qte_progress_bar: ProgressBar
@export var qte_circular_bar: CircularProgressBar
@export var qte_action_label: Label
@export var qte_sub_label: Label
@export var qte_counter_label: Label
var qte_blink_tween: Tween = null

# --- TELAS DE FIM DE JOGO ---
@export_group("Paineis de Finalização")
@export var victory_panel: PanelContainer
@export var game_over_panel: PanelContainer
@export var victory_stats_label: Label
@export var game_over_stats_label: Label
@export var victory_restart_button: Button
@export var game_over_restart_button: Button

# --- TRANSIÇÃO CINEMÁTICA DE MORTE ---
@export_group("Transição Cinemática de Morte")
@export var death_video_player: VideoStreamPlayer
@export var death_vignette: TextureRect
@export var death_fade_overlay: ColorRect
@export var blood_screen: ColorRect

# Configuração da missão
var target_distance: float = 800.0
var max_player_hp: float = 100.0

# --- CHECKPOINT MILITAR E METRAGEM ---
var last_checkpoint_100m: int = 0
var score_multiplier: float = 1.0
var checkpoint_label: Label = null
var checkpoint_audio: AudioStreamPlayer = null

# --- RECORDE PESSOAL E ZONAS NARRATIVAS ---
var best_record_distance: float = 0.0
var record_label: Label = null
var sector_banner_panel: PanelContainer = null
var sector_banner_title: Label = null
var sector_banner_subtitle: Label = null
var sector_banner_tween: Tween = null

# --- SELETOR DE MODO E MUTATORES ---
var mode_badge_label: Label = null
var mode_config_button: Button = null
var mode_config_panel: PanelContainer = null
var is_config_open: bool = false

# --- COMBO FLOW STATE E FEEDBACK DE CURA ---
var combo_panel: PanelContainer = null
var combo_title_label: Label = null
var combo_badge_label: Label = null
var combo_progress_bar: ProgressBar = null
var combo_anim_tween: Tween = null
var heal_vignette: ColorRect = null

# --- EVENTO DE HORDA RELÂMPAGO (SWARM SURGE) ---
var swarm_banner_panel: PanelContainer = null
var swarm_banner_label: Label = null
var swarm_tween: Tween = null


func _ready() -> void:
	_setup_nodes_if_needed()
	
	if health_bar:
		health_bar_initial_pos = health_bar.position
		
	if qte_container:
		qte_container.visible = false
		
	if victory_panel:
		victory_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = false
		
	if reload_warning_label:
		reload_warning_label.visible = false

	if death_video_player:
		death_video_player.visible = false
		death_video_player.stop()

	if death_vignette:
		death_vignette.visible = false
		death_vignette.modulate.a = 0.0

	if death_fade_overlay:
		death_fade_overlay.visible = false
		death_fade_overlay.modulate.a = 0.0

	if blood_screen:
		blood_screen.visible = false
		blood_screen.modulate.a = 0.0

	if victory_restart_button:
		victory_restart_button.pressed.connect(_on_restart_pressed)
	if game_over_restart_button:
		game_over_restart_button.pressed.connect(_on_restart_pressed)

	if not (victory_panel and victory_panel.visible) and not (game_over_panel and game_over_panel.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_nodes_if_needed() -> void:
	# Garante que as vinhetas ocupem toda a tela sem bloquear cliques
	if damage_vignette:
		damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		damage_vignette.color = Color(0.45, 0.05, 0.05, 0.0)
		
	if adrenaline_vignette:
		adrenaline_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		adrenaline_vignette.color = Color(0.12, 0.35, 0.5, 0.0)

	if death_vignette:
		death_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if death_fade_overlay:
		death_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not struggle_vignette:
		struggle_vignette = find_child("StruggleVignette", true, false) as TextureRect

	if struggle_vignette:
		struggle_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		struggle_vignette.visible = false
		struggle_vignette.modulate = Color(1.0, 0.08, 0.08, 0.0)

	if not screen_rain_overlay:
		screen_rain_overlay = find_child("ScreenRainOverlay", true, false) as ColorRect
	if screen_rain_overlay:
		screen_rain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not headshot_vignette:
		headshot_vignette = find_child("HeadshotVignette", true, false) as TextureRect
	if headshot_vignette:
		headshot_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		headshot_vignette.visible = false
		headshot_vignette.modulate.a = 0.0

	if not headshot_label:
		headshot_label = find_child("HeadshotLabel", true, false) as Label
	if headshot_label:
		headshot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		headshot_label.visible = false
		headshot_label.modulate.a = 0.0

	if not qte_circular_bar:

		qte_circular_bar = find_child("CircularProgressBar", true, false) as CircularProgressBar

	if not qte_sub_label:
		qte_sub_label = find_child("QTESubLabel", true, false) as Label

	if not death_video_player:
		var canvas = get_node_or_null("DeathCanvasLayer") as CanvasLayer
		if not canvas:
			canvas = CanvasLayer.new()
			canvas.name = "DeathCanvasLayer"
			canvas.layer = 15
			add_child(canvas)
		death_video_player = canvas.get_node_or_null("DeathVideoPlayer") as VideoStreamPlayer
		if not death_video_player:
			death_video_player = VideoStreamPlayer.new()
			death_video_player.name = "DeathVideoPlayer"
			death_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
			death_video_player.expand = true
			death_video_player.visible = false
			canvas.add_child(death_video_player)

	if not checkpoint_audio:
		checkpoint_audio = AudioStreamPlayer.new()
		checkpoint_audio.name = "CheckpointAudioPlayer"
		checkpoint_audio.stream = _create_checkpoint_beep()
		checkpoint_audio.volume_db = -6.0
		add_child(checkpoint_audio)

	if not checkpoint_label:
		checkpoint_label = Label.new()
		checkpoint_label.name = "CheckpointLabel"
		checkpoint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		checkpoint_label.position = Vector2(-220.0, 68.0)
		checkpoint_label.custom_minimum_size = Vector2(440.0, 30.0)
		checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		checkpoint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		checkpoint_label.add_theme_font_size_override("font_size", 16)
		checkpoint_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.55, 0.0))
		checkpoint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(checkpoint_label)

	# 1. Rótulo de Recorde Pessoal Histórico no topo
	if not record_label:
		record_label = Label.new()
		record_label.name = "RecordLabel"
		record_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		record_label.position = Vector2(-160.0, 36.0)
		record_label.custom_minimum_size = Vector2(320.0, 20.0)
		record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		record_label.add_theme_font_size_override("font_size", 12)
		record_label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.35, 0.9))
		record_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		record_label.text = "RECORDE: --"
		add_child(record_label)

	# 2. Badge indicativo de Modo Ativo (Campanha / Pesadelo)
	if not mode_badge_label:
		mode_badge_label = Label.new()
		mode_badge_label.name = "ModeBadgeLabel"
		mode_badge_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		mode_badge_label.position = Vector2(-220.0, 16.0)
		mode_badge_label.custom_minimum_size = Vector2(200.0, 22.0)
		mode_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mode_badge_label.add_theme_font_size_override("font_size", 11)
		mode_badge_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8, 0.85))
		mode_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mode_badge_label.text = "[CAMPANHA 800m]"
		add_child(mode_badge_label)

	# 3. Botão de configuração tática de modos e mutators (atalho [M])
	if not mode_config_button:
		mode_config_button = Button.new()
		mode_config_button.name = "ModeConfigButton"
		mode_config_button.text = "⚙️ REGRAS / MODOS [M]"
		mode_config_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		mode_config_button.position = Vector2(-190.0, 40.0)
		mode_config_button.custom_minimum_size = Vector2(170.0, 26.0)
		mode_config_button.add_theme_font_size_override("font_size", 10)
		mode_config_button.pressed.connect(toggle_mode_selection_menu)
		add_child(mode_config_button)

	# 4. Banner flutuante das 4 Zonas Narrativas (Setores de Tensão)
	if not sector_banner_panel:
		sector_banner_panel = PanelContainer.new()
		sector_banner_panel.name = "SectorBannerPanel"
		sector_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
		sector_banner_panel.position = Vector2(-250.0, 68.0)
		sector_banner_panel.custom_minimum_size = Vector2(500.0, 56.0)
		sector_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var banner_box := StyleBoxFlat.new()
		banner_box.bg_color = Color(0.06, 0.07, 0.08, 0.92)
		banner_box.border_color = Color(0.85, 0.35, 0.2, 0.95)
		banner_box.border_width_left = 3
		banner_box.border_width_right = 3
		banner_box.border_width_top = 1
		banner_box.border_width_bottom = 1
		banner_box.corner_radius_top_left = 4
		banner_box.corner_radius_top_right = 4
		banner_box.corner_radius_bottom_left = 4
		banner_box.corner_radius_bottom_right = 4
		sector_banner_panel.add_theme_stylebox_override("panel", banner_box)

		var svbox := VBoxContainer.new()
		svbox.alignment = BoxContainer.ALIGNMENT_CENTER
		svbox.add_theme_constant_override("separation", 2)

		sector_banner_title = Label.new()
		sector_banner_title.name = "SectorBannerTitle"
		sector_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sector_banner_title.add_theme_font_size_override("font_size", 17)
		sector_banner_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		svbox.add_child(sector_banner_title)

		sector_banner_subtitle = Label.new()
		sector_banner_subtitle.name = "SectorBannerSubtitle"
		sector_banner_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sector_banner_subtitle.add_theme_font_size_override("font_size", 11)
		sector_banner_subtitle.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
		svbox.add_child(sector_banner_subtitle)

		sector_banner_panel.add_child(svbox)
		sector_banner_panel.modulate.a = 0.0
		add_child(sector_banner_panel)

	# 5. Hitmarker Tático na Mira Central (X)
	if not hitmarker_label:
		hitmarker_label = Label.new()
		hitmarker_label.name = "TacticalHitmarker"
		hitmarker_label.set_anchors_preset(Control.PRESET_CENTER)
		hitmarker_label.position = Vector2(-24.0, -24.0)
		hitmarker_label.custom_minimum_size = Vector2(48.0, 48.0)
		hitmarker_label.pivot_offset = Vector2(24.0, 24.0)
		hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hitmarker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hitmarker_label.text = "✕"
		hitmarker_label.add_theme_font_size_override("font_size", 24)
		hitmarker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hitmarker_label.modulate.a = 0.0
		add_child(hitmarker_label)

	# 6. Vinheta translúcida de cura (Kit Médico)
	if not heal_vignette:
		heal_vignette = ColorRect.new()
		heal_vignette.name = "HealVignette"
		heal_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		heal_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heal_vignette.color = Color(0.0, 0.9, 0.45, 0.0)
		add_child(heal_vignette)

	# 7. Painel Tático de Combo de Adrenalina
	if not combo_panel:
		combo_panel = PanelContainer.new()
		combo_panel.name = "TacticalComboPanel"
		combo_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		combo_panel.position = Vector2(-205.0, 75.0)
		combo_panel.custom_minimum_size = Vector2(185.0, 52.0)
		combo_panel.pivot_offset = Vector2(92.0, 26.0)
		combo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		combo_panel.modulate.a = 0.0

		var c_box := StyleBoxFlat.new()
		c_box.bg_color = Color(0.05, 0.06, 0.07, 0.85)
		c_box.border_color = Color(1.0, 0.55, 0.1, 0.9)
		c_box.border_width_right = 3
		c_box.border_width_left = 1
		c_box.border_width_top = 1
		c_box.border_width_bottom = 1
		c_box.corner_radius_top_left = 4
		c_box.corner_radius_bottom_left = 4
		combo_panel.add_theme_stylebox_override("panel", c_box)

		var cvbox := VBoxContainer.new()
		cvbox.alignment = BoxContainer.ALIGNMENT_CENTER
		cvbox.add_theme_constant_override("separation", 2)

		var chbox := HBoxContainer.new()
		chbox.alignment = BoxContainer.ALIGNMENT_CENTER
		chbox.add_theme_constant_override("separation", 6)

		combo_badge_label = Label.new()
		combo_badge_label.name = "ComboBadge"
		combo_badge_label.text = "x2"
		combo_badge_label.add_theme_font_size_override("font_size", 20)
		combo_badge_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.1))
		chbox.add_child(combo_badge_label)

		combo_title_label = Label.new()
		combo_title_label.name = "ComboTitle"
		combo_title_label.text = "RAMPAGE"
		combo_title_label.add_theme_font_size_override("font_size", 13)
		combo_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		chbox.add_child(combo_title_label)

		cvbox.add_child(chbox)

		combo_progress_bar = ProgressBar.new()
		combo_progress_bar.name = "ComboProgressBar"
		combo_progress_bar.custom_minimum_size = Vector2(165.0, 4.0)
		combo_progress_bar.max_value = 1.0
		combo_progress_bar.value = 1.0
		combo_progress_bar.show_percentage = false

		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.12, 0.14, 0.16, 0.8)
		combo_progress_bar.add_theme_stylebox_override("background", bar_bg)

		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = Color(1.0, 0.6, 0.15, 1.0)
		combo_progress_bar.add_theme_stylebox_override("fill", bar_fill)

		cvbox.add_child(combo_progress_bar)
		combo_panel.add_child(cvbox)
		add_child(combo_panel)

	# 8. Painel de Alerta de Horda Relâmpago (Swarm Surge)
	if not swarm_banner_panel:
		swarm_banner_panel = PanelContainer.new()
		swarm_banner_panel.name = "SwarmSurgePanel"
		swarm_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
		swarm_banner_panel.position = Vector2(-280.0, 72.0)
		swarm_banner_panel.custom_minimum_size = Vector2(560.0, 48.0)
		swarm_banner_panel.pivot_offset = Vector2(280.0, 24.0)
		swarm_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swarm_banner_panel.modulate.a = 0.0

		var sbox := StyleBoxFlat.new()
		sbox.bg_color = Color(0.12, 0.02, 0.02, 0.92)
		sbox.border_color = Color(1.0, 0.15, 0.15, 0.95)
		sbox.border_width_left = 3
		sbox.border_width_right = 3
		sbox.border_width_top = 1
		sbox.border_width_bottom = 1
		sbox.corner_radius_top_left = 4
		sbox.corner_radius_top_right = 4
		sbox.corner_radius_bottom_left = 4
		sbox.corner_radius_bottom_right = 4
		swarm_banner_panel.add_theme_stylebox_override("panel", sbox)

		swarm_banner_label = Label.new()
		swarm_banner_label.name = "SwarmLabel"
		swarm_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swarm_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		swarm_banner_label.add_theme_font_size_override("font_size", 15)
		swarm_banner_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		swarm_banner_panel.add_child(swarm_banner_label)
		add_child(swarm_banner_panel)


## Exibe confirmação tática visual no centro da mira (Hitmarker branco para corpo, vermelho/dourado para Headshot)
func show_hitmarker(is_critical: bool = false) -> void:
	if not hitmarker_label:
		_setup_nodes_if_needed()
	if not hitmarker_label:
		return

	if hitmarker_tween and hitmarker_tween.is_valid():
		hitmarker_tween.kill()

	hitmarker_label.modulate = Color(1.0, 0.25, 0.2, 1.0) if is_critical else Color(1.0, 1.0, 1.0, 0.95)
	hitmarker_label.scale = Vector2(1.45, 1.45) if is_critical else Vector2(1.2, 1.2)

	hitmarker_tween = create_tween()
	hitmarker_tween.set_parallel(true)
	hitmarker_tween.tween_property(hitmarker_label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hitmarker_tween.tween_property(hitmarker_label, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Gera sinal sonoro militar procedural de 2 tons para feedback de checkpoint
static func _create_checkpoint_beep() -> AudioStreamWAV:
	var sample_hz: int = 22050
	var duration: float = 0.16
	var total_frames: int = int(sample_hz * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_frames * 2)

	for i in range(total_frames):
		var t: float = float(i) / float(sample_hz)
		# 2 tons marciais militares: 880Hz (La) nos primeiros 0.08s, 1174Hz (Ré) nos últimos 0.08s
		var freq: float = 880.0 if t < 0.08 else 1174.66
		var env: float = 1.0 - (t / duration)
		var sample_val: float = sin(t * TAU * freq) * env * 0.35
		var sample_int16: int = int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		byte_data.encode_s16(i * 2, sample_int16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_hz
	wav.stereo = false
	wav.data = byte_data
	return wav


# ==============================================================================
# 1. ATUALIZAÇÕES DA BARRA DE VIDA E TREMOR DE DANO
# ==============================================================================

func update_health(current: float, max_val: float) -> void:
	max_player_hp = max_val
	var prev_val = health_bar.value if health_bar else current
	
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
		
	if health_label:
		health_label.text = "%d HP" % int(maxf(0.0, current))
		
	# Mudança de cor dinâmica: azul-acinzentado (#4a5b6b) quando saudável (>35%), vermelho-escuro (#8a2323) quando crítico (<=35%)
	var hp_ratio: float = current / max_val if max_val > 0.0 else 0.0
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat if health_bar else null
	if fill_style:
		if hp_ratio <= 0.35:
			fill_style.bg_color = Color(0.541, 0.137, 0.137, 1.0) # #8a2323 (vermelho-escuro sangue)
		else:
			fill_style.bg_color = Color(0.290, 0.357, 0.420, 1.0) # #4a5b6b (azul-acinzentado sóbrio)

	if health_icon:
		if hp_ratio <= 0.35:
			health_icon.add_theme_color_override("font_color", Color(0.541, 0.137, 0.137, 1.0))
		else:
			health_icon.add_theme_color_override("font_color", Color(0.290, 0.357, 0.420, 1.0))

	# Pulsação do ícone médico quando vida estiver abaixo de 35%
	if hp_ratio <= 0.35 and hp_ratio > 0.0:
		_start_heart_pulse()
	else:
		_stop_heart_pulse()

	# Aplica tremor e flash de dano se sofreu redução de vida
	if current < prev_val and current > 0.0:
		shake_health_bar()
		flash_damage_vignette()


func shake_health_bar() -> void:
	if not health_bar:
		return
		
	if health_shake_tween and health_shake_tween.is_valid():
		health_shake_tween.kill()
		
	health_shake_tween = create_tween()
	var base_pos = health_bar_initial_pos
	# Tremor rápido horizontal de +/- 6 pixels por 0.22 segundos
	health_shake_tween.tween_property(health_bar, "position:x", base_pos.x - 6.0, 0.04)
	health_shake_tween.tween_property(health_bar, "position:x", base_pos.x + 6.0, 0.04)
	health_shake_tween.tween_property(health_bar, "position:x", base_pos.x - 3.0, 0.04)
	health_shake_tween.tween_property(health_bar, "position:x", base_pos.x + 3.0, 0.04)
	health_shake_tween.tween_property(health_bar, "position:x", base_pos.x, 0.04)


## Atualiza a barra fina de vigor/fôlego (logo abaixo da barra de vida)
func update_stamina(current: float, max_val: float, is_exhausted: bool) -> void:
	if not stamina_bar:
		stamina_bar = find_child("StaminaBar", true, false) as ProgressBar
	if not stamina_label:
		stamina_label = find_child("StaminaLabel", true, false) as Label
	if not stamina_icon:
		stamina_icon = find_child("StaminaIcon", true, false) as Label

	if stamina_bar:
		stamina_bar.max_value = max_val
		stamina_bar.value = current
		var fill_style: StyleBoxFlat = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if is_exhausted:
				fill_style.bg_color = Color(0.92, 0.35, 0.15, 1.0) # Laranja exausto
			else:
				fill_style.bg_color = Color(0.22, 0.72, 0.88, 1.0) # Ciano fôlego

	if stamina_label:
		if is_exhausted:
			stamina_label.text = "EXAUSTO!"
			stamina_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.15))
		else:
			stamina_label.text = "VIGOR"
			stamina_label.add_theme_color_override("font_color", Color(0.55, 0.68, 0.75))

	if stamina_icon:
		if is_exhausted:
			stamina_icon.add_theme_color_override("font_color", Color(0.95, 0.35, 0.15))
		else:
			stamina_icon.add_theme_color_override("font_color", Color(0.22, 0.72, 0.88, 0.8))


func flash_damage_vignette(target_alpha: float = 0.35) -> void:
	if not damage_vignette:
		return
		
	var tween := create_tween()
	tween.tween_property(damage_vignette, "color:a", target_alpha, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(damage_vignette, "color:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _start_heart_pulse() -> void:
	if is_pulsing_heart or not health_icon:
		return
	is_pulsing_heart = true
	
	if heart_pulse_tween and heart_pulse_tween.is_valid():
		heart_pulse_tween.kill()
		
	heart_pulse_tween = create_tween().set_loops()
	heart_pulse_tween.tween_property(health_icon, "scale", Vector2(1.25, 1.25), 0.35).set_trans(Tween.TRANS_SINE)
	heart_pulse_tween.tween_property(health_icon, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE)


func _stop_heart_pulse() -> void:
	if not is_pulsing_heart:
		return
	is_pulsing_heart = false
	if heart_pulse_tween and heart_pulse_tween.is_valid():
		heart_pulse_tween.kill()
	if health_icon:
		health_icon.scale = Vector2(1.0, 1.0)


# ==============================================================================
# 2. PAINEL DE MUNIÇÃO E AVISO ANIMADO DE RECARGA
# ==============================================================================

func update_ammo(current: int, reserve: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, reserve]
		if current == 0 and reserve == 0:
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		else:
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))

	# Se a munição no pente for 0, pisca aviso animado "RECARREGAR [R]"
	if current == 0:
		_start_reload_warning(reserve > 0)
	else:
		_stop_reload_warning()


func _start_reload_warning(has_reserve: bool) -> void:
	if not reload_warning_label:
		return
		
	reload_warning_label.visible = true
	if has_reserve:
		reload_warning_label.text = "RECARREGAR [R]"
		reload_warning_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.1))
	else:
		reload_warning_label.text = "SEM MUNIÇÃO!"
		reload_warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

	if reload_blink_tween and reload_blink_tween.is_valid():
		return
		
	reload_blink_tween = create_tween().set_loops()
	reload_blink_tween.tween_property(reload_warning_label, "modulate:a", 0.15, 0.28)
	reload_blink_tween.tween_property(reload_warning_label, "modulate:a", 1.0, 0.28)


func _stop_reload_warning() -> void:
	if reload_blink_tween and reload_blink_tween.is_valid():
		reload_blink_tween.kill()
		reload_blink_tween = null
	if reload_warning_label:
		reload_warning_label.visible = false
		reload_warning_label.modulate.a = 1.0


# ==============================================================================
# 3. BARRA DE PROGRESSO DA MISSÃO (TOPO)
# ==============================================================================

func update_mission_progress(distance_traveled: float, total_target: float = 800.0) -> void:
	if not checkpoint_label:
		_setup_nodes_if_needed()
	target_distance = total_target

	if total_target > 0.0:
		# Modo Campanha (800m até o resgate)
		var remaining: float = maxf(0.0, total_target - distance_traveled)
		var progress_ratio: float = clampf(distance_traveled / total_target, 0.0, 1.0)
		if mission_progress_bar:
			mission_progress_bar.max_value = 1.0
			mission_progress_bar.value = progress_ratio
		if distance_label:
			distance_label.text = "EXTRAÇÃO: %dm" % int(remaining)
			if remaining <= 120.0:
				distance_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
			else:
				distance_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	else:
		# Modo Pesadelo Infinito
		if mission_progress_bar:
			mission_progress_bar.max_value = 200.0
			mission_progress_bar.value = fmod(distance_traveled, 200.0)
		if distance_label:
			distance_label.text = "PESADELO: %dm" % int(distance_traveled)
			distance_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))

	# Verifica Checkpoint militar a cada 100 metros percorridos (100m, 200m, 300m...)
	var current_checkpoint: int = int(distance_traveled / 100.0)
	if current_checkpoint > last_checkpoint_100m:
		last_checkpoint_100m = current_checkpoint
		_trigger_checkpoint(current_checkpoint * 100)


## Define o valor do recorde pessoal histórico exibido no topo do HUD
func set_best_record_display(best_dist: float) -> void:
	best_record_distance = best_dist
	if not record_label:
		_setup_nodes_if_needed()
	if record_label:
		if best_dist > 0.0:
			record_label.text = "RECORDE: %dm" % int(best_dist)
		else:
			record_label.text = "RECORDE: --"


## Exibe banner comemorativo em tempo real quando o recorde é quebrado durante a partida
func show_new_record_banner(new_dist: float) -> void:
	best_record_distance = new_dist
	if record_label:
		record_label.text = "★ NOVO RECORDE: %dm! ★" % int(new_dist)
		record_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
		var rtw := create_tween()
		rtw.tween_property(record_label, "scale", Vector2(1.2, 1.2), 0.15)
		rtw.tween_property(record_label, "scale", Vector2(1.0, 1.0), 0.25)


## Exibe banner flutuante cinematográfico ao entrar em uma das 4 Zonas Narrativas
func show_sector_banner(title: String, subtitle: String) -> void:
	if not sector_banner_panel:
		_setup_nodes_if_needed()
	if not sector_banner_panel or not sector_banner_title:
		return

	sector_banner_title.text = title
	if sector_banner_subtitle:
		sector_banner_subtitle.text = subtitle

	if sector_banner_tween and sector_banner_tween.is_valid():
		sector_banner_tween.kill()

	sector_banner_panel.modulate.a = 0.0
	sector_banner_panel.position.y = 52.0

	sector_banner_tween = create_tween()
	sector_banner_tween.set_parallel(true)
	sector_banner_tween.tween_property(sector_banner_panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sector_banner_tween.tween_property(sector_banner_panel, "position:y", 68.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	sector_banner_tween.chain().tween_interval(2.6)

	sector_banner_tween.chain().set_parallel(true)
	sector_banner_tween.tween_property(sector_banner_panel, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sector_banner_tween.tween_property(sector_banner_panel, "position:y", 52.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Configura indicadores de modo e mutatores no HUD
func configure_mode_indicators(mode: int, no_fl: bool, all_run: bool, melee: bool) -> void:
	if not mode_badge_label:
		_setup_nodes_if_needed()
	if not mode_badge_label:
		return

	var mode_name := "[CAMPANHA 800m]" if mode == 0 else "[PESADELO INFINITO]"
	var mut_tags: Array[String] = []
	if no_fl:
		mut_tags.append("🌑 NOITE")
	if all_run:
		mut_tags.append("⚡ HORDA")
	if melee:
		mut_tags.append("🗡️ FACA")

	if mut_tags.is_empty():
		mode_badge_label.text = mode_name
	else:
		mode_badge_label.text = "%s %s" % [mode_name, " ".join(mut_tags)]


## Abre ou fecha o menu tático de seleção de modo e mutadores
func toggle_mode_selection_menu() -> void:
	_create_mode_config_panel_if_needed()
	if not mode_config_panel:
		return

	is_config_open = not is_config_open
	mode_config_panel.visible = is_config_open

	if is_config_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var gc = GameController.instance
		if not gc or (not gc.game_finished and not GameController.is_game_over):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_M:
			toggle_mode_selection_menu()
			get_viewport().set_input_as_handled()


## Constrói programaticamente o painel de configuração rápida de modo e mutadores
func _create_mode_config_panel_if_needed() -> void:
	if mode_config_panel:
		return

	mode_config_panel = PanelContainer.new()
	mode_config_panel.name = "ModeConfigPanel"
	mode_config_panel.set_anchors_preset(Control.PRESET_CENTER)
	mode_config_panel.custom_minimum_size = Vector2(440.0, 320.0)

	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	pstyle.border_color = Color(0.35, 0.55, 0.75, 0.9)
	pstyle.border_width_left = 2
	pstyle.border_width_right = 2
	pstyle.border_width_top = 2
	pstyle.border_width_bottom = 2
	pstyle.corner_radius_top_left = 6
	pstyle.corner_radius_top_right = 6
	pstyle.corner_radius_bottom_left = 6
	pstyle.corner_radius_bottom_right = 6
	mode_config_panel.add_theme_stylebox_override("panel", pstyle)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var mtitle := Label.new()
	mtitle.text = "⚙️ REGRAS DA CORRIDA E MUTADORES"
	mtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mtitle.add_theme_font_size_override("font_size", 18)
	mtitle.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(mtitle)

	var mdesc := Label.new()
	mdesc.text = "Alterne o modo de jogo ou ative desafios extremos:"
	mdesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mdesc.add_theme_font_size_override("font_size", 12)
	mdesc.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	vbox.add_child(mdesc)

	# Botão de alternância de modo
	var mode_btn := Button.new()
	mode_btn.custom_minimum_size = Vector2(340, 34)
	mode_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var is_nightmare: bool = GameController.selected_game_mode == GameController.GameMode.ENDLESS_NIGHTMARE
	mode_btn.text = "MODO: PESADELO INFINITO" if is_nightmare else "MODO: CAMPANHA DE RESGATE (800m)"
	mode_btn.pressed.connect(func():
		if GameController.selected_game_mode == GameController.GameMode.CAMPAIGN:
			GameController.selected_game_mode = GameController.GameMode.ENDLESS_NIGHTMARE
			mode_btn.text = "MODO: PESADELO INFINITO"
		else:
			GameController.selected_game_mode = GameController.GameMode.CAMPAIGN
			mode_btn.text = "MODO: CAMPANHA DE RESGATE (800m)"
		configure_mode_indicators(int(GameController.selected_game_mode), GameController.mutator_no_flashlight, GameController.mutator_all_runners, GameController.mutator_melee_only)
	)
	vbox.add_child(mode_btn)

	# Mutators Checkboxes
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cbox.add_theme_constant_override("separation", 6)

	var chk_fl := CheckBox.new()
	chk_fl.text = "🌑 Noite Sem Lanterna (Escuridão e relâmpagos)"
	chk_fl.button_pressed = GameController.mutator_no_flashlight
	chk_fl.toggled.connect(func(val):
		GameController.mutator_no_flashlight = val
		configure_mode_indicators(int(GameController.selected_game_mode), GameController.mutator_no_flashlight, GameController.mutator_all_runners, GameController.mutator_melee_only)
	)
	cbox.add_child(chk_fl)

	var chk_run := CheckBox.new()
	chk_run.text = "⚡ Horda Voraz (100% zumbis corredores rápidos)"
	chk_run.button_pressed = GameController.mutator_all_runners
	chk_run.toggled.connect(func(val):
		GameController.mutator_all_runners = val
		configure_mode_indicators(int(GameController.selected_game_mode), GameController.mutator_no_flashlight, GameController.mutator_all_runners, GameController.mutator_melee_only)
	)
	cbox.add_child(chk_run)

	var chk_knife := CheckBox.new()
	chk_knife.text = "🗡️ Guerra de Trincheira (Faca Tática exclusiva)"
	chk_knife.button_pressed = GameController.mutator_melee_only
	chk_knife.toggled.connect(func(val):
		GameController.mutator_melee_only = val
		configure_mode_indicators(int(GameController.selected_game_mode), GameController.mutator_no_flashlight, GameController.mutator_all_runners, GameController.mutator_melee_only)
	)
	cbox.add_child(chk_knife)

	vbox.add_child(cbox)

	var h_actions := HBoxContainer.new()
	h_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	h_actions.add_theme_constant_override("separation", 12)

	var apply_restart_btn := Button.new()
	apply_restart_btn.text = "APLICAR E REINICIAR"
	apply_restart_btn.custom_minimum_size = Vector2(170, 34)
	apply_restart_btn.pressed.connect(func():
		get_tree().reload_current_scene()
	)
	h_actions.add_child(apply_restart_btn)

	var close_btn := Button.new()
	close_btn.text = "FECHAR"
	close_btn.custom_minimum_size = Vector2(110, 34)
	close_btn.pressed.connect(toggle_mode_selection_menu)
	h_actions.add_child(close_btn)

	vbox.add_child(h_actions)
	mode_config_panel.add_child(vbox)
	mode_config_panel.visible = false
	add_child(mode_config_panel)


## Aciona feedback militar e bônus de pontuação a cada 100m percorridos
func _trigger_checkpoint(checkpoint_dist: int) -> void:
	score_multiplier += 0.25

	# Sincroniza multiplicador com o GameController
	if is_inside_tree():
		var tree := get_tree()
		if tree:
			var gc = tree.get_first_node_in_group("game_controller")
			if gc and "score_multiplier" in gc:
				gc.score_multiplier = score_multiplier

	# Som sutil militar de checkpoint
	if checkpoint_audio and is_inside_tree():
		checkpoint_audio.play()

	# Banner visual sutil na tela
	if checkpoint_label:
		checkpoint_label.text = "CHECKPOINT %dm  |  MULTIPLICADOR: %.2fx" % [checkpoint_dist, score_multiplier]
		if is_inside_tree():
			var tw := create_tween()
			tw.tween_property(checkpoint_label, "theme_override_colors/font_color", Color(0.35, 0.95, 0.55, 0.95), 0.15)
			tw.tween_interval(1.8)
			tw.tween_property(checkpoint_label, "theme_override_colors/font_color", Color(0.35, 0.95, 0.55, 0.0), 0.45)
		else:
			checkpoint_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55, 0.95))


# ==============================================================================
# 4. QTE CINEMÁTICO DE AGARRÃO E FACA TÁTICA (GRAPPLE CUTSCENE)
# ==============================================================================

## Exibe o QTE cinemático de agarrão com indicador de ação estilizado e barra circular
func show_grapple_qte(duration_real: float = 1.6) -> void:
	if not qte_container:
		return

	_setup_nodes_if_needed()
	qte_container.visible = true

	if qte_action_label:
		qte_action_label.text = "[F] CRAVAR FACA TÁTICA"
		qte_action_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99))
		qte_action_label.scale = Vector2(1.0, 1.0)

	if qte_sub_label:
		qte_sub_label.visible = true
		qte_sub_label.text = "[M1] OU BOTÃO ESQUERDO DO MOUSE"
		qte_sub_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))

	if qte_circular_bar:
		qte_circular_bar.visible = true
		qte_circular_bar.center_text = "F"
		qte_circular_bar.set_progress(duration_real, duration_real)

	if qte_progress_bar:
		qte_progress_bar.visible = false

	if qte_counter_label:
		qte_counter_label.visible = true
		qte_counter_label.text = "TEMPO: %.1fs" % duration_real
		qte_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))

	start_struggle_vignette()

	if qte_blink_tween and qte_blink_tween.is_valid():
		qte_blink_tween.kill()

	# Pulso suave e dinâmico de urgência
	qte_blink_tween = create_tween().set_loops()
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.06, 1.06), 0.16).set_trans(Tween.TRANS_SINE)
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_SINE)


func update_grapple_timer(time_left_real: float, total_duration: float = 1.6) -> void:
	if not qte_container or not qte_container.visible:
		return
	var clamped_time: float = maxf(0.0, time_left_real)
	if qte_circular_bar:
		qte_circular_bar.set_progress(clamped_time, total_duration)
	elif qte_progress_bar:
		qte_progress_bar.visible = true
		qte_progress_bar.max_value = total_duration
		qte_progress_bar.value = clamped_time

	if qte_counter_label:
		qte_counter_label.visible = true
		if clamped_time <= 0.4:
			qte_counter_label.text = "TEMPO: %.1fs (CRÍTICO!)" % clamped_time
			qte_counter_label.add_theme_color_override("font_color", Color(1.0, 0.22, 0.18))
		else:
			qte_counter_label.text = "TEMPO: %.1fs" % clamped_time
			qte_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))


func hide_grapple_qte() -> void:
	if qte_blink_tween and qte_blink_tween.is_valid():
		qte_blink_tween.kill()
		qte_blink_tween = null
	if qte_container:
		qte_container.visible = false
	if qte_action_label:
		qte_action_label.scale = Vector2.ONE
	if qte_sub_label:
		qte_sub_label.visible = false
	if qte_counter_label:
		qte_counter_label.visible = false
	stop_struggle_vignette()



## Ativa a vinheta vermelha pulsante nas bordas da tela durante o agarrão corporal
func start_struggle_vignette() -> void:
	if not struggle_vignette:
		_setup_nodes_if_needed()
	if not struggle_vignette:
		return
	struggle_vignette.visible = true
	struggle_vignette.modulate = Color(1.0, 0.08, 0.08, 0.3)
	if struggle_vignette_tween and struggle_vignette_tween.is_valid():
		struggle_vignette_tween.kill()
	struggle_vignette_tween = create_tween().set_loops()
	struggle_vignette_tween.tween_property(struggle_vignette, "modulate:a", 0.72, 0.20).set_trans(Tween.TRANS_SINE)
	struggle_vignette_tween.tween_property(struggle_vignette, "modulate:a", 0.28, 0.20).set_trans(Tween.TRANS_SINE)


func stop_struggle_vignette() -> void:
	if struggle_vignette_tween and struggle_vignette_tween.is_valid():
		struggle_vignette_tween.kill()
		struggle_vignette_tween = null
	if struggle_vignette and struggle_vignette.visible:
		var fade := create_tween()
		fade.tween_property(struggle_vignette, "modulate:a", 0.0, 0.16)
		fade.chain().tween_callback(func():
			if is_instance_valid(struggle_vignette):
				struggle_vignette.visible = false
		)


## Respinga sangue instantaneamente na lente da câmera ao cravar a faca
func show_blood_lens_splatter() -> void:
	if damage_vignette:
		damage_vignette.color = Color(0.72, 0.02, 0.02, 0.75)
		var tw := create_tween()
		tw.tween_property(damage_vignette, "color:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ==============================================================================
# 5. AVISO DE GOLPE DE EMERGÊNCIA (FACA / TECLA [F])
# ==============================================================================

## Exibe na tela um aviso minimalista e centralizado com fonte fina: "[F] GOLPE DE EMERGÊNCIA"
func show_emergency_prompt(duration_real: float = 0.8) -> void:
	if not qte_container:
		return

	qte_container.visible = true
	if qte_action_label:
		qte_action_label.text = "[F] GOLPE DE EMERGÊNCIA"
		qte_action_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
		qte_action_label.scale = Vector2(1.0, 1.0)

	if qte_progress_bar:
		qte_progress_bar.visible = true
		qte_progress_bar.max_value = duration_real
		qte_progress_bar.value = duration_real

	if qte_counter_label:
		qte_counter_label.visible = false

	if qte_blink_tween and qte_blink_tween.is_valid():
		qte_blink_tween.kill()

	# Pulso sutil e refinado de atenção
	qte_blink_tween = create_tween().set_loops()
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.06, 1.06), 0.18).set_trans(Tween.TRANS_SINE)
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE)


func update_emergency_timer(time_left_real: float, total_duration: float = 0.8) -> void:
	if not qte_container or not qte_container.visible:
		return
	if qte_progress_bar:
		qte_progress_bar.max_value = total_duration
		qte_progress_bar.value = maxf(0.0, time_left_real)


func hide_emergency_prompt() -> void:
	if qte_blink_tween and qte_blink_tween.is_valid():
		qte_blink_tween.kill()
		qte_blink_tween = null
	if qte_container:
		qte_container.visible = false
	if qte_action_label:
		qte_action_label.scale = Vector2.ONE


func show_qte_overlay(duration_real: float, _required_presses: int = 1) -> void:
	show_emergency_prompt(duration_real)


func update_qte_progress(_current_presses: int, _required_presses: int, time_remaining_real: float) -> void:
	update_emergency_timer(time_remaining_real)


func hide_qte_overlay(success: bool) -> void:
	if success:
		if qte_action_label:
			qte_action_label.text = "ELIMINADO!"
			qte_action_label.add_theme_color_override("font_color", Color(0.25, 0.9, 0.4))
		var t = create_tween()
		t.tween_interval(0.2)
		t.tween_callback(hide_emergency_prompt)
	else:
		hide_emergency_prompt()


## Exibe o indicador de perigo crítico do sistema Anti-Camper: "[F] APUNHALAR AGORA!" ou "[ESPAÇO] EMPURRÃO DE EMERGÊNCIA"
func show_ambush_prompt(action_text: String, duration_real: float = 0.9) -> void:
	if not qte_container:
		return

	qte_container.visible = true
	if qte_action_label:
		qte_action_label.text = action_text
		qte_action_label.add_theme_color_override("font_color", Color(1.0, 0.22, 0.18))
		qte_action_label.scale = Vector2(1.0, 1.0)

	if qte_progress_bar:
		qte_progress_bar.visible = true
		qte_progress_bar.max_value = duration_real
		qte_progress_bar.value = duration_real

	if qte_counter_label:
		qte_counter_label.visible = false

	if qte_blink_tween and qte_blink_tween.is_valid():
		qte_blink_tween.kill()

	# Pulso intenso e agressivo de alerta crítico
	qte_blink_tween = create_tween().set_loops()
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.16, 1.16), 0.11).set_trans(Tween.TRANS_SINE)
	qte_blink_tween.tween_property(qte_action_label, "scale", Vector2(1.0, 1.0), 0.11).set_trans(Tween.TRANS_SINE)


func update_ambush_timer(time_left_real: float, total_duration: float = 0.9) -> void:
	if not qte_container or not qte_container.visible:
		return
	if qte_progress_bar:
		qte_progress_bar.max_value = total_duration
		qte_progress_bar.value = maxf(0.0, time_left_real)


func hide_ambush_prompt() -> void:
	hide_emergency_prompt()


# ==============================================================================
# 5. VINHETAS DE ADRENALINA E NOTIFICAÇÃO DE MUNIÇÃO
# ==============================================================================

func flash_adrenaline_vignette() -> void:
	if not adrenaline_vignette:
		return
		
	var tween := create_tween()
	tween.tween_property(adrenaline_vignette, "color:a", 0.32, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(adrenaline_vignette, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func show_ammo_collected(amount: int) -> void:
	if not ammo_notify_label:
		return
		
	ammo_notify_label.text = "+%d MUNIÇÃO (9mm)" % amount
	var tween := create_tween()
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.25, 1.0, 0.45, 1.0), 0.15)
	tween.tween_property(ammo_notify_label, "position:y", 30.0, 0.4)
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.25, 1.0, 0.45, 0.0), 0.35)
	tween.tween_callback(func(): ammo_notify_label.position.y = 50.0)


## Feedback de restauração de vida por Kit Médico
func flash_heal_feedback(amount: int) -> void:
	if not heal_vignette:
		_setup_nodes_if_needed()
	if heal_vignette:
		var tw := create_tween()
		tw.tween_property(heal_vignette, "color:a", 0.24, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(heal_vignette, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	if ammo_notify_label:
		ammo_notify_label.text = "💚 +%d HP (KIT MÉDICO MILITAR)" % amount
		var tween := create_tween()
		tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.2, 1.0, 0.5, 1.0), 0.15)
		tween.tween_property(ammo_notify_label, "position:y", 30.0, 0.4)
		tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(0.2, 1.0, 0.5, 0.0), 0.35)
		tween.tween_callback(func(): ammo_notify_label.position.y = 50.0)


## Feedback de adrenalina máxima coletada
func flash_adrenaline_pickup(_duration: float = 4.5) -> void:
	flash_adrenaline_vignette()
	if ammo_notify_label:
		ammo_notify_label.text = "⚡ ADRENALINA MÁXIMA (FÔLEGO INFINITO +15% VELOCIDADE)"
		var tween := create_tween()
		tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(1.0, 0.82, 0.15, 1.0), 0.15)
		tween.tween_property(ammo_notify_label, "position:y", 30.0, 0.5)
		tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(1.0, 0.82, 0.15, 0.0), 0.35)
		tween.tween_callback(func(): ammo_notify_label.position.y = 50.0)


# ==============================================================================
# 5.1 PAINEL DINÂMICO DE COMBO MULTIPLIER (FLOW STATE)
# ==============================================================================

func update_combo_display(multiplier: int, _count: int, timer_ratio: float, title: String) -> void:
	if not combo_panel:
		_setup_nodes_if_needed()
	if multiplier < 2:
		hide_combo_display()
		return

	combo_panel.visible = true
	combo_panel.modulate.a = 1.0
	if combo_badge_label:
		combo_badge_label.text = "x%d" % multiplier
	if combo_title_label:
		combo_title_label.text = title

	# Cores vibrantes por nível de combo
	var col := Color(1.0, 0.6, 0.15) # RAMPAGE (laranja)
	if multiplier == 3:
		col = Color(1.0, 0.85, 0.2) # UNSTOPPABLE (ouro)
	elif multiplier == 4:
		col = Color(0.2, 0.9, 1.0) # RELENTLESS (ciano neon)
	elif multiplier >= 5:
		col = Color(1.0, 0.2, 0.25) # GODLIKE (vermelho vivo)

	if combo_badge_label:
		combo_badge_label.add_theme_color_override("font_color", col)
	if combo_title_label:
		combo_title_label.add_theme_color_override("font_color", col)
	if combo_progress_bar:
		combo_progress_bar.value = timer_ratio
		var fill = combo_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = col


func update_combo_timer(ratio: float) -> void:
	if combo_progress_bar and combo_panel and combo_panel.visible:
		combo_progress_bar.value = ratio


func trigger_combo_burst(multiplier: int, title: String) -> void:
	if not combo_panel:
		_setup_nodes_if_needed()
	update_combo_display(multiplier, 0, 1.0, title)
	
	if combo_anim_tween and combo_anim_tween.is_valid():
		combo_anim_tween.kill()

	combo_anim_tween = create_tween()
	combo_panel.scale = Vector2(1.35, 1.35)
	combo_anim_tween.tween_property(combo_panel, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_combo_display() -> void:
	if combo_panel and combo_panel.visible:
		var tw := create_tween()
		tw.tween_property(combo_panel, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			if combo_panel:
				combo_panel.visible = false
		)


# ==============================================================================
# 5.2 ALERTAS DE ENXAME (HORDA RELÂMPAGO) E PISTA COM ÓLEO
# ==============================================================================

func show_swarm_surge_alert(_duration: float = 6.0) -> void:
	if not swarm_banner_panel:
		_setup_nodes_if_needed()
	if not swarm_banner_panel or not swarm_banner_label:
		return

	if swarm_tween and swarm_tween.is_valid():
		swarm_tween.kill()

	swarm_banner_panel.visible = true
	swarm_banner_label.text = "⚠️ ALERTA DE QUARENTENA: ENXAME DE ZUMBIS SE APROXIMANDO!"
	swarm_banner_label.add_theme_color_override("font_color", Color(1.0, 0.22, 0.18))

	var sbox = swarm_banner_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sbox:
		sbox.bg_color = Color(0.15, 0.02, 0.02, 0.92)
		sbox.border_color = Color(1.0, 0.18, 0.15, 0.95)

	swarm_banner_panel.scale = Vector2(1.2, 1.2)
	swarm_tween = create_tween()
	swarm_tween.tween_property(swarm_banner_panel, "modulate:a", 1.0, 0.15)
	swarm_tween.parallel().tween_property(swarm_banner_panel, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK)
	swarm_tween.tween_interval(3.2)
	swarm_tween.tween_property(swarm_banner_panel, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD)
	swarm_tween.tween_callback(func():
		if swarm_banner_panel:
			swarm_banner_panel.visible = false
	)


func show_swarm_survived_feedback(bonus_points: int) -> void:
	if not swarm_banner_panel:
		_setup_nodes_if_needed()
	if not swarm_banner_panel or not swarm_banner_label:
		return

	if swarm_tween and swarm_tween.is_valid():
		swarm_tween.kill()

	swarm_banner_panel.visible = true
	swarm_banner_label.text = "⚡ ENXAME SUPERADO COM SUCESSO! (+%d PTS / COMBO +2)" % bonus_points
	swarm_banner_label.add_theme_color_override("font_color", Color(0.25, 1.0, 0.5))

	var sbox = swarm_banner_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sbox:
		sbox.bg_color = Color(0.02, 0.12, 0.05, 0.92)
		sbox.border_color = Color(0.2, 1.0, 0.45, 0.95)

	swarm_banner_panel.scale = Vector2(1.15, 1.15)
	swarm_tween = create_tween()
	swarm_tween.tween_property(swarm_banner_panel, "modulate:a", 1.0, 0.12)
	swarm_tween.parallel().tween_property(swarm_banner_panel, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK)
	swarm_tween.tween_interval(2.5)
	swarm_tween.tween_property(swarm_banner_panel, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD)
	swarm_tween.tween_callback(func():
		if swarm_banner_panel:
			swarm_banner_panel.visible = false
	)


func flash_oil_slip_alert() -> void:
	if not ammo_notify_label:
		return
	ammo_notify_label.text = "⚠️ DERRAPAGEM! PISTA COM ÓLEO DIESEL"
	var tween := create_tween()
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(1.0, 0.65, 0.1, 1.0), 0.12)
	tween.tween_property(ammo_notify_label, "position:y", 30.0, 0.45)
	tween.tween_property(ammo_notify_label, "theme_override_colors/font_color", Color(1.0, 0.65, 0.1, 0.0), 0.30)
	tween.tween_callback(func(): ammo_notify_label.position.y = 50.0)


## Feedback visual de tiro crítico na cabeça (Headshot): vinheta radial e texto flutuante
func show_headshot_feedback(bonus_points: int = 100) -> void:
	if AudioManager.instance:
		AudioManager.instance.play_headshot_ding()

	if not headshot_vignette:
		headshot_vignette = find_child("HeadshotVignette", true, false) as TextureRect
	if not headshot_label:
		headshot_label = find_child("HeadshotLabel", true, false) as Label

	# 1. Vinheta radial rápida dourada
	if headshot_vignette:
		headshot_vignette.visible = true
		headshot_vignette.modulate.a = 0.0
		var vig_tw := create_tween()
		vig_tw.tween_property(headshot_vignette, "modulate:a", 0.55, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		vig_tw.tween_property(headshot_vignette, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		vig_tw.tween_callback(func():
			if headshot_vignette:
				headshot_vignette.visible = false
		)

	# 2. Texto flutuante "+HEADSHOT" com pontuação dobrada
	if headshot_label:
		if headshot_tween and headshot_tween.is_valid():
			headshot_tween.kill()

		headshot_label.visible = true
		headshot_label.modulate.a = 1.0
		headshot_label.scale = Vector2(1.4, 1.4)
		headshot_label.position.y = -24.0
		headshot_label.text = "🎯 +HEADSHOT (+%d)" % (bonus_points * 2)

		headshot_tween = create_tween()
		# Pop in rítmico
		headshot_tween.tween_property(headshot_label, "scale", Vector2(1.0, 1.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Flutua suavemente para cima
		headshot_tween.parallel().tween_property(headshot_label, "position:y", -48.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Fade out final
		headshot_tween.tween_property(headshot_label, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		headshot_tween.tween_callback(func():
			if headshot_label:
				headshot_label.visible = false
				headshot_label.position.y = -24.0
		)


## Feedback cinemático de Near-Miss (Raspão Quase-Fatal): pulso elétrico de adrenalina e indicador tático
func show_near_miss_feedback(direction_sign: float, bonus_points: int = 50) -> void:
	# 1. Pulso elétrico ciano na vinheta de adrenalina
	if adrenaline_vignette:
		var vig_tw := create_tween()
		adrenaline_vignette.color = Color(0.18, 0.78, 1.0, 0.45)
		vig_tw.tween_property(adrenaline_vignette, "color:a", 0.42, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		vig_tw.tween_property(adrenaline_vignette, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 2. Pop-up dinâmico de texto com seta direcional e tom elétrico
	if not headshot_label:
		headshot_label = find_child("HeadshotLabel", true, false) as Label

	if headshot_label:
		if headshot_tween and headshot_tween.is_valid():
			headshot_tween.kill()

		headshot_label.visible = true
		headshot_label.modulate = Color(0.35, 0.92, 1.0, 1.0)
		headshot_label.scale = Vector2(1.3, 1.3)
		headshot_label.position.y = -20.0

		var arrow_str: String = "◄ " if direction_sign < 0.0 else "► "
		headshot_label.text = "⚡ %sRASPÃO QUASE-FATAL! (+%d)" % [arrow_str, bonus_points]

		headshot_tween = create_tween()
		headshot_tween.tween_property(headshot_label, "scale", Vector2(1.0, 1.0), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		headshot_tween.parallel().tween_property(headshot_label, "position:y", -45.0, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		headshot_tween.tween_property(headshot_label, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		headshot_tween.tween_callback(func():
			if headshot_label:
				headshot_label.visible = false
				headshot_label.position.y = -24.0
				headshot_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		)



# ==============================================================================
# 6. TELAS FINAIS DE EVACUAÇÃO CONCLUÍDA E TRANSIÇÃO DE GAME OVER
# ==============================================================================

## Executa a transição cinemática de derrota (Cenário A: Vídeo ou Cenário B: Câmera 3D + Vinheta Radial e Fade Escuro)
func play_death_transition(player: Player, distance_traveled: int, zombies_killed: int, score: int, run_record: Dictionary = {}) -> void:
	# Oculta overlays de ação para limpar a visão do jogador
	if qte_container:
		qte_container.visible = false
	if reload_warning_label:
		reload_warning_label.visible = false
	if sector_banner_panel:
		sector_banner_panel.visible = false

	# Cenário A: Vídeo de Ataque / Jumpscare ("assets/Videos/death_attack.ogv" ou ".webm")
	var video_path := _find_death_video_path()
	if video_path != "":
		var stream = load(video_path) as VideoStream
		if stream and death_video_player:
			death_video_player.stream = stream
			death_video_player.visible = true
			death_video_player.play()
			death_video_player.finished.connect(func():
				death_video_player.visible = false
				show_game_over_screen(distance_traveled, zombies_killed, score, run_record)
			, CONNECT_ONE_SHOT)
			return

	# Cenário B: Fallback via Câmera 3D (queda de 1.6m para 0.25m e roll 65 graus) + Vinheta radial suave e fade para preto/cinza (#0e1012)
	if player and player.has_method("play_camera_death_fall"):
		player.play_camera_death_fall()

	var tween := create_tween().set_parallel(true)
	if death_vignette:
		death_vignette.visible = true
		death_vignette.modulate.a = 0.0
		tween.tween_property(death_vignette, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if death_fade_overlay:
		death_fade_overlay.visible = true
		death_fade_overlay.modulate.a = 0.0
		tween.tween_property(death_fade_overlay, "modulate:a", 0.90, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	elif blood_screen:
		blood_screen.visible = true
		blood_screen.color = Color(0.055, 0.063, 0.071, 0.0)
		tween.tween_property(blood_screen, "color:a", 0.88, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	var timer_tween := create_tween()
	timer_tween.tween_interval(0.42)
	timer_tween.tween_callback(func():
		show_game_over_screen(distance_traveled, zombies_killed, score, run_record)
	)


func _find_death_video_path() -> String:
	var candidates: Array[String] = [
		"res://assets/Videos/death_attack.ogv",
		"res://assets/Videos/death_attack.webm",
		"assets/Videos/death_attack.ogv",
		"assets/Videos/death_attack.webm"
	]
	for p in candidates:
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""


func show_victory_screen(distance_traveled: int, zombies_killed: int, score: int, run_record: Dictionary = {}) -> void:
	if victory_panel:
		var prev_best: int = int(run_record.get("previous_distance", best_record_distance))
		var is_new: bool = bool(run_record.get("is_new_distance", false))
		var new_rec_str: String = "★ NOVO RECORDE PESSOAL! ★\n" if is_new else ""
		var headshots: int = int(run_record.get("current_headshots", 0))

		if victory_stats_label:
			victory_stats_label.text = "%sDistância: %dm (Recorde: %dm)\nZumbis Eliminados: %d (Headshots: %d)\nPontuação Final: %d" % [
				new_rec_str,
				distance_traveled,
				prev_best if not is_new else distance_traveled,
				zombies_killed,
				headshots,
				score
			]
		_setup_end_panel_mode_controls(victory_panel)
		victory_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_game_over_screen(distance_traveled: int, zombies_killed: int, score: int, run_record: Dictionary = {}) -> void:
	if game_over_panel:
		var title_label := game_over_panel.find_child("GameOverTitle", true, false) as Label
		if title_label:
			title_label.text = "VOCÊ NÃO SOBREVIVEU"
			title_label.add_theme_color_override("font_color", Color(0.91, 0.92, 0.93))

		var prev_best: int = int(run_record.get("previous_distance", best_record_distance))
		var is_new: bool = bool(run_record.get("is_new_distance", false))
		var new_rec_str: String = "★ NOVO RECORDE PESSOAL! ★\n" if is_new else ""
		var headshots: int = int(run_record.get("current_headshots", 0))

		if game_over_stats_label:
			game_over_stats_label.text = "%sDistância: %dm (Recorde: %dm)\nZumbis Eliminados: %d (Headshots: %d)\nPontuação Final: %d" % [
				new_rec_str,
				distance_traveled,
				prev_best if not is_new else distance_traveled,
				zombies_killed,
				headshots,
				score
			]
			if is_new:
				game_over_stats_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
			else:
				game_over_stats_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))

		_setup_end_panel_mode_controls(game_over_panel)
		game_over_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Constrói os controles de seleção de Modo e Mutators dentro do painel final antes do botão reiniciar
func _setup_end_panel_mode_controls(panel: PanelContainer) -> void:
	if not panel:
		return
	var vbox := panel.get_node_or_null("VBox") as VBoxContainer
	if not vbox:
		return

	var existing_controls := vbox.get_node_or_null("EndModeControls") as VBoxContainer
	if existing_controls:
		existing_controls.queue_free()

	var mode_container := VBoxContainer.new()
	mode_container.name = "EndModeControls"
	mode_container.add_theme_constant_override("separation", 6)
	mode_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# Botão de alternar Modo de Jogo para a próxima tentativa
	var mode_toggle := Button.new()
	mode_toggle.custom_minimum_size = Vector2(280, 30)
	mode_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var is_nightmare: bool = GameController.selected_game_mode == GameController.GameMode.ENDLESS_NIGHTMARE
	mode_toggle.text = "PRÓXIMO: PESADELO INFINITO" if is_nightmare else "PRÓXIMO: CAMPANHA (800m)"
	mode_toggle.pressed.connect(func():
		if GameController.selected_game_mode == GameController.GameMode.CAMPAIGN:
			GameController.selected_game_mode = GameController.GameMode.ENDLESS_NIGHTMARE
			mode_toggle.text = "PRÓXIMO: PESADELO INFINITO"
		else:
			GameController.selected_game_mode = GameController.GameMode.CAMPAIGN
			mode_toggle.text = "PRÓXIMO: CAMPANHA (800m)"
	)
	mode_container.add_child(mode_toggle)

	# Mutators rápidos
	var hbox_muts := HBoxContainer.new()
	hbox_muts.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_muts.add_theme_constant_override("separation", 8)

	var chk_fl := CheckBox.new()
	chk_fl.text = "🌑 Sem Lanterna"
	chk_fl.button_pressed = GameController.mutator_no_flashlight
	chk_fl.toggled.connect(func(v): GameController.mutator_no_flashlight = v)
	hbox_muts.add_child(chk_fl)

	var chk_run := CheckBox.new()
	chk_run.text = "⚡ Horda Voraz"
	chk_run.button_pressed = GameController.mutator_all_runners
	chk_run.toggled.connect(func(v): GameController.mutator_all_runners = v)
	hbox_muts.add_child(chk_run)

	var chk_knife := CheckBox.new()
	chk_knife.text = "🗡️ Faca Only"
	chk_knife.button_pressed = GameController.mutator_melee_only
	chk_knife.toggled.connect(func(v: bool): GameController.mutator_melee_only = v)
	hbox_muts.add_child(chk_knife)

	mode_container.add_child(hbox_muts)

	# Botão de retorno ao Menu Principal
	var btn_main_menu := Button.new()
	btn_main_menu.text = "MENU PRINCIPAL"
	btn_main_menu.custom_minimum_size = Vector2(280, 32)
	btn_main_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_main_menu.pressed.connect(func():
		AudioManager.play_ui_click()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	mode_container.add_child(btn_main_menu)

	# Insere antes do botão de reiniciar (penúltimo elemento)
	var child_count := vbox.get_child_count()
	vbox.add_child(mode_container)
	if child_count > 0:
		vbox.move_child(mode_container, child_count - 1)


func _on_restart_pressed() -> void:
	restart_requested.emit()
	get_tree().reload_current_scene()
