varying vec3 f_normal;
varying vec3 f_position;
varying float f_distance;
varying vec4 f_shadow_coords;

#ifdef VERTEX
attribute vec3 VertexNormal;

uniform mat4 u_model, u_view, u_projection;
uniform mat4 u_normal_mtx;
uniform vec2 u_clips;
// uniform float u_curvature;
uniform mat4 u_lightvp;

vec4 position(mat4 mvp, vec4 vertex) {
	mat4 transform = u_model;
	f_normal = mat3(u_normal_mtx) * VertexNormal;
	f_position = vertex.xyz;

	float dist = length((u_view * u_model * vertex).xyz);
	float scaled = (dist - u_clips.x) / (u_clips.y - u_clips.x);

	f_distance = clamp(dist / u_clips.y, 0.0, 1.0);

	// vertex.z -= pow(scaled, 3.0) * u_curvature;

	vec3 pos_offset = vertex.xyz + VertexNormal * 0.0012;
	vec4 wpos = transform * vec4(pos_offset, 1.0);
	f_shadow_coords = u_lightvp * wpos;

	return u_projection * u_view * vertex;
}
#endif

#ifdef PIXEL
uniform vec3 u_light_direction;
uniform float u_light_intensity;
uniform vec2 u_clips;
uniform vec3 u_fog_color;
uniform sampler2D s_shadow;
uniform bool u_receive_shadow;

uniform float u_roughness;
uniform sampler2D s_roughness;

float pcf_shadow(sampler2D _sampler, vec4 _shadowCoord, float _bias) {
	vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;

	bool outside = any(greaterThan(texCoord.xy, vec2(1.0))) || any(lessThan(texCoord.xy, vec2(0.0)));

	if (outside) {
		return 1.0;
	}

	vec3 coord = _shadowCoord.xyz / _shadowCoord.w;
	float val = Texel(_sampler, coord.xy).x;

	if (val > coord.z) { // + _bias) {
		// return max(0.125, val);
		return min(val, 1.0);
	}

	return 1.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
	vec3 light = normalize(u_light_direction);
	vec3 normal = normalize(f_normal);

	float roughness = Texel(s_roughness, uv).r * u_roughness * 0.95;
	float shade = pow(max(0.0, dot(normal, light)), 1.0-roughness);
	// shade = smoothstep(0.5, 1.0, shade);
	// uncomment after adding reflection maps
	// shade *= 1.0 - metalness;
	// float shade = schlick_ggx_gsf(ndl, ndv, 1.0 - roughness);
	shade = clamp(shade, 0.125, 1.0);
	shade *= u_light_intensity;

	float shadow = 1.0;
	shadow = pcf_shadow(s_shadow, f_shadow_coords, 0.01);
	if (u_receive_shadow) {
		shade *= shadow;
	}

	color.rgb += 0.025;

	vec3 blending = abs(f_normal);
	blending = normalize(max(blending, 0.00001)); // Force weights to sum to 1.0
	float b = (blending.x + blending.y + blending.z);
	blending /= vec3(b);

	float scale = 0.25;
	vec4 xaxis = Texel(tex, f_position.yz * scale);
	vec4 yaxis = Texel(tex, f_position.xz * scale);
	vec4 zaxis = Texel(tex, f_position.xy * scale);
	vec4 tripla1 = xaxis * blending.x + xaxis * blending.y + zaxis * blending.z;
	color.rgb = tripla1.rgb * color.rgb;

	// ambient
	vec3 top = vec3(0.2, 0.7, 1.0) * 3.0;
	vec3 bottom = vec3(0.30, 0.25, 0.35) * 2.0;
	vec3 ambient = mix(top, bottom, dot(normal, vec3(0.0, 0.0, -1.0)) * 0.5 + 0.5);
	ambient *= color.rgb;
	ambient *= clamp(u_light_intensity, 0.25, 1.0);

	// combine diffuse with light info
	vec3 diffuse = Texel(tex, uv).rgb * color.rgb * vec3(shade * 10.0);
	diffuse += ambient;

	// mix ambient beyond the terminator
	vec3 out_color = mix(ambient.rgb, diffuse.rgb, clamp(dot(light, normal) + 0.2, 0.0, 1.0));

	// fog
	float scaled = pow(f_distance, 1.6);

	vec3 final = mix(out_color.rgb, u_fog_color, scaled);
	// final *= final;

	return vec4(final, 1.0);
}
#endif
