static const float PI = 3.14159265f;

static const float kernelX[48] = {
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
	0.117851130f };

static const float kernelY[48] = {
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
};

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
	float gSinglePixelRadius;
}

/*
Kernel Weights :
 i : 0 -> 23
kernel[i].x = cos(2.0f * PI* (float)i / 24.0f) / 2; //correction coc diameter -> radius
kernel[i].x = sin(2.0f * PI* (float)i / 24.0f) / 2;
 i : 24 -> 39
kernel[i].x = cos(2.0f * PI* (float)i / 16.0f) / 3;
kernel[i].x = sin(2.0f * PI* (float)i / 16.0f) / 3;
 i : 40 -> 47
kernel[i].x = cos(2.0f * PI* (float)i / 8.0f) / 6;
kernel[i].x = sin(2.0f * PI* (float)i / 8.0f) / 6;
*/

/*
Returns the alpha of a splatted pixel according to coc size
*/
float SampleAlpha(float cocRadius, float singlePixelRadius) {
	//samplecoc is radius of coc in pixels
	return min(1.0f / (PI * cocRadius * cocRadius), 1.0f / (PI * singlePixelRadius * singlePixelRadius));
	//return min(1.0f, (singlePixelRadius * singlePixelRadius) / (cocRadius * cocRadius));
}


PS_OUTPUT main(float2 texC : TEXCOORD, float4 pos : SV_Position)
{
	PS_OUTPUT MainPassBufOut;
	uint2 pixelPos = (uint2)pos.xy;

	//initialization
	float4 foreground;
	float4 background;
	float coc = gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].r; //max coc in tile
	float4 farFieldValue;
	float4 nearFieldValue;

	float3 sampleColor = float3(0.0f, 0.0f, 0.0f);
	float spreadCmp;
	float alphaSpreadCmpSum;
	float sampleCount;
	
	/*#case 1:  where foreground and background will contribute to far field only*/

	if (gDilate[uint2(pixelPos.x / 10, pixelPos.y / 10)].g > gDistanceToFocalPlane - gOffset) {

		foreground = gPresortBuffer[pixelPos].b * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
		background = gPresortBuffer[pixelPos].g * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
		alphaSpreadCmpSum = SampleAlpha(gPresortBuffer[pixelPos].r / 2.0f, gSinglePixelRadius);


		/*Iterate over the samples*/ 

		for (int i = 0; i < 48; i++) {
			
			/*Here let’s suppose that the circular filter has the same size as the max_coc in tile */

			float2 sampleCoord = float2( ((float)pos.x * 2.0f + coc * kernelX[i]) / gTextureWidth, ((float)pos.y * 2.0f + coc * kernelY[i]) / gTextureHeight);
			float3 presortSample = gPresortBuffer.SampleLevel(gSampler, sampleCoord, 0).rgb;			//sample level 0 of texture using texcoord
			
			/*Get the spread comparison weight*/

			if (i < 24) {
				spreadCmp = presortSample.r < coc ? 0.0f : 1.0f;
			} else if (i < 39) {
				spreadCmp = presortSample.r < 2.0f * coc / 3.0f ? 0.0f : 1.0f;
			} else {
				spreadCmp = presortSample.r < coc / 3.0f ? 0.0f : 1.0f;
			}

			foreground += spreadCmp * presortSample.b * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0f);
			background += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0f);
			alphaSpreadCmpSum += spreadCmp * SampleAlpha(presortSample.r / 2.0f, gSinglePixelRadius);

			/*We may want to smooth transition using intermediary values for spreadCmp*/
		}

		farFieldValue = float4( (background.rgb + foreground.rgb) / alphaSpreadCmpSum, 1.0);
		nearFieldValue = float4(0.0f);

	/*
	#case 2 : where foreground-background gradient may overlap focus plane -> sort contribution to fields on sample basis
	*/
	} else {
		
		farFieldValue = float4(0.0f, 0.0f, 0.0f , 0.0f);
		foreground = gPresortBuffer[pixelPos].b * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
		background = gPresortBuffer[pixelPos].g * float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
		alphaSpreadCmpSum = SampleAlpha(gPresortBuffer[pixelPos].r / 2.0f, gSinglePixelRadius);
		sampleCount = 1.0;

		//Iterate over the samples 
		for (int i = 0; i < 48; i++) {

			//here let’s suppose that the circular filter has the same size as the max_coc in tile 
			float2 sampleCoord = float2( ((float)pos.x * 2.0f + coc * kernelX[i]) / gTextureWidth, ((float)pos.y * 2.0f + coc * kernelY[i]) / gTextureHeight);
			float3 presortSample = gPresortBuffer.SampleLevel(gSampler, sampleCoord, 0).rgb; //sample level 0 of texture using texcoord

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
				farFieldValue += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0f);

			//second case, sample belongs to near field
			} else {
				foreground += spreadCmp * presortSample.b * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);
				background += spreadCmp * presortSample.g * float4(gHalfResFrameColor.SampleLevel(gSampler, sampleCoord, 0).rgb, 1.0);
				alphaSpreadCmpSum += spreadCmp * SampleAlpha(presortSample.r / 2.0f, gSinglePixelRadius);
				sampleCount += spreadCmp;
			}
		}
		//here the fragments are already pretty much in focus so we cannot normalize, sum of weights probably 0
		if (farFieldValue.a < 0.001f) {
			farFieldValue = float4(gHalfResFrameColor[pixelPos].rgb, 1.0);
		}
		else {	//here we can still get some background fragments
			farFieldValue = float4(farFieldValue.rgb / farFieldValue.a, 1.0f);
		}
		

		float alpha = saturate(2.0f * foreground.a / (sampleCount * SampleAlpha(coc / 2.0f, gSinglePixelRadius) ) );
		//nearFieldValue = float4((foreground.rgb + background.rgb) / alphaSpreadCmpSum, alpha);
		nearFieldValue = float4(foreground.rgb / foreground.a, alpha);
	}

	MainPassBufOut.halfResFarField = farFieldValue;
	MainPassBufOut.halfResNearField = nearFieldValue;


	return MainPassBufOut;
}