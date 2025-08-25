//
//  AppModel.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import SwiftUI
import ScreenCaptureKit
import Metal
import simd

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
    
    init() {
        setupWindowCaptureCallbacks()
    }
    
    // Captured windows that will be rendered in the immersive space
    // Now owned by AppModel instead of referencing WindowCaptureManager
    var capturedWindows: [CapturedWindow] = []
    
    // Layout configuration for windows in 3D space
    var windowArrangement: WindowArrangement = .grid
    
    // Preview state
    var previewNeedsUpdate = false
    var previewQuality: PreviewQuality = .medium
    
    enum PreviewQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
    
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
        print("🔄 AppModel: Refreshing windows...")
        await windowCaptureManager.refreshAvailableWindows()
        print("✅ AppModel: Window refresh complete")
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
        // Notify that preview needs update
        previewNeedsUpdate = true
    }
    
    // Preview coordination
    func notifyPreviewUpdate() {
        previewNeedsUpdate = true
    }
    
    func getWindowRenderData() -> [WindowRenderData] {
        // Note: This function is not used in the current implementation
        // The renderer now creates textures from IOSurface directly
        return []
    }
    
    private func setupWindowCaptureCallbacks() {
        // Set up callback to add a new window when capture starts
        windowCaptureManager.onCaptureStarted = { [weak self] window in
            guard let self = self else { return }
            let newWindow = CapturedWindow(window: window, surface: nil, lastUpdate: Date())
            self.capturedWindows.append(newWindow)
            print("✅ AppModel: Added captured window: \(window.title ?? "Unknown")")
        }
        
        // Set up callback to remove a window when capture stops
        windowCaptureManager.onCaptureStopped = { [weak self] windowID in
            self?.capturedWindows.removeAll { $0.window.windowID == windowID }
            print("✅ AppModel: Removed captured window with ID: \(windowID)")
        }
        
        // Set up callback to update a window with a new IOSurface
        windowCaptureManager.onFrameUpdated = { [weak self] windowID, surface, contentRect, contentScale, scaleFactor in
            guard let self = self else { return }
            if let index = self.capturedWindows.firstIndex(where: { $0.window.windowID == windowID }) {
                let isFirstSurface = self.capturedWindows[index].surface == nil
                self.capturedWindows[index].surface = surface
                self.capturedWindows[index].contentRect = contentRect
                self.capturedWindows[index].contentScale = contentScale
                self.capturedWindows[index].scaleFactor = scaleFactor
                self.capturedWindows[index].lastUpdate = Date()
                
                if isFirstSurface {
                    print("✅ AppModel: First IOSurface set for window: \(self.capturedWindows[index].title)")
                }
            }
        }
    }
}
