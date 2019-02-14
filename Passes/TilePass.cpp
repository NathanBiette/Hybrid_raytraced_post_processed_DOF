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
	int32_t width = (int32_t)mpResManager->getWidth();
	int32_t height = (int32_t)mpResManager->getHeight();
	printf("width = %d /n", width);
	printf("height = %d /n", height);
	//mpResManager->requestTextureResource("Tiles", ResourceFormat::R32Float,(Falcor::Resource::BindFlags)112U,500,500); //specifying size seems to work well
	mpResManager->requestTextureResource("Tiles", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); //specifying size seems to work well
	mpResManager->requestTextureResource("Dilate", ResourceFormat::RG16Float,(Falcor::Resource::BindFlags)112U, width / 20 , height / 20); 
	
	//mpResManager->requestTextureResource("Tiles", ResourceFormat::R32Float);
	//mpResManager->requestTextureResource("Tiles");
	mpResManager->requestTextureResource("Z-Buffer2", ResourceFormat::D24UnormS8, ResourceManager::kDepthBufferFlags);
	//mpResManager->requestTextureResource("Z-Buffer");

	// Create our graphics state and an tiling shader
	mpGfxState = GraphicsState::create();
	mpTilingShader = FullscreenLaunch::create(kTilingShader);
	mpDilateShader = FullscreenLaunch::create(kDilateShader);
	return true;
}

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

void TilePass::execute(RenderContext::SharedPtr pRenderContext)
{
	// Get our output buffer; clear it to black.
	//Texture::SharedPtr outputTexture = mpResManager->getClearedTexture("Tiles", vec4(0.0f, 0.0f, 0.0f, 0.0f));
	Texture::SharedPtr inputTexture = mpResManager->getTexture("Z-Buffer");
	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
	if (!inputTexture) return;

	Fbo::SharedPtr outputFbo = mpResManager->createManagedFbo({"Tiles" }, "Z-Buffer2");
	// Failed to create a valid FBO?  We're done.
	if (!outputFbo) return;
	// Clear our color buffers to background color, depth to 1, stencil to 0
	pRenderContext->clearFbo(outputFbo.get(), vec4(0.5f, 0.5f, 0.5f, 1.0f), 1.0f, 0);

	// Set shader parameters for our accumulation pass
	auto shaderVars = mpTilingShader->getVars();
	
	shaderVars["gZBuffer"] = inputTexture;
	shaderVars["cameraParametersCB"]["gFocalLength"] = mFocalLength;
	shaderVars["cameraParametersCB"]["gDistanceToFocalPlane"] = mDistFocalPlane;
	shaderVars["cameraParametersCB"]["gAperture"] = mAperture;

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
	dilateShaderVars["textureParametersCB"]["width"] = (int)mpResManager->getWidth();
	dilateShaderVars["textureParametersCB"]["height"] = (int)mpResManager->getHeight();
	mpGfxState->setFbo(outputFbo2);
	mpDilateShader->execute(pRenderContext, mpGfxState);

}