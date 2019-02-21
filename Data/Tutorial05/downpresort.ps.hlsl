static const float PI = 3.14159265f;

Texture2D<float4>   gDilate;
Texture2D<float4>   gZBuffer;
Texture2D<float4>   gFrameColor;

SamplerState linearSampler
{
	Filter = MIN_MAG_MIP_LINEAR;
	//AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
	//AddressU = Wrap;
	//AddressV = Wrap;
}

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
	float gDepthRange;
	float gSinglePixelRadius;
}

cbuffer textureParametersCB
{
	int gTextureWidth;
	int gTextureHeight;
}

struct DownPresortBuffer
{
	float4 halfResColor    : SV_Target0;  // Our color goes in color buffer 0
	float4 presortBuffer    : SV_Target1;  // Our color goes in buffer 1
};


//################################## Helper functions ##############################
float COC(float depth) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - depth) / (depth * (gDistanceToFocalPlane - gFocalLength)));
}

float2 DepthCmp2(float pixelDepth, float closestDepthInTile, float depthRange) {
	float d = depthRange * (pixelDepth - closestDepthInTile);
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

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	uint2 pixelPos = (uint2)pos.xy;
	DownPresortBuffer DownPresortBufOut;

	float Z = gZBuffer[uint2(pixelPos.x, pixelPos.y)].r;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			if (gZBuffer[uint2(pixelPos.x + i, pixelPos.y + j)].r > Z) {
				Z = gZBuffer[uint2(pixelPos.x + i, pixelPos.y + j)].r;
			}
		}
	}

	//####################### presort pass #######################################################
	float coc = COC(Z);
	float depthCmp2 = DepthCmp2(Z, gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)], gDepthRange);
	float sampleAlpha = SampleAlpha(coc / 2.0f, gSinglePixelRadius);
	
	DownPresortBufOut.presortBuffer = float4(coc, sampleAlpha * depthCmp2.x, sampleAlpha * depthCmp2.y, 0.0f);
	
	//####################### downsample pass #######################################################

	float4 halfResColor = gFrameColor.SampleLevel(linearSampler, texC, 0);
	float* sampleZ = float[9];
	float sumZ = Z; //the Z from the downsample part, of target output
	float3* sampleColor = float3[9];

	/*
	for (int i = 0; i < 9; i++) {
		//find sample location while scaling filter width with coc size 
		sampleColor[i] = float3(0.0f, 0.0f, 0.0f);
		float2 sampleLocation;
		sampleLocation.x = (float)pixelPos.x * 2.0f + coc / 2.0f * cos(2.0f * PI* (float)i / 9.0f);
		sampleLocation.y = (float)pixelPos.y * 2.0f + coc / 2.0f * sin(2.0f * PI* (float)i / 9.0f);
		if(sampleLocation.x >= 0.0f && sampleLocation.x < gTextureWidth)

		//------------
		sample_Z[i] = min(gather4(Z_buffer, sample_x, sample_y));
		sample_color[i] = fetch(full_res_buffer, sample_x, sample_y); // bilinear fetch    
		sum_z += sample_z[i];
		//--------------
	}
	
	*/
	



	DownPresortBufOut.halfResColor = halfResColor;
	
	
	return DownPresortBufOut;
}



