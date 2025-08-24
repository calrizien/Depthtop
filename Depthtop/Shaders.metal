//
//  Shaders.metal
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               ushort amp_id [[amplification_id]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               constant ViewProjectionArray & viewProjectionArray [[ buffer(BufferIndexViewProjection) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = viewProjectionArray.viewProjectionMatrix[amp_id] * uniforms.modelMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(colorSample);
}

// MARK: - Window Capture Shaders

// Shader specifically for rendering captured window textures
vertex ColorInOut windowVertexShader(Vertex in [[stage_in]],
                                     ushort amp_id [[amplification_id]],
                                     constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                                     constant ViewProjectionArray & viewProjectionArray [[ buffer(BufferIndexViewProjection) ]])
{
    ColorInOut out;
    
    float4 position = float4(in.position, 1.0);
    out.position = viewProjectionArray.viewProjectionMatrix[amp_id] * uniforms.modelMatrix * position;
    out.texCoord = in.texCoord;
    
    return out;
}

// Fragment shader for captured windows with proper BGRA handling
fragment float4 windowFragmentShader(ColorInOut in [[stage_in]],
                                     texture2d<float> windowTexture [[ texture(TextureIndexColor) ]])
{
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
    
    // The texture from ScreenCaptureKit is in BGRA format
    // Metal handles this automatically, but we ensure full opacity
    color.a = 1.0;
    
    return color;
}

// MARK: - Preview Shaders

struct PreviewVertex {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct PreviewUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

struct PreviewVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex PreviewVertexOut previewVertexShader(uint vertexID [[vertex_id]],
                                           constant float *vertices [[buffer(0)]],
                                           constant PreviewUniforms &uniforms [[buffer(1)]]) {
    PreviewVertexOut out;
    
    // Read vertex data (position + texcoord)
    int baseIndex = vertexID * 5;
    float3 position = float3(vertices[baseIndex], vertices[baseIndex + 1], vertices[baseIndex + 2]);
    float2 texCoord = float2(vertices[baseIndex + 3], vertices[baseIndex + 4]);
    
    float4 worldPosition = uniforms.modelMatrix * float4(position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.texCoord = texCoord;
    
    return out;
}

fragment float4 previewFragmentShader(PreviewVertexOut in [[stage_in]],
                                     texture2d<half> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    if (!is_null_texture(texture)) {
        return float4(texture.sample(textureSampler, in.texCoord));
    } else {
        // Default gray color if no texture
        return float4(0.3, 0.3, 0.3, 1.0);
    }
}
