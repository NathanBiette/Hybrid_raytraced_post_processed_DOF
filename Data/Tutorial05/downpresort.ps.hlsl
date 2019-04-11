static const float PI = 3.14159265f;
static const float Z_RANGE = 0.03f; //standard deviation of Z used if Gaussian weights computation

Texture2D<float4>   gDilate;
Texture2D<float4>   gZBuffer;
Texture2D<float4>   gFrameColor;

SamplerState gSampler;

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
	float gSensorWidth;
	float gDepthRange;
	float gSinglePixelRadius;
	float gTextureWidth;
	float gTextureHeight;
	float gNear;
	float gFar;
	float gStrengthTweak;
}

struct PS_OUTPUT

{
	float4 halfResColor    : SV_Target0;
	float4 presortBuffer    : SV_Target1;  
	float4 halfResZBuffer	: SV_Target2;
};


//################################## Helper functions ##############################
/*
COC size reminder

float mFNumber = 2.0f;                  // f number (typeless) = F/A (A = aperture)
float mFocalLength = 0.05f;              // here we take 50mm of focal length
float mDistFocalPlane = 1.0f;				// What is our distance to focal plane (meaning where we focus on, 1m here)
float mAperture = mFocalLength / mFNumber = 0.025;

for an object at 0.5 m coc = 0.025 * 0.05 * (1.0 - 0.5) / (0.5 * (1 - 0.05)) = 0.001315 m = 1.315 mm
coc in pixel = 0.001315 * 1920 / 0.036 = 70.1754

*/

/*
Returns the COC diameter in pixels
*/
float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength))) * gTextureWidth / gSensorWidth;
}

/*
Weights sample contribution to relative foreground and background layers
*/
float2 DepthCmp2(float pixelDepth, float closestDepthInTile, float depthRange) {
	float d = (pixelDepth - closestDepthInTile) / depthRange;
	float2 depthCmp;
	depthCmp.x = smoothstep(0.0f, 1.0f, d);
	depthCmp.y = 1.0f - depthCmp.x;
	return depthCmp;
}

/*
Returns the alpha of a splatted pixel according to coc size
*/
float SampleAlpha(float cocRadius, float singlePixelRadius) {
	//samplecoc is radius of coc in pixels
	return min(1.0f / (PI * cocRadius * cocRadius), 1.0f / (PI * singlePixelRadius * singlePixelRadius));
	//return min(1.0f, (singlePixelRadius * singlePixelRadius) / (cocRadius * cocRadius));
}

/*
Gaussian function
*/
float Gaussian(float mean, float standardDeviation, float value) {
	return exp(-0.5f * (value - mean) * (value - mean) / (standardDeviation * standardDeviation)) / (2.506628f * standardDeviation);
}
/*
Returns the luma of a color supposing RGB color spaces use the ITU-R BT.709 primaries
*/
float Luma(float3 color) {
	return 0.2126f*color.r + 0.7152f*color.g + 0.0722f*color.b;
}
//##################################################################################

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	uint2 pixelPos = (uint2)pos.xy;
	PS_OUTPUT DownPresortBufOut;

	float Z = gZBuffer[uint2(pixelPos.x * 2, pixelPos.y * 2)].r;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			if (gZBuffer[uint2(pixelPos.x * 2 + i, pixelPos.y * 2 + j)].r > Z) {
				Z = gZBuffer[uint2(pixelPos.x * 2 + i, pixelPos.y * 2 + j)].r;
			}
		}
	}

	//####################### presort pass #######################################################
	float coc = COC(Z);
	float2 depthCmp2 = DepthCmp2(Z, gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].g, gDepthRange);
	float sampleAlpha = SampleAlpha(coc / 2.0f, gSinglePixelRadius);
	
	/*
	Store COC of pixel, alpha background, alpha foreground 
	*/
	float foregroundAlphaTweak = 1.0f;
	DownPresortBufOut.presortBuffer = float4(coc, sampleAlpha * depthCmp2.x, foregroundAlphaTweak * sampleAlpha * depthCmp2.y, 0.0f);
	
	//####################### downsample pass #######################################################

	float4 halfResColor = gFrameColor.SampleLevel(gSampler, texC, 0);
	float2 sampleLocation = float2(0.0f);
	float sampleZ[8] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
	float3 sampleColor[9];
	float4 Z4;

	for (int i = 0; i < 8; i++) {
		//find sample location while scaling filter width with coc size 
		sampleColor[i] = float3(0.0f, 0.0f, 0.0f);
		// to get location of the sample : take the center of current pixel, get the rigth angle according to index of sample on unit circle and get the rigth distance to center pixel
		// the distance to pixel is the COC (diameter) size / 12 (coc /(2*6) 2 is to get the radius, 6 is to fill in the space between main filter samples (3 circles of sample, 49taps)) 
		sampleLocation.x = ((float)pixelPos.x * 2.0f + coc / 12.0f * cos(2.0f * PI* (float)i / 8.0f)) / gTextureWidth;
		sampleLocation.y = ((float)pixelPos.y * 2.0f + coc / 12.0f * sin(2.0f * PI* (float)i / 8.0f)) / gTextureHeight;

		/*
		Here as we are supposedly sampling the Z buffer with the border to 0 sampler, 
		if we sample outside, the min Z = 0 and sample doesn't count anyway
		Gather4 takes the 4 red value used in bilinear sampling and output float4(r1,r2,r3,r4)
		*/
		Z4 = gZBuffer.Gather(gSampler, sampleLocation);
		sampleZ[i] = min(min(min(Z4.r, Z4.g), Z4.b), Z4.a);
		sampleColor[i] = gFrameColor.SampleLevel(gSampler, sampleLocation, 0).rgb;
	}

	float3 sumColor = float3(0.0f);
	float sumWeigth = 0.0f;
	float weigth = 0.0f;

	for (int i = 0; i < 8; i++) {
		weigth = abs(Z - sampleZ[i]) * Gaussian(0.0f , Z_RANGE, abs(Z - sampleZ[i]));
		sumColor += sampleColor[i] * weigth;
		sumWeigth += weigth;
	}

	/*
	This is to avoid using a null sum of weights in focus area
	*/
	if (sumWeigth > 0.001f) {
		halfResColor.rgb = halfResColor.rgb / 2.0f + sumColor / (sumWeigth * 2.0f);
	}
	
	/*
	Store the haflres color and Z
	*/
	DownPresortBufOut.halfResColor = float4(halfResColor.rgb, 1.0f);
	DownPresortBufOut.halfResZBuffer = float4(Z, 0.0f, 0.0f, 0.0f);
	
	//#################################################################################################

	return DownPresortBufOut;
}



