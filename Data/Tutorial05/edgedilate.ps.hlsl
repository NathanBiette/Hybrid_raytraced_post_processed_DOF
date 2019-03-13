static const float EDGE_THRESHOLD = 0.5f;

Texture2D<float4>   gEdgeBuffer;

SamplerState gSampler;

static const float kernelX[8] = {
	1.0f,
	0.7071f,
	0.0f,
	-0.7071f,
	-1.0f,
	-0.7071f,
	0.0f,
	0.7071
};

static const float kernelY[8] = {
	0.0f,
	0.7071f,
	1.0f,
	0.7071f,
	0.0f,
	-0.7071f,
	-1.0f,
	-0.7071f
};

cbuffer cameraParametersCB
{
	float gTextureWidth;
	float gTextureHeight;
}

struct PS_OUTPUT
{
	float4 edgesDilated    : SV_Target0;
};

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT edgesDilatedBufOut;
	uint2 pixelPos = (uint2)pos.xy;
	float edgeMax = gEdgeBuffer[uint2(pixelPos.x, pixelPos.y)].r;

	for (int i = 0; i < 8; i++) {
			float2 coord = float2(10.0f * (pos.x + kernelX[i] * 2.0f) / gTextureWidth, 10.0f * (pos.y + kernelY[i] * 2.0f) / gTextureHeight);
			edgeMax = max(edgeMax, gEdgeBuffer.SampleLevel(gSampler, coord, 0).r);
		}
	float edgeIntensity = edgeMax > EDGE_THRESHOLD ? 1.0f : 0.0f;
	edgesDilatedBufOut.edgesDilated = float4(edgeIntensity, 0.0f, 0.0f, 1.0f);

	return edgesDilatedBufOut;
}