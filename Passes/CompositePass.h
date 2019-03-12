#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/FullscreenLaunch.h"

class CompositePass : public RenderPass, inherit_shared_from_this<RenderPass, CompositePass>
{
public:
	using SharedPtr = std::shared_ptr<CompositePass>;

	static SharedPtr create();
	virtual ~CompositePass() = default;

protected:
	CompositePass();

	bool initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void execute(RenderContext::SharedPtr pRenderContext) override;
	//void resize(uint32_t width, uint32_t height) override;
	void initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene);

	// The RenderPass class defines various methods we can override to specify this pass' properties. 
	bool appliesPostprocess() override { return true; }
	bool requiresScene() override { return false; }

	float mFNumber = 2.0f;                  // f number (typeless) = F/A (A = aperture)
	float mFocalLength = 0.05f;              // here we take 50mm of focal length 
	float mDistFocalPlane = 1.0f;				// What is our distance to focal plane (meaning where we focus on, 1m here)
	float mAperture = mFocalLength / mFNumber;
	//full frame camera = 36x24 mm 
	float mSensorWidth = 0.036f;
	float mImageWidth = 1920.0f;
	//near and far limits of focus zone
	float mNearLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength + (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);
	float mFarLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength - (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);

	// Shaders
	FullscreenLaunch::SharedPtr   mpCompositeShader;
	FullscreenLaunch::SharedPtr   mpSobelShader;
	// State for our accumulation shader
	GraphicsState::SharedPtr      mpGfxState;
	Texture::SharedPtr            mpLastFrame;
	Fbo::SharedPtr                mpInternalFbo;

	Scene::SharedPtr            mpScene;                ///< A pointer to the scene we're rendering
	GraphicsVars::SharedPtr		mpVars;
	Texture::SharedPtr mptest;
};