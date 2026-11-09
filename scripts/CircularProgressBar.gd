class_name CircularProgressBar
extends Control

## Dead Run - Tactical Circular Progress Bar (Godot 4.3)
## Renderiza barra circular vetorial com antialiasing para QTEs de emergência e combate corporal.

@export var value: float = 1.0
@export var max_value: float = 1.0
@export var radius: float = 38.0
@export var bar_width: float = 5.0
@export var bg_color: Color = Color(0.12, 0.14, 0.18, 0.7)
@export var center_text: String = "F"
@export var show_center_text: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(96, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_progress(current: float, total: float = 1.0) -> void:
	value = clampf(current, 0.0, total)
	max_value = maxf(0.001, total)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var r: float = radius

	# 1. Círculo escuro translúcido de fundo tático
	draw_circle(center, r + 6.0, Color(0.04, 0.05, 0.06, 0.65))

	# 2. Anel de trilha escura (360 graus)
	draw_arc(center, r, 0.0, TAU, 64, bg_color, bar_width, true)

	# 3. Anel de progresso ativo (esgota no sentido horário)
	var ratio: float = clampf(value / max_value, 0.0, 1.0)
	if ratio > 0.001:
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + (ratio * TAU)

		# Cor dinâmica conforme urgência:
		# Branco-azulado tático (> 60%), Amarelo âmbar (30%-60%), Vermelho crítico (< 30%)
		var active_color: Color
		if ratio < 0.32:
			active_color = Color(1.0, 0.22, 0.18, 1.0)
		elif ratio < 0.65:
			active_color = Color(1.0, 0.78, 0.22, 1.0)
		else:
			active_color = Color(0.92, 0.95, 1.0, 1.0)

		draw_arc(center, r, start_angle, end_angle, 64, active_color, bar_width + 0.8, true)

	# 4. Letra/tecla centralizada estilizada
	if show_center_text and center_text != "":
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 22
		var text_size: Vector2 = font.get_string_size(center_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos: Vector2 = center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
		draw_string(font, text_pos, center_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.96, 0.97, 0.99))
