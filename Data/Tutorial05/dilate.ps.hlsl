Texture2D<float4>   gTiles;

cbuffer textureParametersCB
{
	int width;
	int height;
}

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_TARGET0
{
	uint2 pixelPos = (uint2)pos.xy;

	float max_coc = 0.0f;
	float nearest_Z = gTiles[uint2(pixelPos.x, pixelPos.y)].g;
	int start_x = max(pixelPos.x - 1, 0);
	int stop_x = min(pixelPos.x + 1, width - 1);
	int start_y = max(pixelPos.y - 1, 0);
	int stop_y = min(pixelPos.y + 1, height - 1);

	for (int i = start_x; i < stop_x + 1; i++) {
		for (int j = start_y; j < stop_y + 1; j++) {
			if (gTiles[uint2(i, j)].r > max_coc) {
				max_coc = gTiles[uint2(i, j)].r;
			}
			if (gTiles[uint2(i, j)].g < nearest_Z) {
				nearest_Z = gTiles[uint2(i, j)].g;
			}
		}
	}

	return float4(max_coc, nearest_Z, 0.0f, 1.0f);
}