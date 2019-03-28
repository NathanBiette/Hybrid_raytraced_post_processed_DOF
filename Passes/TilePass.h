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
#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/FullscreenLaunch.h"

class TilePass : public RenderPass, inherit_shared_from_this<RenderPass, TilePass>
{
public:
	using SharedPtr = std::shared_ptr<TilePass>;

	static SharedPtr create();
	virtual ~TilePass() = default;

protected:
	TilePass();

	//Thin lens parameters
	float mFNumber = 2.0f;						// f number (typeless) = F/A (A = aperture)
	float mFocalLength = 0.1f;					// here we take 50mm of focal length 
	float mDistFocalPlane = 1.0f;				// What is our distance to focal plane (meaning where we focus on, 1m here)
	float mAperture = mFocalLength / mFNumber;	//the diameter of the lens in thin lens model
	//full frame camera = 36x24 mm 
	//float mSensorWidth = 0.036f;
	float mSensorWidth = 2.0f * mFocalLength * mDistFocalPlane / (mDistFocalPlane - mFocalLength);
	float mImageWidth = 1920.0f;
	//near and far limits of focus zone
	float mNearLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength + (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);
	float mFarLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength - (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);

	float mDepthRange = 0.1f;
	//float mDepthRange = 1.0f;

	// Implementation of SimpleRenderPass interface
	bool initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void execute(RenderContext::SharedPtr pRenderContext) override;
	//void resize(uint32_t width, uint32_t height) override;
	void initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene);

	// The RenderPass class defines various methods we can override to specify this pass' properties. 
	bool appliesPostprocess() override { return true; }
	bool requiresScene() override { return true; }

	// Shaders
	FullscreenLaunch::SharedPtr   mpTilingShader;
	FullscreenLaunch::SharedPtr   mpDilateShader;
	FullscreenLaunch::SharedPtr   mpDownPresortShader;
	FullscreenLaunch::SharedPtr   mpMainPassShader;
	// State for our accumulation shader
	GraphicsState::SharedPtr      mpGfxState;
	Texture::SharedPtr            mpLastFrame;
	Fbo::SharedPtr                mpInternalFbo;
	
	Scene::SharedPtr            mpScene;                ///< A pointer to the scene we're rendering
	GraphicsVars::SharedPtr		mpVars;
	Texture::SharedPtr mptest;
	uint32_t   mFrameCount = 0xdeadbeef;
};
