shader_type canvas_item;

// Dead Run - Screen Rain Droplets Shader (Godot 4.3)
// Simula gotas de chuva e filetes de água transparentes escorrendo pela lente da câmera,
// gerando distorção refrativa e realce especular via SCREEN_TEXTURE.


uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.75;
uniform float distortion_strength : hint_range(0.0, 0.08) = 0.022;
uniform float drop_speed : hint_range(0.1, 4.0) = 1.15;

vec2 hash22(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(vec2(p.x * p.y, p.x + p.y));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 aspect_uv = uv * vec2(1.777, 1.0);
	vec2 total_distortion = vec2(0.0);
	float total_drops = 0.0;

	// Camada 1: Gotículas condensadas que escorrem suavemente
	vec2 grid1 = aspect_uv * 16.0;
	grid1.y += TIME * drop_speed * 0.35;
	vec2 id1 = floor(grid1);
	vec2 f1 = fract(grid1) - 0.5;
	vec2 h1 = hash22(id1);
	if (h1.x > 0.62) {
		float r1 = length(f1);
		float drop_mask1 = smoothstep(0.24, 0.04, r1);
		vec2 norm1 = normalize(f1 + vec2(0.0001)) * drop_mask1;
		total_distortion += norm1 * distortion_strength * 0.85;
		total_drops += drop_mask1;
	}

	// Camada 2: Filetes verticais de água escorrendo com o impacto da chuva
	vec2 grid2 = aspect_uv * vec2(26.0, 6.5);
	grid2.y += TIME * drop_speed * 1.4;
	vec2 id2 = floor(grid2);
	vec2 f2 = fract(grid2) - 0.5;
	vec2 h2 = hash22(id2);
	if (h2.x > 0.75) {
		f2.x *= 2.4;
		float r2 = length(f2);
		float streak_mask2 = smoothstep(0.26, 0.05, r2);
		vec2 norm2 = normalize(f2 + vec2(0.0001)) * streak_mask2;
		total_distortion += norm2 * distortion_strength * 1.15;
		total_drops += streak_mask2;
	}

	// Distorção ótica na cena renderizada
	vec2 distorted_uv = uv + total_distortion * rain_amount;
	vec4 scene_color = texture(screen_texture, distorted_uv);

	// Destaque especular suave na silhueta da gota
	vec4 drop_highlight = vec4(0.85, 0.92, 1.0, 1.0) * total_drops * 0.16 * rain_amount;

	COLOR = scene_color + drop_highlight;
}
