// Some shared Falcor stuff for talking between CPU and GPU code
#include "HostDeviceSharedMacros.h"

// Include and import common Falcor utilities and data structures
__import Raytracing;                   // Shared ray tracing specific functions & data
__import ShaderCommon;                 // Shared shading data structures
__import Shading;                      // Shading functions, etc  

// Include utility functions for random numbers & alpha testing
#include "thinLensUtils.hlsli"

// Halton sequence base 2 and 3 coordinates in unit circle
static const float haltonX[64] = {
	0.50000f,
	0.25000f,
	0.75000f,
	0.12500f,
	0.62500f,
	0.37500f,
	0.87500f,
	0.56250f,
	0.31250f,
	0.81250f,
	0.18750f,
	0.68750f,
	0.43750f,
	0.93750f,
	0.03125f,
	0.53125f,
	0.28125f,
	0.78125f,
	0.15625f,
	0.65625f,
	0.40625f,
	0.09375f,
	0.59375f,
	0.34375f,
	0.21875f,
	0.71875f,
	0.46875f,
	0.96875f,
	0.51562f,
	0.26562f,
	0.76562f,
	0.64062f,
	0.39062f,
	0.07812f,
	0.57812f,
	0.32812f,
	0.82812f,
	0.70312f,
	0.45312f,
	0.54688f,
	0.29688f,
	0.79688f,
	0.17188f,
	0.42188f,
	0.92188f,
	0.10938f,
	0.60938f,
	0.35938f,
	0.85938f,
	0.23438f,
	0.73438f,
	0.48438f,
	0.50781f,
	0.25781f,
	0.75781f,
	0.63281f,
	0.38281f,
	0.57031f,
	0.32031f,
	0.82031f,
	0.19531f,
	0.69531f,
	0.44531f,
	0.94531f
};
static const float haltonY[64] = {
	0.33333f, 
	0.66667f, 
	0.11111f, 
	0.44444f, 
	0.77778f, 
	0.22222f, 
	0.55556f, 
	0.03704f, 
	0.37037f, 
	0.70370f, 
	0.14815f, 
	0.48148f, 
	0.81481f, 
	0.25926f, 
	0.59259f, 
	0.92593f, 
	0.07407f, 
	0.40741f, 
	0.74074f, 
	0.18519f, 
	0.51852f, 
	0.29630f, 
	0.62963f, 
	0.96296f, 
	0.34568f, 
	0.67901f, 
	0.12346f, 
	0.45679f, 
	0.23457f, 
	0.56790f, 
	0.90123f, 
	0.38272f, 
	0.71605f, 
	0.49383f, 
	0.82716f, 
	0.27160f, 
	0.60494f, 
	0.08642f, 
	0.41975f, 
	0.53086f, 
	0.86420f, 
	0.30864f, 
	0.64198f, 
	0.02469f, 
	0.35802f, 
	0.69136f, 
	0.13580f, 
	0.46914f, 
	0.80247f, 
	0.24691f, 
	0.58025f, 
	0.91358f, 
	0.72840f, 
	0.17284f, 
	0.50617f, 
	0.28395f, 
	0.61728f, 
	0.43210f,
	0.76543f, 
	0.20988f, 
	0.54321f, 
	0.87654f, 
	0.32099f, 
	0.65432f
};

Texture2D<float4> gRaytraceMask;
Texture2D<float4> gZBuffer;
// The output textures, where we store our G-buffer results.  See bindings in C++ code.
RWTexture2D<float4> gColorForeground;
RWTexture2D<float4> gColorBackground;

// Payload for our primary rays.  This shader doesn't actually use the data, but it is currently
//    required to use a user-defined payload while tracing a ray.  So define a simple one.
struct SimpleRayPayload
{
	bool dummyValue;
};

struct ColorRayPayload
{
	float4 colorValue;  // Store 0 if we hit a surface, 1 if we miss all surfaces
	float ZValue;
};

// Shader parameters for our ray gen shader that need to be set by the C++ code
cbuffer RayGenCB
{
	float   gLensRadius;    // Radius of the thin lens.  Use 0 for pinhole camera.
	float   gFocalLen;      // Focal Length of the lens
	float   gPlaneDist;      // Distance to the plane where geometry is in focus
	float   gSensorWidth;      // Distance to the plane where geometry is in focus
	float   gSensorHeight;      // Distance to the plane where geometry is in focus
	float   gSensorDepth;      // Distance to the plane where geometry is in focus
	uint    gFrameCount;    // An integer changing every frame to update the random number
	float2  gPixelJitter;   // in [0..1]^2.  Should be (0.5,0.5) if no jittering used
	uint	gNumRays;
	float4x4 gViewMatrix;

}

