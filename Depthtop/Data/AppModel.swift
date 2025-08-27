//
//  AppModel.swift
//  Depthtop
//
//  Maintains app-wide state, merging CS_HoverEffect architecture
//  with Depthtop's window capture functionality
//

import SwiftUI
import ScreenCaptureKit
import Metal
import simd
import CompositorServices

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    // MARK: - Immersive Space Management (from CS_HoverEffect)
    static let immersiveSpaceId = "ImmersiveSpace"
    var isImmersiveSpaceOpen = false
    
    // Backward compatibility
    var immersiveSpaceID: String { Self.immersiveSpaceId }
    
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // Immersion style control (full vs progressive)
    var useProgressiveImmersion: Bool = false  // Default to full for stability
    
    // MARK: - Window Capture Management (from original Depthtop)
    let windowCaptureManager = WindowCaptureManager()
    
    // Captured windows that will be rendered in the immersive space
    var capturedWindows: [CapturedWindow] = []
    
    // Layout configuration for windows in 3D space
    var windowArrangement: WindowArrangement = .grid
    
    // Preview state
    var previewNeedsUpdate = false
    var previewQuality: PreviewQuality = .medium
    
    // MARK: - Rendering Configuration (from CS_HoverEffect)
    var foveation: Bool = true
    var resolution: Double = 1.0
    var overrideResolution: Bool = false
    
    // Hover effect configuration - ENABLED for window interaction!
    var withHover: Bool = true   // Enable hover effects for windows
    var useMSAA: Bool = true     // Enable MSAA for better hover tracking
    var debugColors: Bool = false // Debug visualization of hover areas
    
    // Hover state tracking
    var hoveredWindowID: CGWindowID? = nil
    var hoverProgress: Float = 0.0
    
    enum PreviewQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
    
    enum WindowArrangement {
        case grid
        case curved
        case stack
    }
    
    init() {
        configureLogging()
        setupWindowCaptureCallbacks()
    }
    
    private func configureLogging() {
        // Configure the logger for normal operation - suppress verbose debug output
        Logger.shared.setNormalMode()  // Shows info, warning, error
        
        // You can customize which categories to see:
        // Logger.shared.enabledCategories = [.capture, .rendering, .error]
        
        // Or set a different log level:
        // Logger.shared.setDebugMode()  // Shows everything for debugging
        // Logger.shared.setSilentMode() // Only errors
        
        Logger.shared.info("Depthtop initialized with logging level: \(Logger.shared.logLevel)", category: .none)
    }
    
    // MARK: - Window Management
    
    func refreshWindows() async {
        Logger.shared.info("Refreshing windows...", category: .capture)
        await windowCaptureManager.refreshAvailableWindows()
        Logger.shared.info("Window refresh complete", category: .capture)
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
            let newWindow = CapturedWindow(window: window, texture: nil, lastUpdate: Date())
            self.capturedWindows.append(newWindow)
            Logger.shared.info("Added captured window: \(window.title ?? "Unknown")", category: .capture)
        }
        
        // Set up callback to remove a window when capture stops
        windowCaptureManager.onCaptureStopped = { [weak self] windowID in
            self?.capturedWindows.removeAll { $0.window.windowID == windowID }
            Logger.shared.info("Removed captured window with ID: \(windowID)", category: .capture)
        }
        
        // Set up callback to update a window with a new Metal texture
        windowCaptureManager.onFrameUpdated = { [weak self] windowID, texture, contentRect, contentScale, scaleFactor in
            guard let self = self else { return }
            if let index = self.capturedWindows.firstIndex(where: { $0.window.windowID == windowID }) {
                let isFirstTexture = self.capturedWindows[index].texture == nil
                self.capturedWindows[index].texture = texture
                self.capturedWindows[index].contentRect = contentRect
                self.capturedWindows[index].contentScale = contentScale
                self.capturedWindows[index].scaleFactor = scaleFactor
                self.capturedWindows[index].lastUpdate = Date()
                
                // Texture is already stored above
                
                if isFirstTexture {
                    Logger.shared.info("First texture received for window: \(self.capturedWindows[index].window.title ?? "Unknown")", category: .rendering)
                }
                
                // Notify that preview needs update
                self.notifyPreviewUpdate()
            }
        }
        
        // Note: IOSurface callback removed - we're using MTLTexture directly now
    }
}

// MARK: - WindowArrangement Extension
extension AppModel.WindowArrangement {
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