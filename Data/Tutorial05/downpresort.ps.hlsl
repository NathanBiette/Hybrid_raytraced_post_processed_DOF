Texture2D<float4>   gDilate;
Texture2D<float4>   gZBuffer;
Texture2D<float4>   gFrameColor;

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
}

struct DownPresortBuffer
{
	float4 halfResColor    : SV_Target0;  // Our color goes in color buffer 0
	float4 presortBuffer    : SV_Target1;  // Our color goes in buffer 1
};

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	uint2 pixelPos = (uint2)pos.xy;
	DownPresortBuffer DownPresortBufOut;

	
	
	float Z = gZBuffer[uint2(x, y)].r;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			if (gZBuffer[uint2(x + i, y + j)].r > Z) {
				Z = gZBuffer[uint2(x + i, y + j)].r;
			}
		}
	}

	float coc = COC(Z);
	
	
	DownPresortBufOut.halfResColor =  /*to be filled*/;
	DownPresortBufOut.presortBuffer =  /*to be filled*/;
	
	return DownPresortBufOut;
}

float COC(float depth) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - depth) / (depth * (gDistanceToFocalPlane - gFocalLength)));
}

//TO WRITE PROPERLY
float2 DepthCmp2(float pixel_depth, float closest_depth_in_tile) {
	float d = DEPTH_RANGE_FOREGROUND_BACKGROUND * (pixel_depth - closest_depth_in_tile);
	float2 depthCmp;
	depthCmp.x = smoothstep(0.0, 1.0, d);
	depthCmp.y = 1 - depthCmp.x;
	return depthCmp;
}
