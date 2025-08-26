//
//  SIMD+Utilities.swift
//  Depthtop
//
//  Math utilities for SIMD operations
//

import simd
import Spatial
import RealityKit

extension simd_float4x4 {
    /// Creates a perspective projection matrix
    static func perspectiveProjection(fovRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let h = 1 / tan(fovRadians * 0.5)
        let w = h / aspectRatio
        let zRange = farZ - nearZ
        
        return simd_float4x4(
            [w, 0, 0, 0],
            [0, h, 0, 0],
            [0, 0, -(farZ + nearZ) / zRange, -1],
            [0, 0, -(2 * farZ * nearZ) / zRange, 0]
        )
    }
    
    /// Creates a look-at matrix
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        return simd_float4x4(
            [x.x, y.x, z.x, 0],
            [x.y, y.y, z.y, 0],
            [x.z, y.z, z.z, 0],
            [-dot(x, eye), -dot(y, eye), -dot(z, eye), 1]
        )
    }
}

extension Transform {
    /// Converts the transform to a 4x4 matrix
    var matrix: simd_float4x4 {
        let scaleMatrix = simd_float4x4(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
        let rotationMatrix = simd_float4x4(rotation)
        let translationMatrix = simd_float4x4(
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [translation.x, translation.y, translation.z, 1]
        )
        return translationMatrix * rotationMatrix * scaleMatrix
    }
}