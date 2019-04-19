static const float PI = 3.14159265f;
static const float JITTER_TWEAK = 2.0f;
static const float EDGE_RANGE = 0.10f;

static const float kernelX[48] = {
	0.5f,
	0.482962913f,
	0.433012701f,
	0.35355339f,
	0.250000000f,
	0.129409522f,
	0.0f,
	-0.129409522f,
	-0.24999999f,
	-0.353553390f,
	-0.433012701f,
	-0.48296291f,
	-0.5f,
	-0.482962913f,
	-0.43301270f,
	-0.353553390f,
	-0.25000000f,
	-0.129409522f,
	0.0f,
	0.129409522f,
	0.250000000f,
	0.35355339f,
	0.43301270f,
	0.482962913f,
	0.33333333f,
	0.307959844f,
	0.235702260f,
	0.12756114f,
	0.0f,
	-0.127561144f,
	-0.23570226f,
	-0.307959844f,
	-0.33333333f,
	-0.307959844f,
	-0.23570226f,
	-0.127561144f,
	0.0f,
	0.127561144f,
	0.235702260f,
	0.30795984f,
	0.166666666f,
	0.117851130f,
	0.0f,
	-0.11785113f,
	-0.166666666f,
	-0.117851130f,
	0.0f,
	0.117851130f };

static const float kernelY[48] = {
	0.0f,
	0.129409522f,
	0.249999999f,
	0.353553390f,
	0.433012701f,
	0.482962913f,
	0.5f,
	0.482962913f,
	0.433012701f,
	0.353553390f,
	0.249999999f,
	0.129409522f,
	0.0f,
	-0.12940952f,
	-0.24999999f,
	-0.35355339f,
	-0.43301270f,
	-0.48296291f,
	-0.5f,
	-0.48296291f,
	-0.43301270f,
	-0.35355339f,
	-0.25000000f,
	-0.12940952f,
	0.0f,
	0.127561144f,
	0.23570226f,
	0.307959844f,
	0.333333333f,
	0.307959844f,
	0.235702260f,
	0.127561144f,
	0.0f,
	-0.12756114f,
	-0.23570226f,
	-0.30795984f,
	-0.33333333f,
	-0.30795984f,
	-0.23570226f,
	-0.12756114f,
	0.0f,
	0.1178511f,
	0.166666666f,
	0.117851130f,
	0.0f,
	-0.11785113f,
	-0.166666666f,
	-0.117851130f
};

Texture2D<float4>   gDilate;
Texture2D<float4>   gHalfResZBuffer;
Texture2D<float4>   gHalfResFrameColor;
Texture2D<float4>   gPresortBuffer;
Texture2D<float4>   gRayTraceMask;

SamplerState gSampler;

struct PS_OUTPUT

{
	float4 halfResFarField		: SV_Target0;
	float4 halfResNearField		: SV_Target1;
	float4 rayTraceMask			: SV_Target2;
};

cbuffer cameraParametersCB
{
	float gOffset;
	float gNearLimitFocusZone;
	float gDistanceToFocalPlane;
	float gTextureWidth;
	float gTextureHeight;
	float gSinglePixelRadius;
	uint gFrameCount;
}

/*
Kernel Weights :
 i : 0 -> 23
kernel[i].x = cos(2.0f * PI* (float)i / 24.0f) / 2; //correction coc diameter -> radius
kernel[i].x = sin(2.0f * PI* (float)i / 24.0f) / 2;
 i : 24 -> 39
kernel[i].x = cos(2.0f * PI* (float)i / 16.0f) / 3;
kernel[i].x = sin(2.0f * PI* (float)i / 16.0f) / 3;
 i : 40 -> 47
kernel[i].x = cos(2.0f * PI* (float)i / 8.0f) / 6;
kernel[i].x = sin(2.0f * PI* (float)i / 8.0f) / 6;
*/

/*
Returns the alpha of a splatted pixel according to coc size
*/
float SampleAlpha(float cocRadius, float singlePixelRadius) {
	// Samplecoc is radius of coc in pixels
	return min(1.0f / (PI * cocRadius * cocRadius), 1.0f / (PI * singlePixelRadius * singlePixelRadius));
}

uint initRand(uint val0, uint val1, uint backoff = 16)
{
	uint v0 = val0, v1 = val1, s0 = 0;

	[unroll]
	for (uint n = 0; n < backoff; n++)
	{
		s0 += 0x9e3779b9;
		v0 += ((v1 << 4) + 0xa341316c) ^ (v1 + s0) ^ ((v1 >> 5) + 0xc8013ea4);
		v1 += ((v0 << 4) + 0xad90777d) ^ (v0 + s0) ^ ((v0 >> 5) + 0x7e95761e);
	}
	return v0;
}

