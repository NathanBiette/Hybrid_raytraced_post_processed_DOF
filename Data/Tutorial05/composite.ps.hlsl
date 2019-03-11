Texture2D<float4>   gZBuffer;

SamplerState gSampler;

struct PS_OUTPUT
{
	float4 finalImage    : SV_Target0;
};

/*
cbuffer cameraParametersCB
{
	float gOffset;
	float gDistanceToFocalPlane;
	float gTextureWidth;
	float gTextureHeight;
	float gSinglePixelRadius;
}
*/

float4 Median9(vector<float,4>[9] samples) {
	/*TODO implement the network of min / max nicely end test it with dummy values*/
	return float4(0.0f);
}

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT compositePassBufOut;
	float4 farFieldsamples[9];
	samples[0] = float4(0.0f);
	samples[1] = float4(0.0f);
	samples[2] = float4(0.5f);
	samples[3] = float4(0.0f);

	compositePassBufOut.finalImage = Median9(samples);
	return compositePassBufOut;
}

