Texture2D<float4>   gZBuffer;

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
}

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_TARGET0
{
	uint2 pixelPos = (uint2)pos.xy;

	float max_coc = 0.0f;
	float nearest_Z = gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;

	for (int x = pixelPos.x * 20; x < pixelPos.x * 20 + 20; x++) {
		for (int y = pixelPos.y * 20; y < pixelPos.y * 20 + 20; y++) {
			if (gZBuffer[uint2(x,y)].r < nearest_Z) {
				nearest_Z = gZBuffer[uint2(x, y)].r;
			}
			if (COC(gZBuffer[uint2(x, y)].r) > max_coc) {
				max_coc = COC(gZBuffer[uint2(x, y)].r);
			}
		}
	}
	// TODO : Look into normalization issue ...

	float4 outColor = float4(max_coc, nearest_Z, 0.0f, 1.0f);

	return outColor;
}

float COC(float depth) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - depth) / (depth * (gDistanceToFocalPlane - gFocalLength)));
}