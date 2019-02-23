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
float depth(float Z) {
	return gNear + Z * (gFar - gNear);
}

float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - depth(z)) / (depth(z) * (gDistanceToFocalPlane - gFocalLength)));
}

float2 DepthCmp2(float pixelDepth, float closestDepthInTile, float depthRange) {
	float d = (depth(pixelDepth) - depth(closestDepthInTile)) / depthRange;
	float2 depthCmp;
	depthCmp.x = smoothstep(0.0f, 1.0f, d);
	depthCmp.y = 1.0f - depthCmp.x;
	return depthCmp;
}

float SampleAlpha(float coc, float singlePixelRadius) {
	//samplecoc is radius of coc in pixels
	return min(1.0f / (PI * coc * coc), 1.0f / (PI * singlePixelRadius * singlePixelRadius));
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
	
	DownPresortBufOut.presortBuffer = float4(coc, sampleAlpha * depthCmp2.x, sampleAlpha * depthCmp2.y, 0.0f);
	
	//####################### downsample pass #######################################################

	float4 halfResColor = gFrameColor.SampleLevel(gSampler, texC, 0);
	float* sampleZ = float[9];
	float sumZ = depth(Z); //the Z from the downsample part, of target output
	float3* sampleColor = float3[9];

	
	for (int i = 0; i < 9; i++) {
		//find sample location while scaling filter width with coc size 
		sampleColor[i] = float3(0.0f, 0.0f, 0.0f);
		float2 sampleLocation;
		sampleLocation.x = ((float)pixelPos.x * 2.0f + coc / 2.0f * cos(2.0f * PI* (float)i / 9.0f)) / gTextureWidth;
		sampleLocation.y = (float)pixelPos.y * 2.0f + coc / 2.0f * sin(2.0f * PI* (float)i / 9.0f) / gTextureHeight;
		


		//------------TODO fix the case of sampling on border with possible 0 values for the gather4...
		sampleZ[i] = depth(min(gZBuffer.Gather(Z_buffer, sampleLocation)));
		sampleColor[i] = gFrameColor.SampleLevel(gSampler, sampleLocation, 0);
		sumZ += sampleZ[i];
		//--------------
	}
	
	//float3 sumColor = halfResColor * Z / sumZ / (1 + (1 - STRENGTH_TWEAK) * luma(halfResColor));

	
	
	



	DownPresortBufOut.halfResColor = halfResColor;
	
	
	return DownPresortBufOut;
}



