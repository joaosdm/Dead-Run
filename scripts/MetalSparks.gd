class_name MetalSparks
extends CPUParticles3D

## Dead Run - Metal Scrape Sparks VFX (Godot 4.3)
## Emite explosão de faíscas alaranjadas brilhantes no ponto de atrito entre o jogador e a carcaça de carro.

func _ready() -> void:
	restart()
	emitting = true
	var timer := get_tree().create_timer(lifetime + 0.05)
	timer.timeout.connect(_on_finished)


func _on_finished() -> void:
	queue_free()
