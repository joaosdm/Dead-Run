class_name MainMenu
extends Control

## Dead Run - Main Menu & Cinematic Horror Preloader (Godot 4.3)
## Tela inicial imersiva com estética de suspense, telemetria de recordes,
## seleção de modos/mutadores e tela de pré-carregamento assíncrono (Pre-warming)
## que compila shaders e carrega malhas na GPU antes do início para evitar travamentos.

@export_group("Cena Destino")
@export_file("*.tscn") var gameplay_scene_path: String = "res://scenes/Main.tscn"

# Referências de Nós 3D do Fundo
@onready var bg_camera: Camera3D = $World3D/Camera3D
@onready var thunder_light: DirectionalLight3D = $World3D/ThunderLight
@onready var hazard_light: OmniLight3D = $World3D/WreckedCarHolder/HazardLight

# Referências de UI - Painel Principal
@onready var main_panel: Control = $UI/MainPanel
@onready var title_label: Label = $UI/MainPanel/Header/TitleLabel
@onready var subtitle_label: Label = $UI/MainPanel/Header/SubtitleLabel
@onready var btn_start: Button = $UI/MainPanel/Actions/BtnStart
@onready var btn_guide: Button = $UI/MainPanel/Actions/BtnGuide
@onready var btn_quit: Button = $UI/MainPanel/Actions/BtnQuit

# Seleção de Modo
@onready var btn_mode_campaign: Button = $UI/MainPanel/ModeSection/ModeButtons/BtnCampaign
@onready var btn_mode_nightmare: Button = $UI/MainPanel/ModeSection/ModeButtons/BtnNightmare
@onready var mode_desc_label: Label = $UI/MainPanel/ModeSection/ModeDescLabel

# Mutadores
@onready var chk_no_flashlight: CheckBox = $UI/MainPanel/MutatorsSection/Grid/ChkNoFlashlight
@onready var chk_all_runners: CheckBox = $UI/MainPanel/MutatorsSection/Grid/ChkAllRunners
@onready var chk_melee_only: CheckBox = $UI/MainPanel/MutatorsSection/Grid/ChkMeleeOnly

# Telemetria de Recordes
@onready var record_dist_label: Label = $UI/MainPanel/RecordsCard/Margin/VBox/Grid/ValDistance
@onready var record_score_label: Label = $UI/MainPanel/RecordsCard/Margin/VBox/Grid/ValScore
@onready var record_kills_label: Label = $UI/MainPanel/RecordsCard/Margin/VBox/Grid/ValKills
@onready var record_headshots_label: Label = $UI/MainPanel/RecordsCard/Margin/VBox/Grid/ValHeadshots

# Modal de Guia de Sobrevivência
@onready var guide_modal: PanelContainer = $UI/GuideModal
@onready var btn_close_guide: Button = $UI/GuideModal/VBox/BtnCloseGuide

# Tela de Carregamento & Pre-Warming (Preloader)
@onready var loading_overlay: ColorRect = $UI/LoadingOverlay
@onready var progress_bar: ProgressBar = $UI/LoadingOverlay/Center/VBox/ProgressBar
@onready var loading_status_label: Label = $UI/LoadingOverlay/Center/VBox/StatusLabel
@onready var loading_percent_label: Label = $UI/LoadingOverlay/Center/VBox/PercentLabel
@onready var survival_tip_label: Label = $UI/LoadingOverlay/Center/VBox/TipLabel
@onready var prewarm_container: SubViewport = $PrewarmViewport

# Lista de recursos críticos para pré-aquecimento na GPU
const CRITICAL_PREWARM_PATHS: Array[String] = [
	"res://scenes/Zombie.tscn",
	"res://scenes/ZombieNoArm.tscn",
	"res://scenes/WreckedCar.tscn",
	"res://scenes/MilitaryBarricade.tscn",
	"res://scenes/ExplosiveBarrel.tscn",
	"res://scenes/BloodImpact.tscn",
	"res://scenes/MetalSparks.tscn",
	"res://scenes/AmmoPickup.tscn",
	"res://scenes/KnifeViewModel.tscn",
	"res://assets/3D/tactical knife 3d model.glb",
	"res://assets/3D/handgun 3d model.glb"
]