// Takes our seed, updates it, and returns a pseudorandom float in [0..1]
float nextRand(inout uint s)
{
	s = (1664525u * s + 1013904223u);
	return float(s & 0x00FFFFFF) / float(0x01000000);
}


PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT MainPassBufOut;
	uint2 pixelPos = (uint2)pos.xy;

	// Initialization
	float4 foreground;
	float4 background;
	float coc = gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].r; //max coc in tile
	float coc_RT = gRayTraceMask[uint2(pixelPos.x / 10, pixelPos.y / 10)].g; //max coc in tile
	float4 farFieldValue;
	float4 nearFieldValue;

	float3 sampleColor = float3(0.0f, 0.0f, 0.0f);
	float spreadCmp;
	float alphaSpreadCmpSum;
	
	uint randSeed = initRand(pixelPos.x + (uint)gTextureWidth * pixelPos.y, gFrameCount, 16);

	// Initialisation with target pixel values
	foreground = gPresortBuffer[pixelPos].b * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
	background = gPresortBuffer[pixelPos].g * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
	alphaSpreadCmpSum = SampleAlpha(gPresortBuffer[pixelPos].r / 2.0f, gSinglePixelRadius);

	// For ray trace mask 
	bool foregroundSampled = gHalfResZBuffer[pixelPos].r <= gDistanceToFocalPlane;
	float closestForeground = gHalfResZBuffer[pixelPos].r;
	float furthestBackground = gHalfResZBuffer[pixelPos].r;

	// Iterate over the samples

	for (int i = 0; i < 48; i++) {
			
		/*Here let’s suppose that the circular filter has the same size as the max_coc in tile */
		
		// Sampling coordinate for background layer
		float2 kernelCoord = float2( ((float)pos.x * 2.0f + coc * kernelX[i] / 2.0f) / gTextureWidth, ((float)pos.y * 2.0f + coc * kernelY[i] / 2.0f) / gTextureHeight);
		float2 jitter = float2( ((nextRand(randSeed) - 0.5f) * PI * coc / (48.0f * JITTER_TWEAK)) / gTextureWidth, ((nextRand(randSeed) - 0.5f) * PI * coc / (48.0f * JITTER_TWEAK)) / gTextureHeight);
		float2 sampleCoord = kernelCoord + jitter;

		// Sampling coordinate for foreground layer
		float2 sampleForegroundCoord = float2(((float)pos.x * 2.0f + coc_RT * kernelX[i] / 2.0f) / gTextureWidth, ((float)pos.y * 2.0f + coc_RT * kernelY[i] / 2.0f) / gTextureHeight);
		float3 presortSample = gPresortBuffer.SampleLevel(gSampler, sampleCoord, 0).rgb;			//sample level 0 of texture using texcoord
			
		// Get the spread comparison weight
		if (i < 24) {
			spreadCmp = saturate(3.0f * presortSample.r / coc - 2.0f);
		}
		else if (i < 39) {
			spreadCmp = saturate(3.0f * presortSample.r / coc - 1.0f);
		}
		else {
			spreadCmp = saturate(3.0f * presortSample.r / coc);
		}

		// Create the ray trace mask by checking the Z range sampled with the main pass kernel on foreground geometry
		closestForeground = min(closestForeground, gHalfResZBuffer.SampleLevel(gSampler, sampleForegroundCoord, 0).r);
		furthestBackground = max(furthestBackground, gHalfResZBuffer.SampleLevel(gSampler, sampleForegroundCoord, 0).r);
		foregroundSampled = foregroundSampled | (gHalfResZBuffer.SampleLevel(gSampler, sampleForegroundCoord, 0).r <= gDistanceToFocalPlane);

		// Accumulate color for background layer
		foreground += spreadCmp * presortSample.b * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0f);
		background += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0f);
		alphaSpreadCmpSum += spreadCmp * SampleAlpha(presortSample.r / 2.0f, gSinglePixelRadius);

	}
	
	if (gHalfResZBuffer[pixelPos].r > gDistanceToFocalPlane) {
		farFieldValue = float4( (background.rgb + foreground.rgb) / alphaSpreadCmpSum, 1.0);
		nearFieldValue = float4(0.0f, 0.0f, 0.0f, 1.0f);

	}
	else {
		farFieldValue = float4(0.0f, 0.0f, 0.0f, 1.0f);
		nearFieldValue = float4(0.0f, 0.0f, 0.0f, 1.0f);
	}

	MainPassBufOut.halfResFarField = farFieldValue;
	MainPassBufOut.halfResNearField = nearFieldValue;
	MainPassBufOut.rayTraceMask = float4((float)((furthestBackground - closestForeground) > EDGE_RANGE && foregroundSampled), 0.0f, 0.0f, 1.0f);

	return MainPassBufOut;
}