//
//  WindowRenderData.swift
//  Depthtop
//
//  Shared data structure for passing window render information
//

import Metal
import simd

// Window render data that can be passed across actor boundaries
struct WindowRenderData {
    let texture: MTLTexture
    let textureGPUResourceID: MTLResourceID  // Restored for Metal 4 argument tables
    let modelMatrix: float4x4
}