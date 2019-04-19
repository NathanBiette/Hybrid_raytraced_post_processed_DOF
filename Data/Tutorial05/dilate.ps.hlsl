Texture2D<float4>   gTiles;
Texture2D<float4>   gRaytraceTiles;

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

	float max_coc = 0.0f;
	float max_coc_RT = 0.0f;
	float nearest_Z = 0.0f;
	bool raytraceTile = false;

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

	//Iterate through 3x3 neighbourhood and find nearest Z in tile in neighbourhood

	for (int i = start_x; i < stop_x + 1; i++) {
		for (int j = start_y; j < stop_y + 1; j++) {
			max_coc = max(max_coc, gTiles[uint2(i, j)].r);
			max_coc_RT = max(max_coc_RT, gRaytraceTiles[uint2(i, j)].g);
			nearest_Z += (gTiles[uint2(i, j)].g > 0.0f) * ((gTiles[uint2(i, j)].g - nearest_Z) * (nearest_Z > 0.0f && gTiles[uint2(i, j)].g < nearest_Z) + gTiles[uint2(i, j)].g * (nearest_Z == 0.0f));
			raytraceTile = raytraceTile || gRaytraceTiles[uint2(i, j)].r > 0.0f;
		}
	}
	DilatePassOutput.dilatedTiles = float4(max_coc, nearest_Z, 0.0f, 1.0f);
	//DilatePassOutput.raytraceMask = gRaytraceTiles[pixelPos].r < distToFocusPlane ? 1.0f : 0.0f;
	DilatePassOutput.raytraceMask = float4(raytraceTile, max_coc_RT, 0.0f, 1.0f);
	return DilatePassOutput;
}