//
//  ShaderTypes.h
//  Depthtop
//
//  Shared types between Swift and Metal shaders with hover support
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Window rendering uniforms for a single eye/view
struct WindowUniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
};

// Window rendering uniforms array for stereoscopic rendering with hover
struct WindowUniformsArray {
    struct WindowUniforms uniforms[2];  // One for each eye
    uint16_t windowID;           // ID for this window (used for hover tracking)
    uint16_t isHovered;          // Whether this window is currently hovered
    float hoverProgress;         // Animation progress (0.0 to 1.0)
};

// Function constant indices
typedef enum FunctionConstant {
    FunctionConstantHoverEffect,
    FunctionConstantUseTextureArray,
    FunctionConstantDebugColors
} FunctionConstant;

#ifdef __METAL_VERSION__
// Metal-only types (not visible to Swift)
#include <metal_stdlib>
using namespace metal;

// Vertex output for window rendering (Metal only)
struct WindowVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 worldPosition;
    uint viewportIndex [[viewport_array_index]];
};
#endif

#endif /* ShaderTypes_h */