const SURVIVAL_TIPS: Array[String] = [
	"Mantenha a mira na cabeça: tiros na cabeça causam dano fatal imediato.",
	"Em emboscadas corporais, pressione [F] no momento certo para apunhalar com a faca tática.",
	"Deslize [CTRL] sob placas suspensas e fumaça para manter sua velocidade de fuga.",
	"Pule [ESPAÇO] sobre barricadas baixas e detritos militares abandonados.",
	"No Modo Pesadelo, a cada 200m a rodovia fica mais escura e a velocidade aumenta.",
	"Carros em chamas bloqueiam múltiplas faixas: planeje sua troca de faixa antecipadamente."
]

var _is_preloading: bool = false
var _preload_progress: float = 0.0
var _tip_timer: float = 0.0
var _thunder_timer: float = 0.0
var _next_thunder_delay: float = 8.0
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if bg_camera:
		_cam_base_pos = bg_camera.position

	# Inicializa dados de recordes
	_refresh_records_display()

	# Configura estado inicial dos botões de modo
	_update_mode_buttons_ui()

	# Configura mutadores salvos
	chk_no_flashlight.button_pressed = GameController.mutator_no_flashlight
	chk_all_runners.button_pressed = GameController.mutator_all_runners
	chk_melee_only.button_pressed = GameController.mutator_melee_only

	# Conecta sinais de botões
	btn_start.pressed.connect(_on_start_pressed)
	btn_guide.pressed.connect(_on_guide_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_close_guide.pressed.connect(_on_close_guide_pressed)

	btn_mode_campaign.pressed.connect(_on_campaign_selected)
	btn_mode_nightmare.pressed.connect(_on_nightmare_selected)

	chk_no_flashlight.toggled.connect(func(v: bool):
		GameController.mutator_no_flashlight = v
		AudioManager.play_ui_click()
	)
	chk_all_runners.toggled.connect(func(v: bool):
		GameController.mutator_all_runners = v
		AudioManager.play_ui_click()
	)
	chk_melee_only.toggled.connect(func(v: bool):
		GameController.mutator_melee_only = v
		AudioManager.play_ui_click()
	)

	# Efeitos de áudio ao passar o mouse sobre botões
	_connect_hover_sounds([btn_start, btn_guide, btn_quit, btn_mode_campaign, btn_mode_nightmare, btn_close_guide])

	# Oculta telas secundárias
	guide_modal.visible = false
	loading_overlay.visible = false

	# Inicia áudio de fundo
	AudioManager.play_menu_ambience()

	# Animação inicial de título
	_animate_title_pulse()


func _process(delta: float) -> void:
	# 1. Movimento sutil de respiração da câmera no fundo 3D
	if bg_camera and not _is_preloading:
		_cam_time += delta * 0.8
		bg_camera.position = _cam_base_pos + Vector3(
			sin(_cam_time * 0.5) * 0.08,
			cos(_cam_time * 0.7) * 0.05,
			0.0
		)

	# 2. Piscar de alerta de perigo no carro capotado (hazard light)
	if hazard_light:
		var pulse: float = (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
		hazard_light.light_energy = 0.4 + pulse * 2.2

	# 3. Trovões e relâmpagos intermitentes no fundo
	_thunder_timer += delta
	if _thunder_timer >= _next_thunder_delay:
		_thunder_timer = 0.0
		_next_thunder_delay = randf_range(7.0, 15.0)
		_trigger_lightning_flash()

	# 4. Rotação periódica de dicas na tela de carregamento
	if _is_preloading:
		_tip_timer += delta
		if _tip_timer >= 3.0:
			_tip_timer = 0.0
			_show_random_tip()


## Toca o relâmpago no fundo (flash duplo) e estrondo de trovão
func _trigger_lightning_flash() -> void:
	if not thunder_light:
		return

	var tw := create_tween()
	tw.tween_property(thunder_light, "light_energy", 3.2, 0.05)
	tw.tween_property(thunder_light, "light_energy", 0.2, 0.08)
	tw.tween_property(thunder_light, "light_energy", 2.4, 0.04)
	tw.tween_property(thunder_light, "light_energy", 0.05, 0.25)

	# Toca o trovão logo no primeiro clarão
	AudioManager.play_thunder()


func _refresh_records_display() -> void:
	var records: Dictionary = HighScoreManager.get_all_records()
	var best_dist: float = float(records.get("best_distance", 0.0))
	var best_score: int = int(records.get("best_score", 0))
	var best_kills: int = int(records.get("best_kills", 0))
	var best_heads: int = int(records.get("best_headshots", 0))

	if record_dist_label:
		if best_dist >= 800.0:
			record_dist_label.text = "%dm [PESADELO]" % int(best_dist)
			record_dist_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			record_dist_label.text = "%dm" % int(best_dist)
			record_dist_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	if record_score_label:
		record_score_label.text = "%d pts" % best_score
	if record_kills_label:
		record_kills_label.text = "%d" % best_kills
	if record_headshots_label:
		record_headshots_label.text = "%d" % best_heads


func _on_campaign_selected() -> void:
	AudioManager.play_ui_click()
	GameController.selected_game_mode = GameController.GameMode.CAMPAIGN
	_update_mode_buttons_ui()


func _on_nightmare_selected() -> void:
	AudioManager.play_ui_click()
	GameController.selected_game_mode = GameController.GameMode.ENDLESS_NIGHTMARE
	_update_mode_buttons_ui()


func _update_mode_buttons_ui() -> void:
	var is_nightmare: bool = GameController.selected_game_mode == GameController.GameMode.ENDLESS_NIGHTMARE

	if btn_mode_campaign:
		btn_mode_campaign.button_pressed = not is_nightmare
	if btn_mode_nightmare:
		btn_mode_nightmare.button_pressed = is_nightmare

	if mode_desc_label:
		if is_nightmare:
			mode_desc_label.text = "MODO PESADELO: Rodovia sem fim. A cada 200m a velocidade sobe, a escuridão se aprofunda e a munição se esgota. Até onde você aguenta?"
			mode_desc_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		else:
			mode_desc_label.text = "MODO CAMPANHA: Percorra 800m através dos 4 setores da rodovia até o ponto de extração do comboio militar de resgate."
			mode_desc_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))


