Texture2D<float4>   gDilate;
Texture2D<float4>   gHalfResZBuffer;
Texture2D<float4>   gHalfResFrameColor;
Texture2D<float4>   gPresortBuffer;

SamplerState gSampler;

struct PS_OUTPUT

{
	float4 halfResFarField    : SV_Target0;
	float4 halfResNearField    : SV_Target1;
};

cbuffer cameraParametersCB
{
	float gOffset;
	float gDistanceToFocalPlane;
	float gTextureWidth;
	float gTextureHeight;
}

// i : 0 -> 23 
//kernel[i].x = cos(2.0f * PI* (float)i / 24.0f) / 2; //correction coc diameter -> radius
//kernel[i].x = sin(2.0f * PI* (float)i / 24.0f) / 2;
// i : 24 -> 39
//kernel[i].x = cos(2.0f * PI* (float)i / 16.0f) / 3;
//kernel[i].x = sin(2.0f * PI* (float)i / 16.0f) / 3;
// i : 40 -> 47
//kernel[i].x = cos(2.0f * PI* (float)i / 8.0f) / 6;
//kernel[i].x = sin(2.0f * PI* (float)i / 8.0f) / 6;


float kernelX[48] = { 
0.5f,
0.482962913f,
0.433012701f,
0.35355339f,
0.250000000f,
0.129409522f,
0.0f,
-0.129409522f,
-0.24999999f,
-0.353553390f,
-0.433012701f,
-0.48296291f,
-0.5f,
-0.482962913f,
-0.43301270f,
-0.353553390f,
-0.25000000f,
-0.129409522f,
0.0f,
0.129409522f,
0.250000000f,
0.35355339f,
0.43301270f,
0.482962913f,
0.33333333f,
0.307959844f,
0.235702260f,
0.12756114f,
0.0f,
-0.127561144f,
-0.23570226f,
-0.307959844f,
-0.33333333f,
-0.307959844f,
-0.23570226f,
-0.127561144f,
0.0f,
0.127561144f,
0.235702260f,
0.30795984f,
0.166666666f,
0.117851130f,
0.0f,
-0.11785113f,
-0.166666666f,
-0.117851130f,
0.0f,
0.117851130f};

float kernelY[48] = {
0.0f,
0.129409522f,
0.249999999f,
0.353553390f,
0.433012701f,
0.482962913f,
0.5f,
0.482962913f,
0.433012701f,
0.353553390f,
0.249999999f,
0.129409522f,
0.0f,
-0.12940952f,
-0.24999999f,
-0.35355339f,
-0.43301270f,
-0.48296291f,
-0.5f,
-0.48296291f,
-0.43301270f,
-0.35355339f,
-0.25000000f,
-0.12940952f,
0.0f,
0.127561144f,
0.23570226f,
0.307959844f,
0.333333333f,
0.307959844f,
0.235702260f,
0.127561144f,
0.0f,
-0.12756114f,
-0.23570226f,
-0.30795984f,
-0.33333333f,
-0.30795984f,
-0.23570226f,
-0.12756114f,
0.0f,
0.1178511f,
0.166666666f,
0.117851130f,
0.0f,
-0.11785113f,
-0.166666666f,
-0.117851130f
}

//Buffer<float> weights;

PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT MainPassBufOut;
	uint2 pixelPos = (uint2)pos.xy;

	//initialization
	float4 foreground = gPresortBuffer[pixelPos].g * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
	float4 background = gPresortBuffer[pixelPos].b * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
	float coc = gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].r; //max coc in tile
	
	/*
	if (weights[0] == 1.2f) {
		MainPassBufOut.halfResFarField = float4(1.0f, 0.0f, 1.0f, 1.0f);
	}
	else if(weights[0] == 0.0f) {
		MainPassBufOut.halfResFarField = float4(1.0f, 0.0f, 0.0f, 1.0f);
	}
	else{
		MainPassBufOut.halfResFarField = float4(1.0f, 1.0f, 1.0f, 1.0f);
	}
	*/
	
	float4 farFieldValue = float4(0.0, 0.0, 0.0, 1.0);
	float4 nearFieldValue = float4(0.0, 0.0, 0.0, 1.0);
	float4 foreground = float4(0.0, 0.0, 0.0, 1.0);
	float4 background = float4(0.0, 0.0, 0.0, 1.0);
	
	//#case 1:  where foreground and background will contribute to far field only
	if (gHalfResZBuffer[uint2(pixelPos.x / 10, pixelPos.y / 10)].r > gDistanceToFocalPlane - gOffset) {

		//Iterate over the samples 
		for (int i = 0; i < 48; i++) {

			//here let’s suppose that the circular filter has the same size as the max_coc in tile 
			float2 sampleCoord = float2( ((float)pos.x * 2.0f + coc * kernelX[i]) / gTextureWidth, ((float)pos.y * 2.0f + coc * kernelY[i]) / gTextureHeight);
			float3 presortSample = gPresortBuffer.SampleLevel(gSampler, sampleCoord, 0).rgb; //sample level 0 of texture using texcoord

			//TODO can be improved here with careful multiplication (euclidian division by 24)
			float spreadCmp;
			if (i < 24) {
				spreadCmp = presortSample.r < coc ? 0.0f : 1.0f;
			} else if (i < 39) {
				spreadCmp = presortSample.r < 2.0f * coc / 3.0f ? 0.0f : 1.0f;
			} else {
				spreadCmp = presortSample.r < coc / 3.0f ? 0.0f : 1.0f;
			}

			background += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);
			foreground += spreadCmp * presortSample.b * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);

		}

		farFieldValue = float4(lerp(foreground.rgb, background.rgb, float3(foreground.a)), 1.0);
		MainPassBufOut.halfResFarField = farFieldValue;
		MainPassBufOut.halfResNearField = float4(0.0f);

	} else {
		//#case 2 : where foreground-background gradient may overlap focus plane -> sort contribution to fields on sample basis
		
		//Iterate over the samples 
		for (int i = 0; i < 48; i++) {

			//here let’s suppose that the circular filter has the same size as the max_coc in tile 
			float2 sampleCoord = float2(((float)pos.x * 2.0f + coc * kernelX[i]) / gTextureWidth, ((float)pos.y * 2.0f + coc * kernelY[i]) / gTextureHeight);
			float3 presortSample = gPresortBuffer.SampleLevel(gSampler, sampleCoord, 0).rgb; //sample level 0 of texture using texcoord

			//TODO can be improved here with careful multiplication (euclidian division by 24)
			float spreadCmp;
			if (i < 24) {
				spreadCmp = presortSample.r < coc ? 0.0f : 1.0f;
			}
			else if (i < 39) {
				spreadCmp = presortSample.r < 2.0f * coc / 3.0f ? 0.0f : 1.0f;
			}
			else {
				spreadCmp = presortSample.r < coc / 3.0f ? 0.0f : 1.0f;
			}

			// Get the Z value of sample to know its contribution to far / near color
			float sampleZ = gHalfResZBuffer.SampleLevel(gSampler, sampleCoord, 0).r;

			//first case, sample belongs to far field
			if (sampleZ > gDistanceToFocalPlane - gOffset) {
				farFieldValue.rgb += spreadCmp * presortSample.g * gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb;

			//second case, sample belongs to near field
			} else {
				background += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);
				foreground += spreadCmp * presortSample.b * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);
			}
		}

		// Far field buffer
		MainPassBufOut.halfResFarField = farFieldValue;
		// Near field value and buffer
		nearFieldValue = float4(lerp(foreground.rgb, background.rgb, float3(foreground.a)), 1.0);
		MainPassBufOut.halfResNearField = nearFieldValue;
	}

	return MainPassBufOut;
}