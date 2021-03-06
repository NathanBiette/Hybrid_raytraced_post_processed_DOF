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
#include "DOFCompositePass.h"

namespace {
	// Where is our shader located?
	const char *kCompositeShader = "Tutorial05\\composite.ps.hlsl";
};

// Define our constructor methods
DOFCompositePass::SharedPtr DOFCompositePass::create()
{
	return SharedPtr(new DOFCompositePass());
}

DOFCompositePass::DOFCompositePass()
	: RenderPass("Composite Pass", "Composite Options")
{

}

bool DOFCompositePass::initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager)
{
	if (!pResManager) return false;

	// Stash our resource manager; ask for the texture the developer asked us to accumulate
	mpResManager = pResManager;

	int32_t width = 1920;
	int32_t height = 1080;

	mpResManager->requestTextureResource("Final_image");

	// Create our graphics state and an tiling shader
	mpGfxState = GraphicsState::create();
	mpCompositeShader = FullscreenLaunch::create(kCompositeShader);
	return true;
}

void DOFCompositePass::initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene)
{
	// Stash a copy of the scene
	if (pScene)
		mpScene = pScene;
}

void DOFCompositePass::execute(RenderContext::SharedPtr pRenderContext)
{
	Texture::SharedPtr GBuffer = mpResManager->getTexture("GBuffer");
	if (!GBuffer) return;
	Texture::SharedPtr farFieldBuffer = mpResManager->getTexture("Half_res_far_field");
	if (!farFieldBuffer) return;
	Texture::SharedPtr nearFieldBuffer = mpResManager->getTexture("Half_res_near_field");
	if (!nearFieldBuffer) return;
	Texture::SharedPtr raytraceNearFieldBuffer = mpResManager->getTexture("Half_res_raytrace_near_field");
	if (!raytraceNearFieldBuffer) return;
	Texture::SharedPtr raytraceFarFieldBuffer = mpResManager->getTexture("Half_res_raytrace_far_field");
	if (!raytraceFarFieldBuffer) return;
	Texture::SharedPtr raytraceMask = mpResManager->getTexture("RaytraceMask");
	if (!raytraceMask) return;
	Texture::SharedPtr fullResBuffer = mpResManager->getTexture("FrameColor");
	if (!fullResBuffer) return;
	Fbo::SharedPtr outputFbo = mpResManager->createManagedFbo({ "Final_image" }, "Z-Buffer2");
	if (!outputFbo) return;

	pRenderContext->clearFbo(outputFbo.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);

	auto compositeShaderVars = mpCompositeShader->getVars();
	
	compositeShaderVars["gGBuffer"] = GBuffer;
	compositeShaderVars["gFarField"] = farFieldBuffer;
	compositeShaderVars["gNearField"] = nearFieldBuffer;
	compositeShaderVars["gRTNearField"] = raytraceNearFieldBuffer;
	compositeShaderVars["gRTFarField"] = raytraceFarFieldBuffer;
	compositeShaderVars["gRTMask"] = raytraceMask;
	compositeShaderVars["gFullResColor"] = fullResBuffer;
	compositeShaderVars["cameraParametersCB"]["gFarFocusZoneRange"] = mFarLimitFocusZone - mDistFocalPlane;
	compositeShaderVars["cameraParametersCB"]["gNearFocusZoneRange"] = mDistFocalPlane - mNearLimitFocusZone;
	compositeShaderVars["cameraParametersCB"]["gFarFieldFocusLimit"] = mFarLimitFocusZone;
	compositeShaderVars["cameraParametersCB"]["gNearFieldFocusLimit"] = mNearLimitFocusZone;
	compositeShaderVars["cameraParametersCB"]["gDistFocusPlane"] = mDistFocalPlane;
	compositeShaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();
	compositeShaderVars["cameraParametersCB"]["gTextureHeight"] = (float)mpResManager->getHeight();

	mpGfxState->setFbo(outputFbo);
	mpCompositeShader->execute(pRenderContext, mpGfxState);

	//Setup a clean sampler through the API
	Sampler::SharedPtr mpSampler;
	Sampler::Desc samplerDesc;
	ProgramReflection::SharedConstPtr pReflectorCompositePass;
	ParameterBlockReflection::BindLocation samplerBindLocation;

	
	samplerDesc.setFilterMode(Sampler::Filter::Point, Sampler::Filter::Point, Sampler::Filter::Point).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border);
	mpSampler = Sampler::create(samplerDesc);

	pReflectorCompositePass = mpCompositeShader->getProgramReflection();
	samplerBindLocation = pReflectorCompositePass->getDefaultParameterBlock()->getResourceBinding("gSampler");
	ParameterBlock* pDefaultBlock = compositeShaderVars->getVars()->getDefaultBlock().get();
	pDefaultBlock->setSampler(samplerBindLocation, 0, mpSampler);

}