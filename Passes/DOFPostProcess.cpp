﻿/**********************************************************************************************************************
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

#include "DOFPostProcess.h"

namespace {
	// Where is our shader located?
	const char *kTilingShader = "Tutorial05\\tiling.ps.hlsl";
	const char *kDilateShader = "Tutorial05\\dilate.ps.hlsl";
	const char *kDownPresortShader = "Tutorial05\\downpresort.ps.hlsl";
	const char *kMainPassShader = "Tutorial05\\mainpass.ps.hlsl";
};

// Define our constructor methods
DOFPostProcess::SharedPtr DOFPostProcess::create()
{
	return SharedPtr(new DOFPostProcess());
}

DOFPostProcess::DOFPostProcess()
	: RenderPass("DOF Post Process", "DOF Post Process Options")
{

}

bool DOFPostProcess::initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager)
{
	if (!pResManager) return false;

	// Stash our resource manager; ask for the texture the developer asked us to accumulate
	mpResManager = pResManager;

	int32_t width = 1920;
	int32_t height = 1080;

	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT WIDTH = ") + std::to_string(mpResManager->getWidth()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT HEIGHT = ") + std::to_string(mpResManager->getHeight()));

	// Textures at 20th of resolution for tile informations
	mpResManager->requestTextureResource("Tiles", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); //specifying size seems to work well
	mpResManager->requestTextureResource("Dilate", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); 
	mpResManager->requestTextureResource("EdgeMask", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20);  
	mpResManager->requestTextureResource("RaytraceMask", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20);  

	// Textures for Downsample-Presort pass (half res)
	mpResManager->requestTextureResource("Half_res_color", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 2 , height / 2);
	mpResManager->requestTextureResource("Presort_buffer", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 2 , height / 2);
	mpResManager->requestTextureResource("Half_res_z_buffer", ResourceFormat::R32Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);

	// Intermediary half-resolution color textures for PP and RT
	mpResManager->requestTextureResource("Half_res_far_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);
	mpResManager->requestTextureResource("Half_res_near_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);
	mpResManager->requestTextureResource("Half_res_raytrace_near_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);
	mpResManager->requestTextureResource("Half_res_raytrace_far_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);

	// Useless texture used for FBO setup (ZBuffer needed for some reason)
	mpResManager->requestTextureResource("Z-Buffer2", ResourceFormat::D24UnormS8, ResourceManager::kDepthBufferFlags);

	// Create our graphics state and an tiling shader
	mpGfxState = GraphicsState::create();
	mpTilingShader = FullscreenLaunch::create(kTilingShader);
	mpDilateShader = FullscreenLaunch::create(kDilateShader);
	mpDownPresortShader = FullscreenLaunch::create(kDownPresortShader);
	mpMainPassShader = FullscreenLaunch::create(kMainPassShader);

	return true;
}

void DOFPostProcess::initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene)
{
	// Stash a copy of the scene
	if (pScene)
		mpScene = pScene;

}

/*
void DOFPostProcess::resize(uint32_t width, uint32_t height)
{
	// Create / resize a texture to store the previous frame.
	//    Parameters: width, height, texture format, texture array size, #mip levels, initialization data, how we expect to use it.
	mpLastFrame = Texture::create2D(width, height, ResourceFormat::RGBA32Float, 1, 1, nullptr, ResourceManager::kDefaultFlags);

	// We need a framebuffer to attach to our graphics pipe state (when running our full-screen pass).  We can ask our
	//    resource manager to create one for us, with specified width, height, and format and one color buffer.
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);

}
*/

