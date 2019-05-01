static const float EDGE_RANGE = 0.01f;
static const float NORM_RANGE = 0.1f;

Texture2D<float4>   gGBuffer;

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
	float closestZForeground = gGBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;
	float furthestZForeground = gGBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].r;

	/*try something with normals*/
	float3 minNorm = gGBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].gba;
	float3 maxNorm = gGBuffer[uint2(pixelPos.x * 20, pixelPos.y * 20)].gba;

	for (int x = pixelPos.x * 20; x < pixelPos.x * 20 + 20; x++) {
		for (int y = pixelPos.y * 20; y < pixelPos.y * 20 + 20; y++) {

			nearestBackgroundZ += (gGBuffer[uint2(x, y)].r > gDistanceToFocalPlane)
				* ((nearestBackgroundZ > 0.0f && gGBuffer[uint2(x, y)].r < nearestBackgroundZ)
				* (gGBuffer[uint2(x, y)].r - nearestBackgroundZ)
				+ (nearestBackgroundZ == 0.0f)
				* (gGBuffer[uint2(x, y)].r));

			nearestForegroundZ += (gGBuffer[uint2(x, y)].r <= gDistanceToFocalPlane)
				* ((nearestForegroundZ > 0.0f && gGBuffer[uint2(x, y)].r < nearestForegroundZ)
				* (gGBuffer[uint2(x, y)].r - nearestForegroundZ)
				+ (nearestForegroundZ == 0.0f)
				* (gGBuffer[uint2(x, y)].r));

			maxBackgroundCOC = max(maxBackgroundCOC, COC(gGBuffer[uint2(x, y)].r) * (gGBuffer[uint2(x, y)].r > gDistanceToFocalPlane));
			maxForegroundCOC = max(maxForegroundCOC, COC(gGBuffer[uint2(x, y)].r) * (gGBuffer[uint2(x, y)].r <= gDistanceToFocalPlane));
			
			closestZForeground = min(closestZForeground, gGBuffer[uint2(x, y)].r);
			furthestZForeground = max(furthestZForeground, gGBuffer[uint2(x, y)].r);
			foregroundSampled = foregroundSampled | (gGBuffer[uint2(x, y)].r <= gDistanceToFocalPlane);

			minNorm = float3(min(minNorm.r, gGBuffer[uint2(x, y)].g), min(minNorm.g, gGBuffer[uint2(x, y)].b), min(minNorm.b, gGBuffer[uint2(x, y)].a));
			maxNorm = float3(max(maxNorm.r, gGBuffer[uint2(x, y)].g), max(maxNorm.g, gGBuffer[uint2(x, y)].b), max(maxNorm.b, gGBuffer[uint2(x, y)].a));

		}
	}

	// Pack in one texture (max COC background, nearest Z in tile background, max COC foreground, nearest Z in tile foreground)
	TilePassOutput.Tiles = float4(maxBackgroundCOC, nearestBackgroundZ, maxForegroundCOC, nearestForegroundZ);
	
	// Decide to raytrace or not if foreground edge is deep enough
	//TODO : implement proper gradient computation of normals to estimate 'variance' of normals, current implementation is too sensitive to outliers
	bool tileToBeRaytraced = (length(maxNorm - minNorm) > NORM_RANGE) && foregroundSampled;
	TilePassOutput.EdgeMask = float4((float)(tileToBeRaytraced), length(maxNorm - minNorm) * (float)tileToBeRaytraced, 0.0f, 1.0f);
	return TilePassOutput;
}

/*
COC diameter in pixels
*/
float COC(float z) {
	return abs(gAperture * gFocalLength * (gDistanceToFocalPlane - z) / (z * (gDistanceToFocalPlane - gFocalLength)))  * gTextureWidth / gSensorWidth;
}