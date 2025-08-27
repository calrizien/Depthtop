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
struct WindowUniformsArray {
    var uniforms: (WindowUniforms, WindowUniforms)  // Tuple for both eyes
    var windowID: UInt16           // ID for this window (used for hover tracking)
    var isHovered: UInt16          // Whether this window is currently hovered
    var hoverProgress: Float      // Animation progress (0.0 to 1.0)
    
    init() {
        let identity = simd_float4x4(1)
        let emptyUniforms = WindowUniforms(
            modelMatrix: identity,
            viewMatrix: identity,
            projectionMatrix: identity
        )
        self.uniforms = (emptyUniforms, emptyUniforms)
        self.windowID = 0
        self.isHovered = 0
        self.hoverProgress = 0.0
    }
    
    /// Access uniforms by index (for easier iteration)
    mutating func setUniforms(at index: Int, uniforms: WindowUniforms) {
        if index == 0 {
            self.uniforms.0 = uniforms
        } else if index == 1 {
            self.uniforms.1 = uniforms
        }
    }
}