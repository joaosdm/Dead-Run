shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Dead Run - Ultra-Light Wet Asphalt & Lane Markings Shader (Web / Playgama / Mobile Optimized)
// Desenha asfalto granulado, poças d'água reflexivas, faixa dupla amarela central e faixas brancas tracejadas
// em um ÚNICO Draw Call (Zero trig/for-loops pesados por pixel, 100% fluido em WebGL/Mobile!)

uniform vec4 asphalt_color : source_color = vec4(0.08, 0.085, 0.095, 1.0);
uniform vec4 puddle_color : source_color = vec4(0.035, 0.04, 0.05, 1.0);
uniform vec4 yellow_line_color : source_color = vec4(0.88, 0.68, 0.12, 1.0);
uniform vec4 white_line_color : source_color = vec4(0.82, 0.84, 0.86, 1.0);

varying vec3 world_pos;

// Hash ultra-rápido (sem sin/cos)
float fast_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise simples (1 única oitava interpolada)
float fast_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fast_hash(i);
	float b = fast_hash(i + vec2(1.0, 0.0));
	float c = fast_hash(i + vec2(0.0, 1.0));
	float d = fast_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;
	float abs_x = abs(wp.x);

	// 1. Granulação rápida e mapa de poças d'água (apenas 2 leituras de ruído!)
	float grain = fast_hash(floor(wp * 24.0)) * 0.025;
	float puddle_n = fast_noise(wp * 0.22);
	float puddle_mask = smoothstep(0.54, 0.68, puddle_n);

	// Desgaste longitudinal nas trilhas de pneu
	float tire_track = smoothstep(0.6, 0.0, abs(abs_x - 2.2)) + smoothstep(0.6, 0.0, abs(abs_x - 5.5));
	puddle_mask = clamp(puddle_mask + tire_track * 0.18, 0.0, 1.0);

	vec3 col = mix(asphalt_color.rgb + vec3(grain), puddle_color.rgb, puddle_mask * 0.75);
	float rough = mix(0.62, 0.08, puddle_mask);
	float metal = mix(0.12, 0.65, puddle_mask);

	// 2. Pintura de Pista Integrada no Shader (Elimina dezenas de MeshInstance3D por módulo!)
	// A) Faixa Dupla Amarela Central (X em torno de +/- 0.15)
	float center_line = step(abs(abs_x - 0.15), 0.065);

	// B) Faixas Brancas Tracejadas divisoras de pista (X em +/- 3.35, tracejado a cada 8m em Z)
	float dash_pattern = step(fract(wp.y * 0.125), 0.42);
	float lane_dash = step(abs(abs_x - 3.35), 0.06) * dash_pattern;

	// C) Faixa Branca Contínua do Acostamento (X em +/- 7.8)
	float shoulder_line = step(abs(abs_x - 7.8), 0.075);

	// D) Olhos de gato reflexivos (Cat-eyes emissivos a cada 10m nos acostamentos)
	float cat_eye_z = step(fract(wp.y * 0.1), 0.025);
	float cat_eye = step(abs(abs_x - 7.65), 0.08) * cat_eye_z;

	float paint_wear = 1.0 - puddle_mask * 0.35;
	col = mix(col, yellow_line_color.rgb, center_line * paint_wear);
	col = mix(col, white_line_color.rgb, clamp(lane_dash + shoulder_line, 0.0, 1.0) * paint_wear);
	rough = mix(rough, 0.42, clamp(center_line + lane_dash + shoulder_line, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.45, 0.88, puddle_mask);
	EMISSION = vec3(1.0, 0.32, 0.05) * (cat_eye * 2.2);
}
