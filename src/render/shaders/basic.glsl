#pragma glsl3

varying vec3 f_normal;
varying float f_distance;
varying vec3 f_view_dir;
varying vec3 f_view_nor;
varying mat4 f_tbn;

varying vec4 f_shadow_coords;
varying vec3 f_hash_seed;

#ifdef VERTEX
attribute vec3 VertexNormal;
attribute vec4 VertexWeight;
attribute vec4 VertexBone; // used as ints!

uniform mat4 u_model, u_view, u_projection;
uniform mat4 u_normal_mtx;

uniform mat4 u_lightvp;

uniform int u_rigged;
uniform mat4 u_pose[90];

uniform vec2 u_clips;
uniform float u_curvature;

mat4 getDeformMatrix() {
	if (u_rigged == 1) {
		// *255 because byte data is normalized against our will.
		return
			u_pose[int(VertexBone.x*255.0)] * VertexWeight.x +
			u_pose[int(VertexBone.y*255.0)] * VertexWeight.y +
			u_pose[int(VertexBone.z*255.0)] * VertexWeight.z +
			u_pose[int(VertexBone.w*255.0)] * VertexWeight.w
		;
	}
	return mat4(1.0);
}

vec4 position(mat4 mvp, vec4 vertex) {
	mat4 transform = u_model;
	mat3 normal_mtx = mat3(u_normal_mtx);
	mat4 deform_mtx = getDeformMatrix();
	transform *= deform_mtx;
	normal_mtx *= mat3(deform_mtx);

	f_hash_seed = vertex.xyz;

	f_normal = mat3(normal_mtx) * VertexNormal;
	f_view_nor = mat3(u_view) * f_normal;

	vec4 wpos = transform * vertex;
	vec4 vpos = u_view * wpos;
	f_view_dir = -vpos.xyz;

	float dist = length(vpos.xyz);
	float scaled = (dist - u_clips.x) / (u_clips.y - u_clips.x);

	f_distance = clamp(dist / u_clips.y, 0.0, 1.0);

	vec3 pos_offset = vertex.xyz + VertexNormal * 0.0012;
	wpos = transform * vec4(pos_offset, 1.0);
	f_shadow_coords = u_lightvp * wpos;

	// vec3 T = normalize(vec3(u_view * transform * vec4(VertexTangent.xyz, 0.0)));
	// vec3 B = normalize(vec3(u_view * transform * VertexTangent));
	// vec3 N = normalize(vec3(u_view * transform * vec4(VertexNormal, 0.0)));
	// f_tbn = mat3(T, B, N);

	// vertex.z -= pow(scaled, 3.0) * u_curvature;

	return u_projection * vpos;
}
#endif

#ifdef PIXEL
uniform vec3 u_light_direction;
uniform float u_light_intensity;
uniform vec2 u_clips;
uniform vec3 u_fog_color;
uniform float u_roughness;
uniform float u_metalness;
uniform highp mat4 u_view;
uniform float u_exposure;
uniform vec3 u_white_point;
uniform bool u_receive_shadow;

uniform vec4 u_texel_size;

uniform sampler2D s_roughness;
uniform sampler2D s_metalness;

uniform sampler2D s_shadow;
uniform bool u_alpha_blend;

vec3 Tonemap_ACES(vec3 x) {
	float a = 2.51;
	float b = 0.03;
	float c = 2.43;
	float d = 0.59;
	float e = 0.14;
	return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}

float schlick_ior_fresnel(float ior, float LdotH) {
	float f0 = pow((ior-1.0)/(ior+1.0), 2.0);
	float x = clamp(1.0-LdotH, 0.0, 1.0);
	float x2 = x*x;
	return f0 + (1.0 - f0) * (x2*x2*x);
}

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

	// return textureProj(_sampler, _shadowCoord, _bias);
}

float schlick_ggx_gsf(float ndl, float ndv, float roughness) {
	float k = roughness / 2.0;
	float sl = (ndl) / (ndl * (1.0 - k) + k);
	float sv = (ndv) / (ndv * (1.0 - k) + k);
	return sl * sv;
}

const float pi = 3.1415926535;

float trowbridge_reitz_ndf(float ndh, float roughness) {
	float r2 = roughness*roughness;
	float d2 = ndh*ndh * (r2-1.0) + 1.0;
	d2 *= d2;
	return r2 / (pi * d2);
}

vec4 rgbe8_encode(vec3 _rgb) {
	vec4 rgbe8;
	float maxComponent = max(max(_rgb.x, _rgb.y), _rgb.z);
	float exponent = ceil(log2(maxComponent) );
	rgbe8.xyz = _rgb / exp2(exponent);
	rgbe8.w = (exponent + 128.0) / 255.0;
	return rgbe8;
}

#ifdef GL_ES
#	define USE_RGBE 1
#endif

const float cutoff = 0.25;
const float mip_scale = 0.25;

float CalcMipLevel(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float delta_max_sqr = max(dot(dx, dx), dot(dy, dy));

	return max(0.0, 0.5 * log2(delta_max_sqr));
}

// // A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
// uint hash( uint x ) {
//     x += ( x << 10u );
//     x ^= ( x >>  6u );
//     x += ( x <<  3u );
//     x ^= ( x >> 11u );
//     x += ( x << 15u );
//     return x;
// }

