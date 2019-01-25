Texture2D<float4>   gZBuffer;
//Texture2D<float4>   gTileBuffer;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_TARGET0
{
	uint2 pixelPos = (uint2)pos.xy;
	float4 curColor = gZBuffer[pixelPos];
	//gTileBuffer[pixelPos] = curColor;
	float4 test = float4(0.5f, 0.5f, 0.0f, 0.0f);
	return curColor;
}