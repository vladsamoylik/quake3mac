#version 450

layout(set = 0, binding = 0) uniform sampler2D texture0;

layout(location = 0) in vec2 frag_tex_coord;

layout(location = 0) out vec4 out_color;

layout(constant_id = 0) const float gamma = 1.0;
layout(constant_id = 1) const float obScale = 2.0;
layout(constant_id = 2) const float greyscale = 0.0;
//
layout(constant_id = 7) const int ditherMode = 0; // 0 - disabled, 1 - ordered
layout(constant_id = 8) const int depth_r = 255;
layout(constant_id = 9) const int depth_g = 255;
layout(constant_id = 10) const int depth_b = 255;
layout(constant_id = 11) const int toneMapping = 0; // 0 - linear/gamma, 1 - PQ (HDR10), 2 - ACES

const vec3 sRGB = { 0.2126, 0.7152, 0.0722 };

// PQ (ST2084) constants for HDR10 tone mapping
const float PQ_M1 = 0.1593017578125;      // (2610.0 / 4096.0) / 4.0
const float PQ_M2 = 78.84375;              // (2523.0 / 4096.0) * 128.0
const float PQ_C1 = 0.8359375;             // 3424.0 / 4096.0
const float PQ_C2 = 18.8515625;            // (2413.0 / 4096.0) * 32.0
const float PQ_C3 = 18.6875;               // (2392.0 / 4096.0) * 32.0

// Convert linear to PQ (ST2084) - HDR10 tone mapping
vec3 linearToPQ(vec3 linear) {
    // Normalize to 10000 nits (typical HDR10 peak)
    vec3 normalized = max(linear / 10000.0, vec3(0.0));
    vec3 y = pow(normalized, vec3(PQ_M1));
    vec3 num = vec3(PQ_C1) + vec3(PQ_C2) * y;
    vec3 den = vec3(1.0) + vec3(PQ_C3) * y;
    return pow(num / den, vec3(PQ_M2));
}

// ACES Filmic tone mapping (alternative cinematic look)
vec3 acesFilmic(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

const int bayerSize = 8;
const float bayerMatrix[bayerSize * bayerSize] = {
	0,  32, 8,  40, 2,  34, 10, 42,
	48, 16, 56, 24, 50, 18, 58, 26,
	12, 44, 4,  36, 14, 46, 6,  38,
	60, 28, 52, 20, 62, 30, 54, 22,
	3,  35, 11, 43, 1,  33, 9,  41,
	51, 19, 59, 27, 49, 17, 57, 25,
	15, 47, 7,  39, 13, 45, 5,  37,
	63, 31, 55, 23, 61, 29, 53, 21
};

float threshold() {
	ivec2 coordDenormalized = ivec2(gl_FragCoord.xy);
	ivec2 bayerCoord = coordDenormalized % bayerSize;
	float bayerSample = bayerMatrix[bayerCoord.x + bayerCoord.y * bayerSize];
	float threshold = (bayerSample + 0.5) / float(bayerSize * bayerSize);
	return threshold;
}

vec3 dither(vec3 color) {
	ivec3 depth = ivec3(depth_r, depth_g, depth_b);
	vec3 cDenormalized = color * depth;
	vec3 cLow = floor(cDenormalized);
	vec3 cFractional = cDenormalized - cLow;
	vec3 cDithered = cLow + step(threshold(), cFractional);
	return cDithered / depth;
}

void main() {
	vec3 base = texture(texture0, frag_tex_coord).rgb;

	if ( greyscale == 1 )
	{
		base = vec3(dot(base, sRGB));
	}
	else if ( greyscale != 0 )
	{
		vec3 luma = vec3(dot(base, sRGB));
		base = mix(base, luma, greyscale);
	}

	vec3 linear = base * obScale;
	
	if ( toneMapping == 1 ) {
		// PQ (HDR10) tone mapping - cinematic HDR10 look
		out_color = vec4(linearToPQ(linear), 1.0);
	}
	else if ( toneMapping == 2 ) {
		// ACES Filmic tone mapping - alternative cinematic look
		out_color = vec4(acesFilmic(linear), 1.0);
	}
	else if ( gamma != 1.0 )
	{
		// Standard gamma correction (SDR)
		out_color = vec4(pow(base, vec3(gamma)) * obScale, 1);
	}
	else
	{
		// Linear output (EDR without tone mapping)
		out_color = vec4(linear, 1);
	}

	if ( ditherMode == 1 ) {
		out_color.rgb = dither(out_color.rgb);
	}
}
