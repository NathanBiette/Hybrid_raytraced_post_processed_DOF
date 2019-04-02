static const float BLENDING_TWEAK = 3.0f;

Texture2D<float4>   gZBuffer;
Texture2D<float4>   gFarField;
Texture2D<float4>   gNearField;
Texture2D<float4>   gRTFarField;
Texture2D<float4>   gFullResColor;

SamplerState gSampler;

struct PS_OUTPUT
{
	float4 finalImage    : SV_Target0;
};


cbuffer cameraParametersCB
{
	float gFarFocusZoneRange;
	float gNearFocusZoneRange;
	float gFarFieldFocusLimit;
	float gNearFieldFocusLimit;
	float gTextureWidth;
	float gTextureHeight;
	float gDistFocusPlane;
	//float gSinglePixelRadius;
}

/*
Based on
Implementing Median Filters in XC4000E FPGAs
Jhon L. Smith
http://users.utcluj.ro/~baruch/media/resources/Image/xl23_16.pdf
*/
float4 Median9(vector<float,4>[9] samples) {
	float4 values[30];
	values[29] = min(samples[7], samples[8]);
	values[28] = max(samples[7], samples[8]);
	values[27] = max(values[29], samples[6]);
	values[26] = min(samples[4], samples[5]);
	values[25] = max(samples[4], samples[5]);
	values[24] = max(values[26], samples[3]);
	values[23] = min(samples[1], samples[2]);
	values[22] = max(samples[1], samples[2]);
	values[21] = max(values[23], samples[0]);
	values[19] = min(values[26], samples[3]);
	values[18] = min(values[23], samples[0]);
	values[17] = max(values[27], values[28]);
	values[16] = max(values[24], values[25]);
	values[20] = min(values[16], values[17]);
	values[15] = min(values[27], values[28]);
	values[14] = max(values[21], values[22]);
	values[13] = min(values[25], values[24]);
	values[12] = min(values[29], samples[6]);
	values[11] = min(values[21], values[22]);
	values[10] = max(values[18], values[19]);
	values[9] = min(values[13], values[15]);
	values[8] = max(values[13], values[15]);
	values[7] = max(values[9], values[11]);
	values[6] = min(values[14], values[20]);
	values[5] = min(values[7], values[8]);
	values[4] = min(values[5], values[6]);
	values[3] = max(values[10], values[12]);
	values[2] = max(values[5], values[6]);
	values[1] = max(values[3], values[4]);
	values[0] = min(values[1], values[2]);
	return values[0];
}

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT compositePassBufOut;
	float4 farFieldSamples[9];
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			farFieldSamples[i*3 + j] = gFarField.SampleLevel(gSampler, float2( (pos.x + 2.0f * ((float)i - 1.0f))/gTextureWidth, (pos.y + 2.0f * ((float)j - 1.0f))/gTextureHeight), 0);
		}
	}
	float4 farFieldColor = Median9(farFieldSamples);
	float4 focusColor = gFullResColor.SampleLevel(gSampler, texC, 0);
	float Z = gZBuffer.SampleLevel(gSampler, texC, 0).r;
	float farBlendFactor = saturate((Z - gFarFieldFocusLimit) / (BLENDING_TWEAK * gFarFocusZoneRange));
	//float nearBlendFactor = saturate((gNearFieldFocusLimit - Z) / (BLENDING_TWEAK * gNearFocusZoneRange));


	// far field -> blend between focus and not far 
	if (Z > gFarFieldFocusLimit) {
		//compositePassBufOut.finalImage = float4(farFieldColor.rgb, 1.0f);
		compositePassBufOut.finalImage = float4(farBlendFactor * farFieldColor.rgb + (1.0f - farBlendFactor) * focusColor.rgb, 1.0f);
	}// between focus plane and end of focus area -> focused sharp image
	else if(Z > gDistFocusPlane){
		compositePassBufOut.finalImage = float4(focusColor.rgb, 1.0f);
	}// in front of focus plane -> 
	else {
		compositePassBufOut.finalImage = gRTFarField.SampleLevel(gSampler, texC, 0);
	}


	return compositePassBufOut;
}