void DOFPostProcess::execute(RenderContext::SharedPtr pRenderContext)
{
	Falcor::logWarning(std::string(" CAMERA SETTINGS ARE ") + std::to_string(mpScene->getActiveCamera()->getFarPlane()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT WIDTH = ") + std::to_string(mpResManager->getWidth()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT HEIGHT = ") + std::to_string(mpResManager->getHeight()));
	
	//########################  First pass -> Tile pass  ########################################
	Texture::SharedPtr GBuffer = mpResManager->getTexture("GBuffer");
	if (!GBuffer) return;

	Fbo::SharedPtr outputFbo = mpResManager->createManagedFbo({"Tiles", "EdgeMask"}, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);

	// Set shader parameters for our accumulation pass
	auto shaderVars = mpTilingShader->getVars();
	shaderVars["gGBuffer"] = GBuffer;
	shaderVars["cameraParametersCB"]["gFocalLength"] = mFocalLength;
	shaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	shaderVars["cameraParametersCB"]["gAperture"] = mAperture;
	shaderVars["cameraParametersCB"]["gSensorWidth"] = mSensorWidth;
	shaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();

	mpGfxState->setFbo(outputFbo);
	mpTilingShader->execute(pRenderContext, mpGfxState);

	//########################  Second pass -> dilate pass  ########################################
	Fbo::SharedPtr outputFbo2 = mpResManager->createManagedFbo({ "Dilate", "RaytraceMask" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo2.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);

	Texture::SharedPtr tiles = mpResManager->getTexture("Tiles");
	if (!tiles) return;
	Texture::SharedPtr edgeMask = mpResManager->getTexture("EdgeMask");
	if (!edgeMask) return;

	auto dilateShaderVars = mpDilateShader->getVars();
	dilateShaderVars["gTiles"] = tiles;
	dilateShaderVars["gEdgeMask"] = edgeMask;
	dilateShaderVars["textureParametersCB"]["width"] = (int)mpResManager->getWidth() / 20;
	dilateShaderVars["textureParametersCB"]["height"] = (int)mpResManager->getHeight() / 20;
	dilateShaderVars["textureParametersCB"]["distToFocusPlane"] = mDistFocalPlane;
	mpGfxState->setFbo(outputFbo2);
	mpDilateShader->execute(pRenderContext, mpGfxState);

	//########################  Third pass -> downPresort pass  ########################################
	Fbo::SharedPtr outputFbo3 = mpResManager->createManagedFbo({ "Half_res_color", "Presort_buffer", "Half_res_z_buffer" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo3.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);
	
	Texture::SharedPtr dilate = mpResManager->getTexture("Dilate");
	Texture::SharedPtr frameColor = mpResManager->getTexture("FrameColor");
	
	auto downPresortShaderVars = mpDownPresortShader->getVars();
	downPresortShaderVars["gDilate"] = dilate;
	downPresortShaderVars["gGBuffer"] = GBuffer;
	downPresortShaderVars["gFrameColor"] = frameColor;
	downPresortShaderVars["cameraParametersCB"]["gFocalLength"] = mFocalLength;
	downPresortShaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	downPresortShaderVars["cameraParametersCB"]["gAperture"] = mAperture;
	downPresortShaderVars["cameraParametersCB"]["gSensorWidth"] = mSensorWidth;
	downPresortShaderVars["cameraParametersCB"]["gDepthRange"] = mDepthRange;			//const of depth range here
	downPresortShaderVars["cameraParametersCB"]["gSinglePixelRadius"] = 0.7071f;	//const of pixel radius
	downPresortShaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();
	downPresortShaderVars["cameraParametersCB"]["gTextureHeight"] = (float)mpResManager->getHeight();
	
	//Setup a clean sampler through the API
	Sampler::SharedPtr mpSampler;
	Sampler::Desc samplerDesc;
	ProgramReflection::SharedConstPtr pReflectorDownPresortPass;
	ParameterBlockReflection::BindLocation samplerBindLocation;
	samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Point).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border);
	mpSampler = Sampler::create(samplerDesc);
	pReflectorDownPresortPass = mpDownPresortShader->getProgramReflection();
	samplerBindLocation = pReflectorDownPresortPass->getDefaultParameterBlock()->getResourceBinding("gSampler");
	ParameterBlock* pDefaultBlock = downPresortShaderVars->getVars()->getDefaultBlock().get();
	pDefaultBlock->setSampler(samplerBindLocation, 0, mpSampler);
	//----------------- end sampler section -------------------

	mpGfxState->setFbo(outputFbo3);
	mpDownPresortShader->execute(pRenderContext, mpGfxState);

	//########################  Fourth pass -> main pass  ########################################
	Fbo::SharedPtr outputFbo4 = mpResManager->createManagedFbo({ "Half_res_far_field", "Half_res_near_field" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo4.get(), vec4(0.0f, 0.0f, 0.0f, 0.0f), 1.0f, 0);

	//getting the texture to pass to our shader
	Texture::SharedPtr halfResColor = mpResManager->getTexture("Half_res_color");
	Texture::SharedPtr presortBuffer = mpResManager->getTexture("Presort_buffer");
	Texture::SharedPtr HalfResZBuffer = mpResManager->getTexture("Half_res_z_buffer");
	Texture::SharedPtr rayTraceMask = mpResManager->getTexture("RaytraceMask");

	//shader vars setup
	auto mainPassShaderVars = mpMainPassShader->getVars();
	mainPassShaderVars["gDilate"] = dilate;
	mainPassShaderVars["gHalfResZBuffer"] = HalfResZBuffer;
	mainPassShaderVars["gHalfResFrameColor"] = halfResColor;
	mainPassShaderVars["gPresortBuffer"] = presortBuffer;
	mainPassShaderVars["gRayTraceMask"] = rayTraceMask;
	mainPassShaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	mainPassShaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();
	mainPassShaderVars["cameraParametersCB"]["gTextureHeight"] = (float)mpResManager->getHeight();
	mainPassShaderVars["cameraParametersCB"]["gSinglePixelRadius"] = 0.7071f;	//const of pixel radius
	mainPassShaderVars["cameraParametersCB"]["gFrameCount"] = mFrameCount++;

	//sampler setup
	Sampler::SharedPtr mpPointSampler;
	Sampler::Desc pointSamplerDesc;
	ProgramReflection::SharedConstPtr pReflectorMainPass;
	ParameterBlockReflection::BindLocation pointSamplerBindLocation;
	pointSamplerDesc.setFilterMode(Sampler::Filter::Point, Sampler::Filter::Point, Sampler::Filter::Point).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border);
	mpPointSampler = Sampler::create(pointSamplerDesc);
	pReflectorMainPass = mpMainPassShader->getProgramReflection();
	pointSamplerBindLocation = pReflectorMainPass->getDefaultParameterBlock()->getResourceBinding("gSampler");
	ParameterBlock* pDefaultBlockPointSampler = mainPassShaderVars->getVars()->getDefaultBlock().get();
	pDefaultBlockPointSampler->setSampler(pointSamplerBindLocation, 0, mpPointSampler);
	
	mpGfxState->setFbo(outputFbo4);
	mpMainPassShader->execute(pRenderContext, mpGfxState);
}