func _on_start_pressed() -> void:
	if _is_preloading:
		return

	_is_preloading = true
	AudioManager.play_ui_click()
	AudioManager.play_sector_transition()

	# Esconde o painel principal e abre o overlay de carregamento
	main_panel.visible = false
	loading_overlay.visible = true
	loading_overlay.modulate.a = 0.0

	var fade_tw := create_tween()
	fade_tw.tween_property(loading_overlay, "modulate:a", 1.0, 0.25)
	fade_tw.chain().tween_callback(_start_prewarming_and_threaded_load)


func _on_guide_pressed() -> void:
	AudioManager.play_ui_click()
	guide_modal.visible = true


func _on_close_guide_pressed() -> void:
	AudioManager.play_ui_click()
	guide_modal.visible = false


func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()


func _connect_hover_sounds(buttons: Array[Button]) -> void:
	for b in buttons:
		if b:
			b.mouse_entered.connect(func():
				AudioManager.play_ui_click()
			)


func _animate_title_pulse() -> void:
	if not title_label:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(title_label, "modulate", Color(1.0, 0.25, 0.25, 1.0), 1.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title_label, "modulate", Color(0.95, 0.95, 0.95, 1.0), 1.8).set_trans(Tween.TRANS_SINE)


func _show_random_tip() -> void:
	if survival_tip_label and not SURVIVAL_TIPS.is_empty():
		survival_tip_label.text = SURVIVAL_TIPS[randi() % SURVIVAL_TIPS.size()]