// How do we generate the rays that we trace?
[shader("raygeneration")]
void GBufferRayGen()
{
	if (gRaytraceMask[uint2(DispatchRaysIndex().x / 10, DispatchRaysIndex().y / 10)].r > 0.01f ) {

		// Get our pixel's position on the screen
		uint2 launchIndex = DispatchRaysIndex();
		uint2 launchDim = DispatchRaysDimensions();

		// Convert our ray index into a ray direction in world space.  
		float2 pixelCenter = (launchIndex + gPixelJitter) / launchDim;
		float2 ndc = float2(2, -2) * pixelCenter + float2(-1, 1);
		float3 rayDir = ndc.x * gCamera.cameraU + ndc.y * gCamera.cameraV + gCamera.cameraW;
		//float3 rayDir = ndc.x * gCamera.cameraU * (gSensorWidth / 2.0f) / (length(gCamera.cameraU)) + ndc.y * gCamera.cameraV * (gSensorHeight/2.0f) / (length(gCamera.cameraV)) + gCamera.cameraW * gSensorDepth * 0.985f / length(gCamera.cameraW);
		//0.5 * (0.105263 / 2) / norm of U 
		//float3 rayDir = ndc.x * gCamera.cameraU * gSensorWidth / (length(gCamera.cameraU)) + ndc.y * gCamera.cameraV * gSensorHeight / (length(gCamera.cameraV)) + gCamera.cameraW * gSensorDepth * 0.674f / length(gCamera.cameraW);

		// Find the focal point for this pixel.
		rayDir /= length(gCamera.cameraW);                     // Make ray have length 1 along the camera's w-axis.
		//rayDir /= gSensorDepth;                     // Make ray have length 1 along the camera's w-axis.
		
		//float3 rayDir = gCamera.cameraU * ndc.x / length(gCamera.cameraU) + gCamera.cameraV * ndc.y * 9.0f / ( 16.0f * length(gCamera.cameraV)) + gCamera.cameraW  / length(gCamera.cameraW);


		float3 focalPoint = gCamera.posW + gPlaneDist * rayDir; // Select point on ray a distance to focus plane along the w-axis

																// Initialize a random number generator
		uint randSeed = initRand(launchIndex.x + launchIndex.y * launchDim.x, gFrameCount, 16);

		float4 accumColorNear = float4(0.0f, 0.0f, 0.0f, 1.0f);
		float4 accumColorFar = float4(0.0f, 0.0f, 0.0f, 1.0f);
		uint numHits = 0;
		//shoot many rays

		for (int i = 0; i < gNumRays; i++) {
			// Get random numbers (in polar coordinates), convert to random cartesian uv on the lens
			float2 rnd = float2(2.0f * 3.14159265f * nextRand(randSeed), gLensRadius * nextRand(randSeed));
			//float2 uv = float2(cos(rnd.x) * rnd.y, sin(rnd.x) * rnd.y);

			// Use uv coordinate to compute a random origin on the camera lens
			//float3 randomOrig = gCamera.posW + uv.x * normalize(gCamera.cameraU) + uv.y * normalize(gCamera.cameraV);


			float2 uv = float2( 2.0f * haltonX[i] - 1.0f + (nextRand(randSeed) - 0.5f) * 0.25f, (-2.0f) * haltonY[i] + 1.0f + (nextRand(randSeed) - 0.5f) * 0.25f);
			//float2 uv = float2(2.0f * haltonX[i] - 1.0f, -2.0f * haltonY[i] + 1.0f);
			uv = uv * gLensRadius;

			float3 randomOrig = gCamera.posW + uv.x * normalize(gCamera.cameraU) + uv.y * normalize(gCamera.cameraV);

			// Initialize a ray structure for our ray tracer
			RayDesc ray;
			ray.Origin = randomOrig;							// Start our ray at the world-space camera position
			ray.Direction = normalize(focalPoint - randomOrig); // Our ray direction
			ray.TMin = 0.0f;									// Start at 0.0; for camera, no danger of self-intersection
			ray.TMax = 1e+38f;									// Maximum distance to look for a ray hit

			// Initialize our ray payload (a per-ray, user-definable structure)
			ColorRayPayload rayData;
			rayData.colorValue = float4(0.0f);

			// Trace our ray
			TraceRay(gRtScene,                        // A Falcor built-in containing the raytracing acceleration structure
				RAY_FLAG_CULL_BACK_FACING_TRIANGLES,  // Ray flags.  (Here, we will skip hits with back-facing triangles)
				0xFF,                                 // Instance inclusion mask.  0xFF => no instances discarded from this mask
				0,                                    // Hit group to index (i.e., when intersecting, call hit shader #0)
				hitProgramCount,                      // Number of hit groups ('hitProgramCount' is built-in from Falcor with the right number) 
				0,                                    // Miss program index (i.e., when missing, call miss shader #0)
				ray,                                  // Data structure describing the ray to trace
				rayData);                             // Our user-defined ray payload structure to store intermediate results
		
			if (rayData.ZValue < gPlaneDist) {
			//if (rayData.ZValue == 0.0f) {
			//if (gViewMatrix[0][0] < 0.0f) {
				accumColorNear += rayData.colorValue;
				//float zNormalized = rayData.ZValue / gPlaneDist;
				//accumColorNear += float4(zNormalized, zNormalized, 0.0f, 1.0f);
				numHits++;
			}
			else {
				accumColorFar += rayData.colorValue;
			}

			
		}
		//gColorForeground[launchIndex] = float4(accumColorNear.rgb / (float)numHits, (float)numHits/(float)gNumRays);
		/*
		if (numHits > 0) {
			if (gZBuffer[launchIndex].x > gPlaneDist) {
				gColorForeground[launchIndex] = float4(accumColorNear.rgb / (float)numHits, 1.0f) * (float)numHits / (float)gNumRays + gColorForeground[launchIndex] * (1.0f - (float)numHits / (float)gNumRays);
			}
			else {
				gColorForeground[launchIndex] = float4((accumColorNear.rgb + accumColorFar.rgb) / (float)gNumRays, 1.0f);
			}
			
		}*/
		//gColorForeground[launchIndex] = float4((accumColorNear.rgb + accumColorFar.rgb) / (float)gNumRays, 1.0f);
		
		// If at least one foreground hit, store near color with semi transparency in alpha
		if (numHits > 0) {
			gColorForeground[launchIndex] = float4(accumColorNear.rgb / (float)numHits, (float)numHits / (float)gNumRays);
		}
		// else no foreground color
		else {
			gColorForeground[launchIndex] = float4(0.0f, 0.0f, 0.0f, 1.0f);
		}

		// If no hit in the far scene, no background color
		if (numHits == gNumRays) {
			gColorBackground[launchIndex] = float4(0.0f, 0.0f, 0.0f, 1.0f);
		}
		// else get background color
		else {
			gColorBackground[launchIndex] = float4(accumColorFar.rgb / (float)(gNumRays - numHits), 1.0f);
		}
		

	}

}

