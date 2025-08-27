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
    struct WindowUniforms uniforms[2];  // One for each eye (384 bytes)
    uint16_t windowID;           // ID for this window (2 bytes)
    uint16_t isHovered;          // Whether this window is currently hovered (2 bytes)
    uint32_t padding;            // Padding to ensure proper alignment (4 bytes)
    float hoverProgress;         // Animation progress (4 bytes)
    uint32_t padding2;           // Additional padding to reach 400 bytes total (4 bytes)
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