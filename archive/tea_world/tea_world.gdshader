shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec4 screen = texture(SCREEN_TEXTURE, SCREEN_UV);

	float grey = dot(screen.rgb, vec3(0.299, 0.587, 0.114));
	vec3 dread_tint = vec3(0.25, 0.18, 0.22);
	vec3 desaturated = mix(screen.rgb, vec3(grey), intensity * 0.75);
	vec3 tinted = mix(desaturated, dread_tint * grey, intensity * 0.2);

	vec2 uv = SCREEN_UV - 0.5;
	float vignette = 1.0 - dot(uv, uv) * 1.8;
	vignette = mix(1.0, vignette, intensity * 0.8);
	tinted *= max(vignette, 0.15);

	float pulse = sin(time * 0.6) * 0.5 + 0.5;
	float edge_darken = mix(1.0, 0.85 + pulse * 0.08, intensity);
	tinted *= edge_darken;

	float grain = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453 + time * 0.3);
	tinted = mix(tinted, tinted * (0.95 + grain * 0.1), intensity * 0.05);

	float luminance = dot(tinted, vec3(0.299, 0.587, 0.114));
	vec3 shadow_boost = mix(tinted, tinted * vec3(1.15, 0.85, 0.85), (1.0 - luminance) * intensity * 0.3);
	tinted = mix(tinted, shadow_boost, intensity * 0.6);

	COLOR = vec4(tinted, screen.a);
}
