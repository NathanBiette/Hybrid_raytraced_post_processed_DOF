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

#include "TilePass.h"

namespace {
	// Where is our shader located?
	const char *kTilingShader = "Tutorial05\\tiling.ps.hlsl";
	const char *kDilateShader = "Tutorial05\\dilate.ps.hlsl";
	const char *kDownPresortShader = "Tutorial05\\downpresort.ps.hlsl";
	const char *kMainPassShader = "Tutorial05\\mainpass.ps.hlsl";
};

// Define our constructor methods
TilePass::SharedPtr TilePass::create()
{
	return SharedPtr(new TilePass());
}

TilePass::TilePass()
	: RenderPass("Tiling Pass", "Tiling Options")
{

}

bool TilePass::initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager)
{
	if (!pResManager) return false;

	// Stash our resource manager; ask for the texture the developer asked us to accumulate
	mpResManager = pResManager;

	/* HERE get the rigth texture setup in FBO */
	
	//########### pasted code ###############

	// We need a framebuffer to attach to our graphics pipe state (when running our full-screen pass).  We can ask our
	//    resource manager to create one for us, with specified width, height, and format and one color buffer.
	//mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	//mpGfxState->setFbo(mpInternalFbo);

	//#######################################

	//Get size of full screen image
	/*
	//Viewport isn't even initialized just yet ....
	int32_t width = (int32_t)mpResManager->getWidth();
	int32_t height = (int32_t)mpResManager->getHeight();
	*/
	int32_t width = 1920;
	int32_t height = 1080;

	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT WIDTH = ") + std::to_string(mpResManager->getWidth()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT HEIGHT = ") + std::to_string(mpResManager->getHeight()));

	mpResManager->requestTextureResource("Tiles", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); //specifying size seems to work well
	mpResManager->requestTextureResource("Dilate", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); 
	//mpResManager->requestTextureResource("Half_res_color", ResourceFormat::RGB16Float,(Falcor::Resource::BindFlags)112U, width / 2 , height / 2);

	//mptest = Texture::create2D(width / 20, height / 20, ResourceFormat::RG16Float);
	
	mpResManager->requestTextureResource("Half_res_color", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 2 , height / 2);
	mpResManager->requestTextureResource("Presort_buffer", ResourceFormat::RGBA16Float,(Falcor::Resource::BindFlags)112U, width / 2 , height / 2);
	mpResManager->requestTextureResource("Half_res_z_buffer", ResourceFormat::R32Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);

	mpResManager->requestTextureResource("Half_res_far_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);
	mpResManager->requestTextureResource("Half_res_near_field", ResourceFormat::RGBA16Float, (Falcor::Resource::BindFlags)112U, width / 2, height / 2);
	
	//mpResManager->requestTextureResource("Tiles", ResourceFormat::R32Float);
	//mpResManager->requestTextureResource("Tiles");
	mpResManager->requestTextureResource("Z-Buffer2", ResourceFormat::D24UnormS8, ResourceManager::kDepthBufferFlags);
	//mpResManager->requestTextureResource("Z-Buffer");

	// Create our graphics state and an tiling shader
	mpGfxState = GraphicsState::create();
	mpTilingShader = FullscreenLaunch::create(kTilingShader);
	mpDilateShader = FullscreenLaunch::create(kDilateShader);
	mpDownPresortShader = FullscreenLaunch::create(kDownPresortShader);
	mpMainPassShader = FullscreenLaunch::create(kMainPassShader);

	//NOT WORKING !!!
	/*
	ProgramReflection::SharedConstPtr pReflector = mpMainPassShader->getProgramReflection();
	mpVars = GraphicsVars::create(pReflector);
	TypedBuffer<float>::SharedPtr pBuf = TypedBuffer<float>::create((uint32_t)3, Resource::BindFlags::ShaderResource);
	pBuf[0] = (float)1.2f;
	pBuf[1] = (float)1.0f;
	pBuf[2] = (float)1.0f;
	bool succeed = mpVars->setTypedBuffer("weights", pBuf);
	Falcor::logWarning(std::string("buffer success ? = ") + std::to_string(succeed));
	Falcor::logWarning(std::string("pbuffer 0 ? = ") + std::to_string(pBuf[0]));
	Falcor::logWarning(std::string("pbuffer 1 ? = ") + std::to_string(pBuf[1]));
	Falcor::logWarning(std::string("pbuffer 2 ? = ") + std::to_string(pBuf[2]));
	*/
	
	//setup the kernel for main pass
	
	/*
	std::vector<float> weights(center + 1);

	for (int i = 0; i < 49 - 1; i++) {
		if (i < 24) {
			kernel[i].x = cos(2.0f * PI* (float)i / 24.0f) *

				((float)pixelPos.x * 2.0f + coc / 12.0f *) / gTextureWidth;
			kernel[i].y = (float)pixelPos.y * 2.0f + coc / 12.0f * sin(2.0f * PI* (float)i / 9.0f) / gTextureHeight;
		}
		else if (i < 39) {

		}
		else {

		}

	}*/

	return true;
}

