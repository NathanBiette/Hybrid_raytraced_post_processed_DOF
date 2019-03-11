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