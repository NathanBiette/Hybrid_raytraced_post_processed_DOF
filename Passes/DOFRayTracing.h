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

// This render pass updates the "RayTracedGBufferPass" from Tutorial #4 to include both camera 
//      jitter (as in Tutorial #7) as well as a thin-lens camera approximation.  This allows the
//      viewer to specify a focal length and f-number (which is a photographic method of setting
//      the camera aperature size).  When combined with temporal accumulation, this allows 
//      rendering of antialiased images with variable, user-controllable depth-of-field.

#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/RayLaunch.h"
#include <random>

class DOFRayTracing : public RenderPass, inherit_shared_from_this<RenderPass, DOFRayTracing>
{
public:
	using SharedPtr = std::shared_ptr<DOFRayTracing>;
	using SharedConstPtr = std::shared_ptr<const DOFRayTracing>;

	static SharedPtr create() { return SharedPtr(new DOFRayTracing()); }
	virtual ~DOFRayTracing() = default;

protected:
	DOFRayTracing() : RenderPass("DOF Ray Tracing") {}

	// Implementation of RenderPass interface
	bool initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void execute(RenderContext::SharedPtr pRenderContext) override;
	void initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene) override;

	// The RenderPass class defines various methods we can override to specify this pass' properties. 
	bool requiresScene() override { return true; }
	bool usesRayTracing() override { return true; }

	// Internal pass state
	RayLaunch::SharedPtr        mpRays;            ///< Our wrapper around a DX Raytracing pass
	RtScene::SharedPtr          mpScene;           ///< A copy of our scene

												   //Thin lens parameters
	float mFNumber = 2.0f;						// f number (typeless) = F/A (A = aperture)
	float mFocalLength = 0.1f;					// here we take 50mm of focal length 
	float mDistFocalPlane = 1.0f;				// What is our distance to focal plane (meaning where we focus on, 1m here)
	float mAperture = mFocalLength / mFNumber;	//the diameter of the lens in thin lens model
												//full frame camera = 36x24 mm 

	/*
	Sensor width is determined by fov of raster camera to be coherent.
	sensor width = 2*f*distFocalPlane/(distFocalPlane - f)*tan(fovAngleHorizon/2)
	here we assume fovAngleHorizon = 90 degrees
	*/
	float mSensorWidth = 2.0f * mFocalLength * mDistFocalPlane / (mDistFocalPlane - mFocalLength);
	/*16:9 ratio here*/
	float mSensorHeight = mSensorWidth * 9.0f / 16.0f;
	float mImageWidth = 1920.0f;
	//near and far limits of focus zone
	float mNearLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength + (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);
	float mFarLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength - (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);
	  
    // State for our camera jitter and random number generator (if we're doing randomized samples)
	bool      mUseJitter = false;
	bool      mUseRandomJitter = false;
	std::uniform_real_distribution<float> mRngDist;     ///< We're going to want random #'s in [0...1] (the default distribution)
	std::mt19937 mRng;                                  ///< Our random number generate.  Set up in initialize()

	vec3      mBgColor = vec3(0.5f, 0.5f, 1.0f);
	uint32_t   mFrameCount = 0xdeadbeef;
	// set number of rays per pixels
	uint mNumRays = 64;
};
