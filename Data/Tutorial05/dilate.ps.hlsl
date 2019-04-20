Texture2D<float4>   gTiles;
Texture2D<float4>   gEdgeMask;

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
	float raytraceTile = 0.0f;
	float closestZEdgeLimit = 0.0f;

	// Handle image border during sampling
	int startX = 0 + (pixelPos.x > 0) * (pixelPos.x - 1);
	int startY = 0 + (pixelPos.y > 0) * (pixelPos.y - 1);
	int stopX = min(pixelPos.x + 1, width - 1);
	int stopY = min(pixelPos.y + 1, height - 1);

	// Iterate through 3x3 neighbourhood and find nearest Z in tile in neighbourhood
	for (int i = startX; i < stopX + 1; i++) {
		for (int j = startY; j < stopY + 1; j++) {

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
			
			raytraceTile = max(raytraceTile, gEdgeMask[uint2(i, j)].r);

			closestZEdgeLimit += (gEdgeMask[uint2(i, j)].g > 0.0f)
				* ((gEdgeMask[uint2(i, j)].g - closestZEdgeLimit)
				* (closestZEdgeLimit > 0.0f && gEdgeMask[uint2(i, j)].g < closestZEdgeLimit)
				+ gEdgeMask[uint2(i, j)].g * (closestZEdgeLimit == 0.0f));
		}
	}

	DilatePassOutput.dilatedTiles = float4(maxBackgroundCOC, nearestBackgroundZ, maxForegroundCOC, nearestForegroundZ);
	//DilatePassOutput.raytraceMask = float4(raytraceTile, closestZEdgeLimit, 0.0f, 1.0f);
	DilatePassOutput.raytraceMask = float4(nearestForegroundZ, closestZEdgeLimit, 0.0f, 1.0f);
	return DilatePassOutput;
}