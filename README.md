# 🧟 Dead Run

Jogo de sobrevivência e corrida infinita em 1ª pessoa no estilo realista de *Into the Dead*, desenvolvido em **Godot 4.3 (GDScript)** e otimizado para **Web (Playgama / HTML5)**.

Consulte a documentação técnica e detalhada de todas as mecânicas em:
👉 **[DOCUMENTACAO_MECANICAS.md](DOCUMENTACAO_MECANICAS.md)**

---

## 🎮 Controles Rápidos

- **Movimentação Lateral:** `[A] / [D]` ou `[Setas]`
- **Pulo:** `[Espaço]`
- **Slide / Deslizar:** `[Shift]`
- **Disparo / Estocada:** `[Botão Esquerdo do Mouse]`
- **Recarregar Glock:** `[R]`
- **Quick Melee (Golpe Rápido com Faca):** `[F]` ou `[V]`
- **Golpe de Salvação (Struggle):** `[F]` (durante agarrão em câmera lenta)
- **Slot 1 (Glock 9mm):** `[1]`
- **Slot 2 (Faca Tática - +10% Velocidade):** `[2]`
- **Alternar Armas:** `[Roda do Mouse]`
- **Lanterna Tática:** `[T]` ou `[L]`

---

## 🚀 Principais Características

- **Object Pooling Completo:** 0 alocações de nós ou instâncias em tempo de corrida para zumbis, carros, caixas e pista.
- **Física Imersiva:** Head bobbing em figura 8 (Lissajous), dynamic FOV e inércia de faixas com colisão e ricochete suave.
- **Combate Híbrido:** Balística da Glock 9mm (recoil, clarão, ejeção de cápsulas) e estocada corpo a corpo com a Faca Tática.
- **Hordas de Zumbis:** Duas variantes completas com animações convertidas em in-place, detecção de headshots e partículas de sangue coagulado.
- **Obstáculos Dinâmicos:** Carros tombados em chamas e caixas de munição táticas no asfalto com sinalizadores luminosos.
- **HUD Tático:** Barra de vida com feedback de tremor, avisos de recarga e progressão até a zona de resgate (800m).