// A constant buffer used in our miss shader, we'll fill data in from C++ code
cbuffer MissShaderCB
{
	float3  gBgColor;
};

// What code is executed when our ray misses all geometry?
[shader("miss")]
void PrimaryMiss(inout ColorRayPayload hitData)
{
	// Store the background color into our diffuse material buffer
	hitData.colorValue = float4(gBgColor, 1.0f);
}

// What code is executed when our ray hits a potentially transparent surface?
[shader("anyhit")]
void PrimaryAnyHit(inout ColorRayPayload hitData, BuiltinIntersectionAttribs attribs)
{
	// Is this a transparent part of the surface?  If so, ignore this hit
	if (alphaTestFails(attribs))
		IgnoreHit();
}

// What code is executed when we have a new closest hitpoint?
[shader("closesthit")]
void PrimaryClosestHit(inout ColorRayPayload rayData, BuiltinIntersectionAttribs attribs)
{
	// Get some information about the current ray
	uint2  launchIndex = DispatchRaysIndex();

	// Run a pair of Falcor helper functions to compute important data at the current hit point
	VertexOut  vsOut = getVertexAttributes(PrimitiveIndex(), attribs);          // Get geometrical data
	ShadingData shadeData = prepareShadingData(vsOut, gMaterial, gCamera.posW); // Get shading data

	// Dump out our G buffer channels
	float4 colorAccum = float4(0.0f, 0.0f, 0.0f, 1.0f);

	// Get the shading resulting from all lights (sum diffuse and specular term of each lights contribution)
	for (int lightIndex = 0; lightIndex < gLightsCount; lightIndex++)
	{
		ShadingResult sr = evalMaterial(shadeData, gLights[lightIndex], 1.0);	//for now just don't put any shadows !!!
		colorAccum.rgb += sr.color.rgb;
	}

	rayData.colorValue = colorAccum;
	//rayData.ZValue = 2 * gCamera.farZ * gCamera.nearZ / (gCamera.farZ + gCamera.nearZ - (gCamera.farZ - gCamera.nearZ) * (2 * (vsOut.posH.z / vsOut.posH.w) - 1.0f));
	//rayData.ZValue = 2 * gCamera.farZ * gCamera.nearZ / (gCamera.farZ + gCamera.nearZ - (gCamera.farZ - gCamera.nearZ) * (2 * mul(gCamera.viewProjMat, float4(shadeData.posW, 1.0f)).z - 1.0f));
	//rayData.ZValue = vsOut.posH.z / vsOut.posH.w;
	//rayData.ZValue = mul(gCamera.viewMat, float4(vsOut.posW, 1.0f)).z;
	//rayData.ZValue = mul(float4(vsOut.posW, 1.0f), gViewMatrix).z;
	//rayData.ZValue = vsOut.posW.z;
	rayData.ZValue = dot( (shadeData.posW - gCamera.posW), gCamera.cameraW / length(gCamera.cameraW) );
	
	//rayData.ZValue = (shadeData.posW - gCamera.posW).x;
}