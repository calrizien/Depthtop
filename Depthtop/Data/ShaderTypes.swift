//
//  ShaderTypes.swift
//  Depthtop
//
//  Swift versions of shader types for Metal rendering
//

import simd

/// Window rendering uniforms for a single eye/view
struct WindowUniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
}

/// Window rendering uniforms array for stereoscopic rendering with hover
/// Must match the C struct layout exactly for Metal compatibility
struct WindowUniformsArray {
    // Using explicit fields instead of tuple for C-compatible memory layout
    var uniforms0: WindowUniforms  // First eye uniforms (192 bytes)
    var uniforms1: WindowUniforms  // Second eye uniforms (192 bytes)
    var windowID: UInt16           // ID for this window (2 bytes)
    var isHovered: UInt16          // Whether this window is currently hovered (2 bytes)
    var padding: UInt32 = 0        // Padding to match C struct alignment (4 bytes)
    var hoverProgress: Float       // Animation progress (4 bytes)
    var padding2: UInt32 = 0       // Additional padding to reach 400 bytes total (4 bytes)
    
    init() {
        let identity = simd_float4x4(1)
        let emptyUniforms = WindowUniforms(
            modelMatrix: identity,
            viewMatrix: identity,
            projectionMatrix: identity
        )
        self.uniforms0 = emptyUniforms
        self.uniforms1 = emptyUniforms
        self.windowID = 0
        self.isHovered = 0
        self.padding = 0
        self.hoverProgress = 0.0
        self.padding2 = 0
    }
    
    /// Access uniforms by index (for easier iteration)
    mutating func setUniforms(at index: Int, uniforms: WindowUniforms) {
        if index == 0 {
            self.uniforms0 = uniforms
        } else if index == 1 {
            self.uniforms1 = uniforms
        }
    }
}