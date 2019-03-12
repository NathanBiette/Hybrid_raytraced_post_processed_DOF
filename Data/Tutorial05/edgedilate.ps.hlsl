Texture2D<float4>   gEdgeBuffer;

struct PS_OUTPUT
{
	float4 edgesDilated    : SV_Target0;
};

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT edgesDilatedBufOut;
	/*TODO get the circular or something else filter here and dilate the edges */

	return edgesDilatedBufOut;
}