/**********************************************************************************************************************
# Copyright (c) 2018, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
# following conditions are met:
#  * Redistributions of code must retain the copyright notice, this list of conditions and the following disclaimer.
#  * Neither the name of NVIDIA CORPORATION nor the names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
# SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********************************************************************************************************************/
//#include "HostDeviceSharedCode.h"
#include "RaytracePass.h"
#include <chrono>

// Some global vars, used to simplify changing shader locations
namespace {
	// Where is our shader located?
	const char *kFileRayTrace = "Tutorial05\\raytracePass.rt.hlsl";

	// What are the entry points in that shader for various ray tracing shaders?
	const char* kEntryPointRayGen = "GBufferRayGen";
	const char* kEntryPointMiss0 = "PrimaryMiss";
	const char* kEntryPrimaryAnyHit = "PrimaryAnyHit";
	const char* kEntryPrimaryClosestHit = "PrimaryClosestHit";

	// Our camera allows us to jitter.  If using MSAA jitter, here are same positions.  Divide by 8 to give (-0.5..0.5)
	const float kMSAA[8][2] = { { 1,-3 },{ -1,3 },{ 5,1 },{ -3,-5 },{ -5,5 },{ -7,-1 },{ 3,7 },{ 7,-7 } };
};

bool DOFRayTracing::initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager)
{
	int32_t width = 1920;
	int32_t height = 1080;
	
	mpResManager = pResManager;
	
	// Set the default scene to load
	mpResManager->setDefaultSceneName("Data/pink_room/pink_room.fscene");

	// Create our wrapper around a ray tracing pass.  Tell it where our shaders are, then compile/link the program
	mpRays = RayLaunch::create(kFileRayTrace, kEntryPointRayGen);
	mpRays->addMissShader(kFileRayTrace, kEntryPointMiss0);
	mpRays->addHitShader(kFileRayTrace, kEntryPrimaryClosestHit, kEntryPrimaryAnyHit);
	mpRays->compileRayProgram();
	if (mpScene) mpRays->setScene(mpScene);

	// Set up our random number generator by seeding it with the current time 
	auto currentTime = std::chrono::high_resolution_clock::now();
	auto timeInMillisec = std::chrono::time_point_cast<std::chrono::milliseconds>(currentTime);
	mRng = std::mt19937(uint32_t(timeInMillisec.time_since_epoch().count()));

	// Our GUI for this pass needs more space than other passes, so enlarge the GUI window.
	setGuiSize(ivec2(250, 300));
	return true;
}

void DOFRayTracing::initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene)
{
	// Stash a copy of the scene and pass it to our ray tracer (if initialized)
	mpScene = std::dynamic_pointer_cast<RtScene>(pScene);
	if (mpRays) mpRays->setScene(mpScene);
}

void DOFRayTracing::execute(RenderContext::SharedPtr pRenderContext)
{
	// Check that we're ready to render
	if (!mpRays || !mpRays->readyToRender()) return;

	// didn't find a better way to clear to zero texture (useful only for visualization)
	Fbo::SharedPtr outputFbo = mpResManager->createManagedFbo({ "Half_res_raytrace_near_field", "Half_res_raytrace_far_field" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);

	Texture::SharedPtr nearFieldBuffer = mpResManager->getTexture("Half_res_raytrace_near_field");
	Texture::SharedPtr raytraceFarFieldBuffer = mpResManager->getTexture("Half_res_raytrace_far_field");
	Texture::SharedPtr raytraceMask = mpResManager->getTexture("RaytraceMask");

	// Pass our background color down to our miss shader
	auto missVars = mpRays->getMissVars(0);
	missVars["MissShaderCB"]["gBgColor"] = mBgColor;

	// Pass our camera parameters to the ray generation shader
	auto rayGenVars = mpRays->getRayGenVars();
	rayGenVars["gRaytraceMask"] = raytraceMask;
	rayGenVars["gColorForeground"] = nearFieldBuffer;
	rayGenVars["gColorBackground"] = raytraceFarFieldBuffer;
	rayGenVars["RayGenCB"]["gLensRadius"] = mAperture / 2.0f;
	rayGenVars["RayGenCB"]["gPlaneDist"] = mDistFocalPlane;
	rayGenVars["RayGenCB"]["gFrameCount"] = mFrameCount++;
	rayGenVars["RayGenCB"]["gNumRays"] = mNumRays;

	// Compute our jitter, either (0,0) as the center or some computed random/MSAA offset
	float xOff = 0.0f, yOff = 0.0f;
	if (mUseJitter)
	{
		// Determine our offset in the pixel
		xOff = mUseRandomJitter ? mRngDist(mRng) - 0.5f : kMSAA[mFrameCount % 8][0] * 0.0625f;
		yOff = mUseRandomJitter ? mRngDist(mRng) - 0.5f : kMSAA[mFrameCount % 8][1] * 0.0625f;
	}

	// Set our shader parameters and the scene camera to use the computed jitter
	rayGenVars["RayGenCB"]["gPixelJitter"] = vec2(xOff + 0.5f, yOff + 0.5f);
	mpScene->getActiveCamera()->setJitter(xOff / float(raytraceFarFieldBuffer->getWidth()), yOff / float(raytraceFarFieldBuffer->getHeight()));

	// Launch our ray tracing
	mpRays->execute(pRenderContext, uvec2(mpResManager->getScreenSize().x / 2 , mpResManager->getScreenSize().y / 2));
}
