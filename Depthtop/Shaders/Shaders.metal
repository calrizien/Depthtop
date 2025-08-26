//
//  Shaders.metal
//  Depthtop
//
//  Metal shaders for rendering captured windows in spatial view with hover effects
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

// Function constants for shader variations
constant bool use_hover_effect [[function_constant(FunctionConstantHoverEffect)]];
constant bool use_texture_array [[function_constant(FunctionConstantUseTextureArray)]];
constant bool not_texture_array = !use_texture_array;

// Fragment output for hover tracking
struct FragmentOut {
    float4 color [[color(0)]];
    uint16_t hoverIndex [[color(1)]];  // Window/object ID for hover tracking
};

// Vertex shader for window rendering with stereoscopic and hover support
vertex WindowVertexOut windowVertex(uint vertexID [[vertex_id]],
                                   uint instanceID [[instance_id]],
                                   constant WindowUniformsArray& uniformsArray [[buffer(0)]],
                                   uint ampID [[amplification_id]]) {
    WindowVertexOut out;
    
    // Get uniforms for this eye
    WindowUniforms uniforms = uniformsArray.uniforms[ampID];
    
    // Create a quad (two triangles) for the window
    float2 positions[] = {
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0, -1.0),  // Bottom-right
        float2( 1.0,  1.0),  // Top-right
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0,  1.0),  // Top-right
        float2(-1.0,  1.0),  // Top-left
    };
    
    // UV coordinates for texture mapping
    float2 texCoords[] = {
        float2(0.0, 1.0),  // Bottom-left (flipped Y for Metal)
        float2(1.0, 1.0),  // Bottom-right
        float2(1.0, 0.0),  // Top-right
        float2(0.0, 1.0),  // Bottom-left
        float2(1.0, 0.0),  // Top-right
        float2(0.0, 0.0),  // Top-left
    };
    
    // Get position and texture coordinate for this vertex
    float2 pos = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    
    // Scale the quad to window size (aspect ratio preserved)
    float windowWidth = 2.0;   // Base width in world units
    float windowHeight = 1.5;  // Base height in world units
    
    // Apply hover animation scale if this window is hovered
    float hoverScale = 1.0;
    if (use_hover_effect && uniformsArray.isHovered) {
        hoverScale = 1.0 + uniformsArray.hoverProgress * 0.1;  // Scale up to 110% when hovered
    }
    
    float4 localPos = float4(pos.x * windowWidth * 0.5 * hoverScale, 
                             pos.y * windowHeight * 0.5 * hoverScale, 
                             0.0, 1.0);
    
    // Transform to world space, then view space, then projection
    float4 worldPos = uniforms.modelMatrix * localPos;
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    
    // Pass through world position for lighting/effects
    out.worldPosition = worldPos.xyz;
    
    // Set viewport for stereoscopic rendering (use amplification ID for eye index)
    out.viewportIndex = ampID;
    
    return out;
}

// Fragment shader for window rendering with hover effects
fragment FragmentOut windowFragment(WindowVertexOut in [[stage_in]],
                                   texture2d<float> windowTexture [[texture(0)]],
                                   constant WindowUniformsArray& uniformsArray [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the window texture
    float4 color = windowTexture.sample(textureSampler, in.texCoord);
    
    // Apply hover highlight effect
    if (use_hover_effect && uniformsArray.isHovered) {
        // Add a subtle glow/highlight to hovered windows
        float3 highlightColor = float3(0.2, 0.4, 0.8);  // Blue-ish highlight
        float highlightStrength = uniformsArray.hoverProgress * 0.3;
        color.rgb = mix(color.rgb, color.rgb + highlightColor, highlightStrength);
        
        // Add edge glow
        float2 edgeDist = abs(in.texCoord - 0.5) * 2.0;
        float edgeFactor = max(edgeDist.x, edgeDist.y);
        if (edgeFactor > 0.9) {
            float edgeGlow = (edgeFactor - 0.9) * 10.0 * uniformsArray.hoverProgress;
            color.rgb += highlightColor * edgeGlow;
        }
    }
    
    // Apply some subtle shading based on position for depth cues
    float3 lightDir = normalize(float3(0.0, 1.0, 1.0));
    float3 normal = float3(0.0, 0.0, 1.0); // Windows face forward
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.8;
    float lighting = ambient + (1.0 - ambient) * diffuse;
    
    // Apply lighting (subtle for windows)
    color.rgb *= lighting;
    
    // Ensure alpha is 1.0 for opaque windows
    color.a = 1.0;
    
    return FragmentOut {
        color,
        uniformsArray.windowID  // Pass window ID for hover tracking
    };
}

// Tile resolver kernel for MSAA and hover tracking
kernel void block_resolve(imageblock<FragmentOut> block,
                          ushort2 tid [[thread_position_in_threadgroup]],
                          uint2 gid [[thread_position_in_grid]],
                          ushort array_index [[render_target_array_index]],
                          texture2d_array<uint16_t, access::write> resolvedTextureArray [[texture(0), function_constant(use_texture_array)]],
                          texture2d<uint16_t, access::write> resolvedTexture [[texture(0), function_constant(not_texture_array)]]) {
    
    const ushort pixelCount = block.get_num_colors(tid);
    ushort index = 0;
    
    // Find the topmost window ID at this pixel
    for (ushort i = 0; i < pixelCount; ++i) {
        const FragmentOut color = block.read(tid, i, imageblock_data_rate::color);
        index = max(index, color.hoverIndex);
    }
    
    // Write the resolved index to the tracking texture
    if (use_texture_array) {
        resolvedTextureArray.write(index, gid, array_index);
    } else {
        resolvedTexture.write(index, gid);
    }
}

// Simple pass-through vertex shader for debugging
vertex float4 debugVertex(uint vertexID [[vertex_id]]) {
    float2 positions[] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0),
        float2(-1.0, -1.0),
        float2( 1.0,  1.0),
        float2(-1.0,  1.0),
    };
    
    float2 pos = positions[vertexID];
    return float4(pos, 0.0, 1.0);
}

// Simple color fragment shader for debugging
fragment float4 debugFragment() {
    return float4(1.0, 0.0, 0.0, 1.0); // Red
}

// MARK: - Metal Preview Shaders for Mac testing

struct PreviewVertex {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct MetalPreviewUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

struct PreviewVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex PreviewVertexOut metalPreviewVertexShader(PreviewVertex in [[stage_in]],
                                                 constant MetalPreviewUniforms &uniforms [[buffer(1)]]) {
    PreviewVertexOut out;
    
    // Get vertex data from attributes
    float3 position = in.position;
    float2 texCoord = in.texCoord;
    
    // Transform position
    float4 worldPosition = uniforms.modelMatrix * float4(position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.texCoord = texCoord;
    
    return out;
}

fragment float4 metalPreviewFragmentShader(PreviewVertexOut in [[stage_in]],
                                          texture2d<float> windowTexture [[texture(0)]]) {
    constexpr sampler windowSampler(address::clamp_to_edge,
                                   mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    // Check if texture exists
    if (is_null_texture(windowTexture)) {
        // Return a dark gray placeholder if no texture
        return float4(0.2, 0.2, 0.2, 1.0);
    }
    
    // Sample the window texture
    float4 color = windowTexture.sample(windowSampler, in.texCoord);
    
    // Ensure full opacity
    color.a = 1.0;
    
    return color;
}