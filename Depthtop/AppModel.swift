//
//  AppModel.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import SwiftUI
import ScreenCaptureKit

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // Window capture management
    let windowCaptureManager = WindowCaptureManager()
    
    // Captured windows that will be rendered in the immersive space
    var capturedWindows: [CapturedWindow] {
        windowCaptureManager.capturedWindows
    }
    
    // Layout configuration for windows in 3D space
    var windowArrangement: WindowArrangement = .grid
    
    enum WindowArrangement {
        case grid
        case curved
        case stack
        
        func calculatePosition(for index: Int, total: Int) -> SIMD3<Float> {
            switch self {
            case .grid:
                // Arrange windows in a grid pattern
                let columns = 3
                let row = index / columns
                let col = index % columns
                let spacing: Float = 3.0
                let x = Float(col - 1) * spacing
                let y = Float(1 - row) * spacing * 0.7
                let z: Float = -5.0
                return SIMD3<Float>(x, y, z)
                
            case .curved:
                // Arrange windows in a curved arc
                let angle = Float(index) / Float(max(total - 1, 1)) * .pi * 0.5 - .pi * 0.25
                let radius: Float = 5.0
                let x = sin(angle) * radius
                let z = -cos(angle) * radius - 2.0
                let y: Float = 0
                return SIMD3<Float>(x, y, z)
                
            case .stack:
                // Stack windows with depth offset
                let x: Float = 0
                let y: Float = 0
                let z = -3.0 - Float(index) * 0.5
                return SIMD3<Float>(x, y, z)
            }
        }
    }
    
    func refreshWindows() async {
        await windowCaptureManager.refreshAvailableWindows()
    }
    
    func startCapture(for window: SCWindow) async {
        await windowCaptureManager.startCapture(for: window)
        updateWindowPositions()
    }
    
    func stopCapture(for window: SCWindow) async {
        await windowCaptureManager.stopCapture(for: window)
        updateWindowPositions()
    }
    
    func stopAllCaptures() async {
        await windowCaptureManager.stopAllCaptures()
    }
    
    func updateWindowPositions() {
        let windows = capturedWindows
        for (index, window) in windows.enumerated() {
            window.position = windowArrangement.calculatePosition(
                for: index,
                total: windows.count
            )
        }
    }
}
