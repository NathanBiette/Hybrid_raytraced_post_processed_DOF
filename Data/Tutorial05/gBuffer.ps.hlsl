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

// Falcor / Slang imports to include shared code and data structures
__import Shading;           // Imports ShaderCommon and DefaultVS, plus material evaluation
__import DefaultVS;         // VertexOut declaration

cbuffer cameraParametersCB
{
	float gNear;
	float gFar;
}

struct GBuffer
{
	float4 color    : SV_Target0;  // Our color goes in color buffer 0
	float depth : SV_Target1;
};

// Our main entry point for the g-buffer fragment shader.
GBuffer main(VertexOut vsOut, uint primID : SV_PrimitiveID, float4 pos : SV_Position)
{
	// This is a Falcor built-in that extracts data suitable for shading routines
	//     (see ShaderCommon.slang for the shading data structure and routines)
	ShadingData hitPt = prepareShadingData(vsOut, gMaterial, gCamera.posW);

	// Dump out our G buffer channels
	GBuffer gBufOut;
	gBufOut.color = float4(0.0, 0.0, 0.0, hitPt.opacity);


	// Get the shading resulting from all lights (sum diffuse and specular term of each lights contribution)
	for (int lightIndex = 0; lightIndex < gLightsCount; lightIndex++)
	{
		ShadingResult sr = evalMaterial(hitPt, gLights[lightIndex], 1.0);	//for now just don't put any shadows !!!
		gBufOut.color.rgb += sr.color.rgb;
	}

	//float4x4 worldMat = getWorldMat(vsOut);
	//float4 posW = mul(pos, worldMat);
	//gBufOut.depth = mul(posW, gCamera.viewProjMat).z;		//gCamera comes from shaderCommon injection, we get the pixel fragment in clip space here with view projection matrix applied to world pos
	gBufOut.depth = 2 * gFar * gNear / (gFar + gNear - (gFar - gNear) * (2 * pos.z - 1.0f));

	return gBufOut;
}