# ==============================================================================
# SISTEMA ESSENCIAL DE PRÉ-AQUECIMENTO (PRE-WARMING) E CARGA DE ASSETS
# ==============================================================================

## Executa o ciclo de carga assíncrona com compilação antecipada de shaders na GPU
func _start_prewarming_and_threaded_load() -> void:
	_show_random_tip()
	_update_loading_ui(0.05, "Inicializando sistema de telemetria e memória...")

	# Solicita carga assíncrona em background da cena principal
	var err: Error = ResourceLoader.load_threaded_request(gameplay_scene_path)
	if err != OK:
		push_warning("Falha ao iniciar threaded load de %s. Tentando carga direta." % gameplay_scene_path)

	# Inicia corrotina de pré-aquecimento das malhas críticas
	_run_prewarm_routine()


func _run_prewarm_routine() -> void:
	var total_items: int = CRITICAL_PREWARM_PATHS.size()

	for i in range(total_items):
		var path: String = CRITICAL_PREWARM_PATHS[i]
		var filename: String = path.get_file()
		var step_progress: float = 0.10 + (float(i) / float(total_items)) * 0.55

		_update_loading_ui(step_progress, "Pré-aquecendo malhas 3D e shaders: %s" % filename)

		# Instancia e renderiza 1 frame no SubViewport oculto para forçar a GPU a compilar
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is PackedScene and prewarm_container:
				var instance: Node = res.instantiate()
				if instance:
					prewarm_container.add_child(instance)
					# Dá 1 frame para o motor gráfico registrar na GPU
					await get_tree().process_frame
					instance.queue_free()

		# Aguarda o próximo frame para manter a interface fluida a 60 FPS
		await get_tree().process_frame

	_update_loading_ui(0.70, "Calibrando física balística e geradores acústicos...")
	await get_tree().process_frame

	# Monitora o carregamento em thread da cena destino
	_poll_threaded_loading()


func _poll_threaded_loading() -> void:
	var progress_arr: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(gameplay_scene_path, progress_arr)

	var timeout_counter: int = 0
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var scene_progress: float = progress_arr[0] if progress_arr.size() > 0 else 0.8
		var final_pct: float = clampf(0.70 + scene_progress * 0.25, 0.70, 0.95)
		_update_loading_ui(final_pct, "Finalizando montagem do setor de quarentena...")
		await get_tree().create_timer(0.05).timeout
		status = ResourceLoader.load_threaded_get_status(gameplay_scene_path, progress_arr)
		timeout_counter += 1
		if timeout_counter > 100: # Fallback de 5s
			break

	if status == ResourceLoader.THREAD_LOAD_LOADED or ResourceLoader.exists(gameplay_scene_path):
		_update_loading_ui(1.0, "ZONA DE QUARENTENA PRONTA. BOA SORTE.")
		await get_tree().create_timer(0.35).timeout
		_finish_and_enter_game()
	else:
		push_error("Erro no carregamento assíncrono: status %d" % status)
		get_tree().change_scene_to_file(gameplay_scene_path)


func _update_loading_ui(progress: float, status_text: String) -> void:
	_preload_progress = progress
	if progress_bar:
		progress_bar.value = progress * 100.0
	if loading_percent_label:
		loading_percent_label.text = "%d%%" % int(progress * 100.0)
	if loading_status_label:
		loading_status_label.text = status_text


func _finish_and_enter_game() -> void:
	# Transição suave para preto
	var fade_tw := create_tween()
	fade_tw.tween_property(loading_overlay, "modulate", Color(0, 0, 0, 1), 0.25)
	fade_tw.chain().tween_callback(func():
		AudioManager.stop_menu_ambience()
		var scene_res = ResourceLoader.load_threaded_get(gameplay_scene_path) as PackedScene
		if scene_res:
			get_tree().change_scene_to_packed(scene_res)
		else:
			get_tree().change_scene_to_file(gameplay_scene_path)
	)
