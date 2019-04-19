Texture2D<float4>   gTiles;

cbuffer textureParametersCB
{
	int width;
	int height;
	float distToFocusPlane;
}

struct PS_OUTPUT
{
	float4 dilatedTiles    : SV_Target0;
	float4 raytraceMask    : SV_Target1;
};

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT DilatePassOutput;
	uint2 pixelPos = (uint2)pos.xy;

	float maxBackgroundCOC = 0.0f;
	float maxForegroundCOC = 0.0f;
	float nearestBackgroundZ = 0.0f;
	float nearestForegroundZ = 0.0f;
	bool raytraceTile = false;

	// Handle image border during sampling
	int start_x = 0;
	int start_y = 0;
	if (pixelPos.x > 0) {
		start_x = pixelPos.x - 1;
	}
	if (pixelPos.y > 0) {
		start_y = pixelPos.y - 1;
	}
	int stop_x = min(pixelPos.x + 1, width - 1);
	int stop_y = min(pixelPos.y + 1, height - 1);

	// Iterate through 3x3 neighbourhood and find nearest Z in tile in neighbourhood
	for (int i = start_x; i < stop_x + 1; i++) {
		for (int j = start_y; j < stop_y + 1; j++) {

			maxBackgroundCOC = max(maxBackgroundCOC, gTiles[uint2(i, j)].r);
			maxForegroundCOC = max(maxForegroundCOC, gTiles[uint2(i, j)].b);

			nearestBackgroundZ += (gTiles[uint2(i, j)].g > 0.0f) 
				* ((gTiles[uint2(i, j)].g - nearestBackgroundZ) 
				* (nearestBackgroundZ > 0.0f && gTiles[uint2(i, j)].g < nearestBackgroundZ) 
				+ gTiles[uint2(i, j)].g * (nearestBackgroundZ == 0.0f));

			nearestForegroundZ += (gTiles[uint2(i, j)].a > 0.0f)
				* ((gTiles[uint2(i, j)].a - nearestForegroundZ)
				* (nearestForegroundZ > 0.0f && gTiles[uint2(i, j)].a < nearestForegroundZ)
				+ gTiles[uint2(i, j)].a * (nearestForegroundZ == 0.0f));

			//raytraceTile = raytraceTile || gRaytraceTiles[uint2(i, j)].r > 0.0f;
		}
	}

	DilatePassOutput.dilatedTiles = float4(maxBackgroundCOC, nearestBackgroundZ, maxForegroundCOC, nearestForegroundZ);
	DilatePassOutput.raytraceMask = float4(nearestForegroundZ, maxForegroundCOC, 0.0f, 1.0f);
	return DilatePassOutput;
}