static const float PI = 3.14159265f;

Texture2D<float4>   gDilate;
Texture2D<float4>   gZBuffer;
Texture2D<float4>   gFrameColor;

SamplerState gSampler;

/*
SamplerState linearSampler
{
	Filter = MIN_MAG_MIP_LINEAR;
	//AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
	//AddressU = Wrap;
	//AddressV = Wrap;
};
*/

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
	float gDepthRange;
	float gSinglePixelRadius;
	float gTextureWidth;
	float gTextureHeight;
	float gNear;
	float gFar;
	float gStrengthTweak;
}

/*
cbuffer textureParametersCB
{
	int gTextureWidth;
	int gTextureHeight;
}*/

struct PS_OUTPUT

{
	float4 halfResColor    : SV_Target0;  // Our color goes in color buffer 0
	float4 presortBuffer    : SV_Target1;  // Our color goes in buffer 1
};


//################################## Helper functions ##############################

float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength)));
}

float2 DepthCmp2(float pixelDepth, float closestDepthInTile, float depthRange) {
	float d = (pixelDepth - closestDepthInTile) / depthRange;
	float2 depthCmp;
	depthCmp.x = smoothstep(0.0f, 1.0f, d);
	depthCmp.y = 1.0f - depthCmp.x;
	return depthCmp;
}

float SampleAlpha(float coc, float singlePixelRadius) {
	//samplecoc is radius of coc in pixels
	return min(1.0f / (PI * coc * coc), 1.0f / (PI * singlePixelRadius * singlePixelRadius));
}

//supposing RGB color spaces use the ITU-R BT.709 primaries
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

	//TODO fix displacement error from tiling passes -> seen in presort result

	//####################### presort pass #######################################################
	float coc = COC(Z);
	float2 depthCmp2 = DepthCmp2(Z, gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].g, gDepthRange);
	float sampleAlpha = SampleAlpha(coc / 2.0f, gSinglePixelRadius);
	
	DownPresortBufOut.presortBuffer = float4(coc, sampleAlpha * depthCmp2.x, sampleAlpha * depthCmp2.y, 0.0f);
	
	//####################### downsample pass #######################################################

	float4 halfResColor = gFrameColor.SampleLevel(gSampler, texC, 0);
	float sampleZ[9] = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};
	float sumZ = Z; //the Z from the downsample part, of target output
	float3 sampleColor[9];
	float4 Z4;
	
	for (int i = 0; i < 9; i++) {
		//find sample location while scaling filter width with coc size 
		sampleColor[i] = float3(0.0f, 0.0f, 0.0f);
		float2 sampleLocation;
		sampleLocation.x = ((float)pixelPos.x * 2.0f + coc / 2.0f * cos(2.0f * PI* (float)i / 9.0f)) / gTextureWidth;
		sampleLocation.y = (float)pixelPos.y * 2.0f + coc / 2.0f * sin(2.0f * PI* (float)i / 9.0f) / gTextureHeight;
		


		//Here as we are supposedly sampling the Z buffer with the border to 0 sampler, if we sample outside, the min Z = 0 and sample doesn't count anyway
		Z4 = gZBuffer.Gather(gSampler, sampleLocation);
		sampleZ[i] = min(min(min(Z4.r, Z4.g), Z4.b), Z4.a);
		sampleColor[i] = gFrameColor.SampleLevel(gSampler, sampleLocation, 0).rgb;
		sumZ += sampleZ[i];
	}

	float3 sumColor = halfResColor.rgb * Z / (sumZ * (1 + (1 - gStrengthTweak) * Luma(halfResColor.rgb)));

	for (int i = 0; i < 9; i++) {
		sumColor += sampleColor[i] * sampleZ[i] / (sumZ * (1 + (1 - gStrengthTweak) * Luma(sampleColor[i])));
	}
	
	DownPresortBufOut.halfResColor = float4(sumColor.r, sumColor.g, sumColor.b, 1.0f);
	//DownPresortBufOut.halfResColor = gZBuffer.Gather(gSampler, texC);


	/*
		if (Z > 100.0f) {
		DownPresortBufOut.halfResColor = float4(1.0f);
	}
	else if (Z > 50.0f) {
		DownPresortBufOut.halfResColor = float4(0.75f);
	}
	else if (Z > 10.0f) {
		DownPresortBufOut.halfResColor = float4(0.5f);
	}
	else if (Z > 5.0f) {
		DownPresortBufOut.halfResColor = float4(0.25f);
	}
	else if (Z > 1.0f) {
		DownPresortBufOut.halfResColor = float4(0.15f);
	}
	else {
		DownPresortBufOut.halfResColor = float4(1.0f,0.0f,1.0f,1.0f);
	}
	*/


	return DownPresortBufOut;
}