void TilePass::initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene)
{
	// Stash a copy of the scene
	if (pScene)
		mpScene = pScene;

}

/*
void TilePass::resize(uint32_t width, uint32_t height)
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

void TilePass::execute(RenderContext::SharedPtr pRenderContext)
{
	Falcor::logWarning(std::string(" CAMERA SETTINGS ARE ") + std::to_string(mpScene->getActiveCamera()->getFarPlane()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT WIDTH = ") + std::to_string(mpResManager->getWidth()));
	Falcor::logWarning(std::string("INITIALIZATION - VIEWPORT HEIGHT = ") + std::to_string(mpResManager->getHeight()));

	// Get our output buffer; clear it to black.
	//Texture::SharedPtr outputTexture = mpResManager->getClearedTexture("Tiles", vec4(0.0f, 0.0f, 0.0f, 0.0f));
	//Texture::SharedPtr fullResZBuffer = mpResManager->getTexture("Z-Buffer");
	Texture::SharedPtr ZBuffer = mpResManager->getTexture("ZBuffer");
	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
	if (!ZBuffer) return;

	Fbo::SharedPtr outputFbo = mpResManager->createManagedFbo({"Tiles" }, "Z-Buffer2");
	// Failed to create a valid FBO?  We're done.
	if (!outputFbo) return;
	// Clear our color buffers to background color, depth to 1, stencil to 0
	pRenderContext->clearFbo(outputFbo.get(), vec4(0.5f, 0.5f, 0.5f, 1.0f), 1.0f, 0);

	// Set shader parameters for our accumulation pass
	auto shaderVars = mpTilingShader->getVars();
	
	shaderVars["gZBuffer"] = ZBuffer;
	shaderVars["cameraParametersCB"]["gFocalLength"] = mFocalLength;
	shaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	shaderVars["cameraParametersCB"]["gAperture"] = mAperture;
	shaderVars["cameraParametersCB"]["gSensorWidth"] = mSensorWidth;
	shaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();


	//shaderVars["gTileBuffer"] = outputTexture;

	/*
	shaderVars["PerFrameCB"]["gAccumCount"] = mAccumCount++;
	shaderVars["gLastFrame"] = mpLastFrame;
	shaderVars["gCurFrame"] = inputTexture;
	*/

	// ------------- my stuff ---------------
	mpGfxState->setFbo(outputFbo);
	//---------------------------------------
	// Execute the accumulation shader
	mpTilingShader->execute(pRenderContext, mpGfxState);

	//########################  Second pass -> dilate pass  ########################################
	Fbo::SharedPtr outputFbo2 = mpResManager->createManagedFbo({ "Dilate" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo2.get(), vec4(0.0f, 0.0f, 0.0f, 1.0f), 1.0f, 0);

	Texture::SharedPtr tiles = mpResManager->getTexture("Tiles");
	if (!tiles) return;

	auto dilateShaderVars = mpDilateShader->getVars();
	dilateShaderVars["gTiles"] = tiles;
	dilateShaderVars["textureParametersCB"]["width"] = (int)mpResManager->getWidth() / 20;
	dilateShaderVars["textureParametersCB"]["height"] = (int)mpResManager->getHeight() / 20;
	mpGfxState->setFbo(outputFbo2);
	mpDilateShader->execute(pRenderContext, mpGfxState);

	//########################  Third pass -> downPresort pass  ########################################
	
	
	Fbo::SharedPtr outputFbo3 = mpResManager->createManagedFbo({ "Half_res_color", "Presort_buffer", "Half_res_z_buffer" }, "Z-Buffer2");
	if (!outputFbo) return;
	pRenderContext->clearFbo(outputFbo3.get(), vec4(0.0f, 0.0f, 0.0f, 0.0f), 1.0f, 0);
	
	Texture::SharedPtr dilate = mpResManager->getTexture("Dilate");
	Texture::SharedPtr frameColor = mpResManager->getTexture("FrameColor");
	
	auto downPresortShaderVars = mpDownPresortShader->getVars();
	downPresortShaderVars["gDilate"] = dilate;
	downPresortShaderVars["gZBuffer"] = ZBuffer;
	downPresortShaderVars["gFrameColor"] = frameColor;
	downPresortShaderVars["cameraParametersCB"]["gFocalLength"] = mFocalLength;
	downPresortShaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	downPresortShaderVars["cameraParametersCB"]["gAperture"] = mAperture;
	downPresortShaderVars["cameraParametersCB"]["gSensorWidth"] = mSensorWidth;
	downPresortShaderVars["cameraParametersCB"]["gDepthRange"] = 1.0f;			//const of depth range here
	
	downPresortShaderVars["cameraParametersCB"]["gSinglePixelRadius"] = 0.7071f;	//const of pixel radius
	
	downPresortShaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();
	downPresortShaderVars["cameraParametersCB"]["gTextureHeight"] = (float)mpResManager->getHeight();
	downPresortShaderVars["cameraParametersCB"]["gNear"] = mpScene->getActiveCamera()->getNearPlane();
	downPresortShaderVars["cameraParametersCB"]["gFar"] = mpScene->getActiveCamera()->getFarPlane();
	downPresortShaderVars["cameraParametersCB"]["gStrengthTweak"] = 0.5f;


	
	//Setup a clean sampler through the API
	Sampler::SharedPtr mpSampler;
	Sampler::Desc samplerDesc;
	ProgramReflection::SharedConstPtr pReflectorDownPresortPass;
	ParameterBlockReflection::BindLocation samplerBindLocation;

	samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Point).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border);
	//samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Point).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border).setLodParams(0.0f, 0.0f, 0.0f);
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

	

	//shader vars setup
	auto mainPassShaderVars = mpMainPassShader->getVars();
	mainPassShaderVars["gDilate"] = dilate;
	mainPassShaderVars["gHalfResZBuffer"] = HalfResZBuffer;
	mainPassShaderVars["gHalfResFrameColor"] = halfResColor;
	mainPassShaderVars["gPresortBuffer"] = presortBuffer;
	mainPassShaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	mainPassShaderVars["cameraParametersCB"]["gOffset"] = 0.01f; //FAKE VALUE , NEED COMPUTATION HERE
	mainPassShaderVars["cameraParametersCB"]["gTextureWidth"] = (float)mpResManager->getWidth();
	mainPassShaderVars["cameraParametersCB"]["gTextureHeight"] = (float)mpResManager->getHeight();

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

	

	/*
	
	std::vector<float> test(3);
	test[0] = 1.2f;
	//mainPassShaderVars["cameraParametersCB"]["gkernel"] = test; //FAKE VALUE , NEED COMPUTATION HERE
	GraphicsVars::SharedPtr mpVars = GraphicsVars::create(pReflectorMainPass);
	TypedBuffer<float>::SharedPtr pBuf = TypedBuffer<float>::create(3, Resource::BindFlags::ShaderResource);
	pBuf[0] = 1.2f;
	pBuf[1] = 1.0f;
	pBuf[2] = 1.0f;
	bool succeed = mpVars->setTypedBuffer("weights", pBuf);
	Falcor::logWarning(std::string("buffer success ? = ") + std::to_string(succeed));
	pRenderContext->pushGraphicsVars(mpVars);
	*/
	
	mpGfxState->setFbo(outputFbo4);
	mpMainPassShader->execute(pRenderContext, mpGfxState);
}