// // Compound versions of the hashing algorithm I whipped together.
// // uint hash( uvec2 v ) { return hash( v.x ^ hash(v.y)                         ); }
// uint hash( uvec3 v ) { return hash( v.x ^ hash(v.y) ^ hash(v.z)             ); }
// // uint hash( uvec4 v ) { return hash( v.x ^ hash(v.y) ^ hash(v.z) ^ hash(v.w) ); }

// // Construct a float with half-open range [0:1] using low 23 bits.
// // All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
// float floatConstruct( uint m ) {
//     const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
//     const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

//     m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
//     m |= ieeeOne;                          // Add fractional part to 1.0

//     float  f = uintBitsToFloat( m );       // Range [1:2]
//     return f - 1.0;                        // Range [0:1]
// }

// // Pseudo-random value in half-open range [0:1].
// // float random( float x ) { return floatConstruct(hash(floatBitsToUint(x))); }
// // float random( vec2  v ) { return floatConstruct(hash(floatBitsToUint(v))); }
// float random( vec3  v ) { return floatConstruct(hash(floatBitsToUint(v))); }
// // float random( vec4  v ) { return floatConstruct(hash(floatBitsToUint(v))); }


// void main()
// {
//     vec3  inputs = vec3( gl_FragCoord.xy, time ); // Spatial and temporal inputs
//     float rand   = random( inputs );              // Random per-pixel value
//     vec3  luma   = vec3( rand );                  // Expand to RGB

//     fragment = vec4( luma, 1.0 );
// }
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
	vec3 light = normalize(u_light_direction);
	vec3 normal = normalize(f_normal);
	vec3 view_dir = normalize(f_view_dir);
	float ndl = max(0.0, dot(normal, light));

	vec3 view_nor = normalize(f_view_nor);
	// bias to prevent extreme darkening on edges
	float ndv = max(0.05, dot(view_nor, view_dir));
	vec3 halfv = normalize(view_dir + (u_view * vec4(light, 0.0)).xyz);
	float ndh = max(0.0, dot(view_nor, halfv));

	float metalness = Texel(s_metalness, uv).g * u_metalness;
	float fresnel = schlick_ior_fresnel(1.8 + 2.0*metalness, ndv); // typical=1.45

	float roughness = Texel(s_roughness, uv).r * u_roughness * 0.95;
	float shade = pow(max(0.0, dot(normal, light)), 1.0-roughness);
	shade = smoothstep(0.475, 0.525, shade);
	// uncomment after adding reflection maps
	// shade *= 1.0 - metalness;
	// float shade = schlick_ggx_gsf(ndl, ndv, 1.0 - roughness);
	shade = clamp(shade, 0.125, 1.0);
	shade += fresnel;// * 0.5;
	shade *= u_light_intensity;

	float shadow = 1.0;
	shadow = pcf_shadow(s_shadow, f_shadow_coords, 0.01);
	if (u_receive_shadow) {
		shade *= shadow;
	}

	color.rgb += 0.025;

	// ambient
	vec3 top = vec3(0.2, 0.7, 1.0) * 3.0;
	vec3 bottom = vec3(0.30, 0.25, 0.35) * 2.0;
	vec3 ambient = mix(top, bottom, dot(normal, vec3(0.0, 0.0, -1.0)) * 0.5 + 0.5);
	ambient *= color.rgb;
	ambient *= clamp(u_light_intensity, 0.075, 0.15);

	// combine diffuse with light info
	vec4 tex_albedo = Texel(tex, uv);
	vec3 albedo  = tex_albedo.rgb * color.rgb;
	vec3 diffuse = albedo * vec3(shade * 10.0);

	vec3 spec = mix(vec3(1.0), albedo, metalness * 0.5 + 0.5);
	float highlight = trowbridge_reitz_ndf(ndh, u_roughness);
	// highlight = step(0.5, highlight);
	spec *= highlight;
	spec *= u_light_intensity;
	spec *= shadow;
	diffuse += spec;

	vec3 out_color = diffuse + ambient;

	// fog
	float scaled = pow(f_distance, 1.6);

	vec3 final = mix(out_color.rgb, u_fog_color, scaled);
	// final = sqrt(final);

	// #ifdef GL_ES
	// vec3 white = Tonemap_ACES(vec3(1000.0));
	// final.rgb *= exp2(u_exposure*2.0);
	// final.rgb = Tonemap_ACES(final.rgb/u_white_point)*white;
	// #endif

#ifdef USE_RGBE
	return rgbe8_encode(final);
#else
#	ifndef GL_ES
	final *= final;
#	endif
	float alpha = tex_albedo.a*color.a;
	if (alpha < 0.01) {
		discard;
	}

#define ALPHA_TO_COVERAGE

	if (!u_alpha_blend) {
#ifdef ALPHA_TO_COVERAGE
		// rescale alpha by mip level (if not using preserved coverage mip maps)
		alpha *= 1.0 + max(0.0, CalcMipLevel(uv * u_texel_size.zw)) * mip_scale;
		
		// rescale alpha by partial derivative
		alpha = (alpha - cutoff) / max(fwidth(alpha), 0.0001) + 0.5;

		alpha = clamp(alpha, 0.01, 1.0);

		// this seems to look better without msaa, but worse with it?
		// final *= alpha; // premul
		// alternatively...
		// final /= alpha; // brighten
		return vec4(final, alpha);
#else
		// hashed alpha
		//
#endif
	}

	return vec4(final, 1.0)*clamp(alpha, 0.0, 1.0);
#endif
}
#endif
