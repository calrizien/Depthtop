//
//  CapturedWindow.swift
//  Depthtop
//
//  Model for captured window data
//

import Foundation
import ScreenCaptureKit
import Metal
import simd
import SwiftUI

@MainActor
@Observable
class CapturedWindow: Identifiable {
    let id = UUID()
    let window: SCWindow
    var texture: MTLTexture?
    var lastUpdate: Date
    var position: SIMD3<Float>
    var scale: Float
    var isSelected: Bool = false
    
    // Window metadata
    var title: String {
        window.title ?? "Unknown Window"
    }
    
    var appName: String {
        window.owningApplication?.applicationName ?? "Unknown App"
    }
    
    var aspectRatio: Float {
        Float(window.frame.width / window.frame.height)
    }
    
    var textureSize: SIMD2<Int> {
        if let texture = texture {
            return SIMD2<Int>(Int(texture.width), Int(texture.height))
        }
        return SIMD2<Int>(Int(window.frame.width * 2), Int(window.frame.height * 2))
    }
    
    init(window: SCWindow, texture: MTLTexture? = nil, lastUpdate: Date = Date()) {
        self.window = window
        self.texture = texture
        self.lastUpdate = lastUpdate
        
        // Default position in 3D space (will be arranged later)
        self.position = SIMD3<Float>(0, 0, -2)
        
        // Default scale based on window size
        let baseScale: Float = 2.0
        self.scale = baseScale * min(1.0, Float(window.frame.width) / 1920.0)
    }
    
    // Transform matrix for positioning in 3D space
    var modelMatrix: float4x4 {
        let translationMatrix = float4x4(translation: position)
        let scaleMatrix = float4x4(scale: SIMD3<Float>(scale * aspectRatio, scale, 1))
        return translationMatrix * scaleMatrix
    }
}

// MARK: - Matrix Helpers

extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }
    
    init(scale s: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}