class_name GameManager
extends GameController

## Dead Run - GameManager (Godot 4.3)
## Orquestrador de jogo com cálculo de progresso baseado estritamente no deslocamento real do jogador.
## Herda static var is_game_over, static var instance e trigger_game_over() de GameController.

var distance_traveled: float = 0.0
var last_player_z: float = 0.0
@export var total_goal_distance: float = 800.0


func _ready() -> void:
	super._ready()
	total_goal_distance = target_distance
	if player and is_instance_valid(player):
		last_player_z = player.global_position.z
	elif is_inside_tree():
		player = get_node_or_null("Player") as Player
		if player:
			last_player_z = player.global_position.z


func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	var z_diff: float = absf(player.global_position.z - last_player_z)
	# Só contabiliza avanço se o jogador estiver de fato se movendo para frente
	if z_diff > 0.01 and not is_game_over:
		distance_traveled += z_diff

		if selected_game_mode == GameMode.CAMPAIGN:
			target_distance = total_goal_distance
		else:
			target_distance = distance_traveled

		_on_distance_updated(distance_traveled)

		if spawner:
			spawner.distance_traveled = distance_traveled

		if selected_game_mode == GameMode.CAMPAIGN:
			if distance_traveled >= total_goal_distance and not game_finished:
				_on_rescue_reached()
		else:
			_process_nightmare_milestones(distance_traveled)

	last_player_z = player.global_position.z


static func request_game_over() -> void:
	is_game_over = true
	if instance and is_instance_valid(instance):
		instance.trigger_game_over()
