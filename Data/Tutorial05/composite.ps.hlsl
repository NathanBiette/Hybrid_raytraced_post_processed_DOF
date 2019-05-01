static const float BLENDING_TWEAK = 3.0f;
static const float NEAR_RT_BLEND_TWEAK = 0.2f;
static const float FAR_RT_BLEND_TWEAK = 2.0f;

Texture2D<float4>   gGBuffer;
Texture2D<float4>   gFarField;
Texture2D<float4>   gNearField;
Texture2D<float4>   gRTNearField;
Texture2D<float4>   gRTFarField;
Texture2D<float4>   gRTMask;
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
	bool raytraced = gRTMask.SampleLevel(gSampler, texC, 0).r > 0.0f;
	float4 backgroundPPSamples[9];
	float4 foregroundPPSamples[9];
	float4 foregroundRTSamples[9];

	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			backgroundPPSamples[i*3 + j] = gFarField.SampleLevel(gSampler, float2( (pos.x + 2.0f * ((float)i - 1.0f))/gTextureWidth, (pos.y + 2.0f * ((float)j - 1.0f))/gTextureHeight), 0);
			foregroundPPSamples[i*3 + j] = gNearField.SampleLevel(gSampler, float2( (pos.x + 2.0f * ((float)i - 1.0f))/gTextureWidth, (pos.y + 2.0f * ((float)j - 1.0f))/gTextureHeight), 0);
			if (raytraced) {
				foregroundRTSamples[i * 3 + j] = gRTNearField.SampleLevel(gSampler, float2((pos.x + 2.0f * ((float)i - 1.0f)) / gTextureWidth, (pos.y + 2.0f * ((float)j - 1.0f)) / gTextureHeight), 0);
			}
		}
	}
	float4 backgroundPPColor = Median9(backgroundPPSamples);
	float4 foregroundPPColor = Median9(foregroundPPSamples);
	

	float4 foregroundRTColor = float4(0.0f);
	// If there was raytracing here
	if (raytraced) {
		// get the median value to remove noise 
		foregroundRTColor = Median9(foregroundRTSamples);
		// and check for 0 values when at tile corner 
		if (foregroundRTColor.r == 0.0f && foregroundRTColor.a == 1.0f) {
			foregroundRTColor = gRTNearField.SampleLevel(gSampler, texC, 0);
		}
	}


	float4 focusColor = gFullResColor.SampleLevel(gSampler, texC, 0);
	float Z = gGBuffer.SampleLevel(gSampler, texC, 0).r;
	
	float farBlendFactor = saturate((Z - gFarFieldFocusLimit) / (BLENDING_TWEAK * gFarFocusZoneRange));


	if (Z > gFarFieldFocusLimit) {
		// Further away than focus limit, blend between focus and background
		compositePassBufOut.finalImage = float4(farBlendFactor * backgroundPPColor.rgb + (1.0f - farBlendFactor) * focusColor.rgb, 1.0f);
	}
	else if(Z > gDistFocusPlane){
		// Between focus plane and end of focus area use focused sharp image
		compositePassBufOut.finalImage = float4(focusColor.rgb, 1.0f);
	}
	else if(raytraced){
		// In object silhouette fill in with background from ray trace
		compositePassBufOut.finalImage = gRTFarField.SampleLevel(gSampler, texC, 0);
	}


	// Outside foreground object silhouette, leak RT background over PP background and composite RT foreground on top
	if (Z > gDistFocusPlane) {
		// If we ray traced this pixel
		if (raytraced) {
			// Leak raytrace background into post processed background to get smooth transitions
			float farBlendFactor = saturate(gRTNearField.SampleLevel(gSampler, texC, 0).a * FAR_RT_BLEND_TWEAK);
			compositePassBufOut.finalImage = float4(farBlendFactor * gRTFarField.SampleLevel(gSampler, texC, 0).rgb + (1.0f - farBlendFactor) * compositePassBufOut.finalImage.rgb, 1.0f);
			
			// Composite semi-transparent RT foreground on top 
			float nearBlendFactor = saturate(foregroundRTColor.a);
			compositePassBufOut.finalImage = float4(nearBlendFactor * foregroundRTColor.rgb + (1.0f - nearBlendFactor) * compositePassBufOut.finalImage.rgb, 1.0f);
		}
	}
	// Inside foreground object silhouette, composite RT foreground on top of RT background
	else {
		if (raytraced) {
			// Transition smoothly from PP foreground to RT foreground on edges based on rays repartition between front and back layer in foreground
			
			// TO BE DONE
			
			float3 foregroundColor = foregroundRTColor.rgb;

			// Composite foreground color on background colour on objects 
			float nearBlendFactor = saturate(foregroundRTColor.a);
			compositePassBufOut.finalImage = float4(nearBlendFactor * foregroundColor + (1.0f - nearBlendFactor) * compositePassBufOut.finalImage.rgb, 1.0f);
		}
		else {
			compositePassBufOut.finalImage = float4(foregroundPPColor.rgb, 1.0f);
		}
		
	}


	return compositePassBufOut;
}

