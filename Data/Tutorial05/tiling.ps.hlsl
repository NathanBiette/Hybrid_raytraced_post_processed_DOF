Texture2D<float4>   gZBuffer;

cbuffer cameraParametersCB
{
	float gFocalLength;
	float gDistanceToFocalPlane;
	float gAperture;
	float gSensorWidth;
	float gTextureWidth;
}

struct PS_OUTPUT
{
	float4 Tiles			: SV_Target0;
	float4 RaytraceTiles    : SV_Target1;
};


PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT TilePassOutput;
	uint2 pixelPos = (uint2)pos.xy;

	float maxBackgroundCOC = 0.0f;
	float maxForegroundCOC = 0.0f;
	float nearestBackgroundZ = 0.0f;
	float nearestForegroundZ = 0.0f;

	bool nearInTile = false;

	for (int x = pixelPos.x * 20; x < pixelPos.x * 20 + 20; x++) {
		for (int y = pixelPos.y * 20; y < pixelPos.y * 20 + 20; y++) {

			nearestBackgroundZ += (gZBuffer[uint2(x, y)].r > gDistanceToFocalPlane)
				* ((nearestBackgroundZ > 0.0f && gZBuffer[uint2(x, y)].r < nearestBackgroundZ)
				* (gZBuffer[uint2(x, y)].r - nearestBackgroundZ)
				+ (nearestBackgroundZ == 0.0f)
				* (gZBuffer[uint2(x, y)].r));

			nearestForegroundZ += (gZBuffer[uint2(x, y)].r <= gDistanceToFocalPlane)
				* ((nearestForegroundZ > 0.0f && gZBuffer[uint2(x, y)].r < nearestForegroundZ)
				* (gZBuffer[uint2(x, y)].r - nearestForegroundZ)
				+ (nearestForegroundZ == 0.0f)
				* (gZBuffer[uint2(x, y)].r));

			maxBackgroundCOC = max(maxBackgroundCOC, COC(gZBuffer[uint2(x, y)].r) * (gZBuffer[uint2(x, y)].r > gDistanceToFocalPlane));
			maxForegroundCOC = max(maxForegroundCOC, COC(gZBuffer[uint2(x, y)].r) * (gZBuffer[uint2(x, y)].r <= gDistanceToFocalPlane));
			
			// Check if at least one sample is in foreground for raytrace mask
			nearInTile = nearInTile || gZBuffer[uint2(x, y)].r < gDistanceToFocalPlane;
		}
	}

	// Pack in one texture (max COC background, nearest Z in tile background, max COC foreground, nearest Z in tile foreground)
	TilePassOutput.Tiles = float4(maxBackgroundCOC, nearestBackgroundZ, maxForegroundCOC, nearestForegroundZ);
	TilePassOutput.RaytraceTiles = float4((float)nearInTile, maxForegroundCOC, 0.0f, 1.0f);
	return TilePassOutput;
}

//COC diameter in pixels
float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength)))  * gTextureWidth / gSensorWidth;
}