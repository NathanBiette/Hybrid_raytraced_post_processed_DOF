static const float EDGE_THRESHOLD = 0.5f;

Texture2D<float4>   gHalfResZBuffer;

cbuffer cameraParametersCB
{
	float gDistanceToFocalPlane;
}

static const float sobelWeights[25] = {
	-0.25f,
	-0.2f,
	0.0f,
	0.2f,
	0.25f,
	-0.4f,
	-0.5f,
	0.0f,
	0.5f,
	0.4f,
	-0.5f,
	-1.0f,
	0.0f,
	1.0f,
	0.5f,
	-0.4f,
	-0.5f,
	0.0f,
	0.5f,
	0.4f,
	-0.25f,
	-0.2f,
	0.0f,
	0.2f,
	0.25f
};

struct PS_OUTPUT
{
	float4 edges    : SV_Target0;
};

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT edgesBufOut;
	uint2 pixelPos = (uint2)pos.xy;
	float sumX = 0.0f;
	float sumY = 0.0f;
	float minZ = gHalfResZBuffer[uint2(pixelPos.x * 5, pixelPos.y * 5)].r;

	for (int i = 0; i < 5; i++) {
		for (int j = 0; j < 5; j++) {
			sumX += sobelWeights[5 * j + i] * gHalfResZBuffer[uint2(pixelPos.x * 5 + i, pixelPos.y * 5 + j)].r;
			sumY += sobelWeights[5 * i + j] * gHalfResZBuffer[uint2(pixelPos.x * 5 + i, pixelPos.y * 5 + j)].r;
			minZ = min(minZ, gHalfResZBuffer[uint2(pixelPos.x * 5 + i, pixelPos.y * 5 + j)].r);
		}
	}

	float edgeIntensity = minZ < gDistanceToFocalPlane ? abs(sumX) + abs(sumY) : 0.0f;
	float edge = edgeIntensity > EDGE_THRESHOLD ? 1.0f : 0.0f;
	edgesBufOut.edges = float4(edge, 0.0f, 0.0f, 1.0f);
	return edgesBufOut;
}