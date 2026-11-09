class_name BloodImpact
extends CPUParticles3D

## Dead Run - Blood Impact Splatter VFX (Godot 4.3)
## Emite explosão one-shot de gotas esféricas de sangue vermelho coagulado (#6b0b0b a #8a1212)
## com gravidade puxando as gotas para o asfalto e auto-liberação (queue_free) em 0.45s.


func _ready() -> void:
	restart()
	emitting = true
	# Auto-liberação da memória ao término do efeito (lifetime = 0.4s) em tempo real
	var timer := get_tree().create_timer(lifetime + 0.05, true, false, true)
	timer.timeout.connect(_on_finished)



func _on_finished() -> void:
	queue_free()
