static const float EDGE_RANGE = 0.10f;

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
	float4 EdgeMask			: SV_Target1;
};


PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT TilePassOutput;
	uint2 pixelPos = (uint2)pos.xy;

	float maxBackgroundCOC = 0.0f;
	float maxForegroundCOC = 0.0f;
	float nearestBackgroundZ = 0.0f;
	float nearestForegroundZ = 0.0f;

	bool foregroundSampled = false;
	float closestZForeground = gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;
	float furthestZForeground = gZBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;

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
			
			closestZForeground = min(closestZForeground, gZBuffer[uint2(x, y)].r);
			furthestZForeground = max(furthestZForeground, gZBuffer[uint2(x, y)].r);
			foregroundSampled = foregroundSampled | (gZBuffer[uint2(x, y)].r <= gDistanceToFocalPlane);

		}
	}

	// Pack in one texture (max COC background, nearest Z in tile background, max COC foreground, nearest Z in tile foreground)
	TilePassOutput.Tiles = float4(maxBackgroundCOC, nearestBackgroundZ, maxForegroundCOC, nearestForegroundZ);
	TilePassOutput.EdgeMask = float4((float)((furthestZForeground - closestZForeground) > EDGE_RANGE && foregroundSampled), 0.0f, 0.0f, 1.0f);
	return TilePassOutput;
}

/*
COC diameter in pixels
*/
float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength)))  * gTextureWidth / gSensorWidth;
}