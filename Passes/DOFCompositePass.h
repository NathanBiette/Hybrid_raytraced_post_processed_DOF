#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/FullscreenLaunch.h"

class DOFCompositePass : public RenderPass, inherit_shared_from_this<RenderPass, DOFCompositePass>
{
public:
	using SharedPtr = std::shared_ptr<DOFCompositePass>;

	static SharedPtr create();
	virtual ~DOFCompositePass() = default;

protected:
	DOFCompositePass();

	bool initialize(RenderContext::SharedPtr pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void execute(RenderContext::SharedPtr pRenderContext) override;
	//void resize(uint32_t width, uint32_t height) override;
	void initScene(RenderContext::SharedPtr pRenderContext, Scene::SharedPtr pScene);

	// The RenderPass class defines various methods we can override to specify this pass' properties. 
	bool appliesPostprocess() override { return true; }
	bool requiresScene() override { return false; }

	float mFNumber = 2.0f;						// f number (typeless) = F/A (A = aperture)
	float mFocalLength = 0.1f;					// here we take 50mm of focal length 
	float mDistFocalPlane = 1.0f;				// What is our distance to focal plane (meaning where we focus on, 1m here)
	float mAperture = mFocalLength / mFNumber;	//the diameter of the lens in thin lens model
	float mSensorWidth = 2.0f * mFocalLength * mDistFocalPlane / (mDistFocalPlane - mFocalLength);
	float mImageWidth = 1920.0f;
	//near and far limits of focus zone
	float mNearLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength + (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);
	float mFarLimitFocusZone = mAperture * mFocalLength * mDistFocalPlane / (mAperture * mFocalLength - (float)sqrt(2) * (mDistFocalPlane - mFocalLength) * mSensorWidth / mImageWidth);

	// Shaders
	FullscreenLaunch::SharedPtr   mpCompositeShader;
	// State for our accumulation shader
	GraphicsState::SharedPtr      mpGfxState;
	Texture::SharedPtr            mpLastFrame;
	Fbo::SharedPtr                mpInternalFbo;

	Scene::SharedPtr            mpScene;                ///< A pointer to the scene we're rendering
	GraphicsVars::SharedPtr		mpVars;
	Texture::SharedPtr mptest;
};