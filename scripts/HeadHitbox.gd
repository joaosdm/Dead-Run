class_name HeadHitbox
extends Area3D

## Dead Run - Headshot Hitbox (Godot 4.3)
## Detecta tiros de precisão na cabeça do zumbi e multiplica o dano crítico.

@export var damage_multiplier: float = 2.5
@export var zombie: Node3D = null


func _ready() -> void:
	name = "HeadHitbox"
	if not zombie:
		zombie = get_parent() as Node3D
	var col = get_node_or_null("CollisionShape3D")
	if col:
		col.name = "HeadCol"


## Chamado pelo sistema de raycast hitscan ao atingir a cabeça
func take_damage(amount: float, hit_point: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO, is_headshot: bool = true, is_point_blank: bool = false) -> void:
	if zombie and is_instance_valid(zombie) and zombie.has_method("take_damage"):
		zombie.take_damage(amount * damage_multiplier, hit_point, hit_normal, true, is_point_blank)

