Texture2D<float4>   gZBuffer;

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
	float gSensorWidth;
	float gTextureWidth;
}

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_TARGET0
{
	uint2 pixelPos = (uint2)pos.xy;

	float max_coc = 0.0f;
	//float nearest_Z = gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;
	//float nearestZFar = gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r * (gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r > gDistanceToFocalPlane);
	float nearestZFar = 0.0f;

	for (int x = pixelPos.x * 20; x < pixelPos.x * 20 + 20; x++) {
		for (int y = pixelPos.y * 20; y < pixelPos.y * 20 + 20; y++) {
			nearestZFar += (gZBuffer[uint2(x, y)].r > gDistanceToFocalPlane) 
				* ((nearestZFar > 0.0f 
					&& gZBuffer[uint2(x, y)].r < nearestZFar)
				* (gZBuffer[uint2(x, y)].r - nearestZFar)
				+ (nearestZFar == 0.0f)
				* (gZBuffer[uint2(x, y)].r - nearestZFar));
			max_coc = max(max_coc, COC(gZBuffer[uint2(x, y)].r) * (gZBuffer[uint2(x, y)].r > gDistanceToFocalPlane));
		}
	}

	float4 outColor = float4(max_coc, nearestZFar, 0.0f, 1.0f);

	return outColor;
}

//COC diameter in pixels
float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength)))  * gTextureWidth / gSensorWidth;
}