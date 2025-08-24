//
//  WindowCaptureManager.swift
//  Depthtop
//
//  Manages window capture using ScreenCaptureKit
//

import Foundation
import ScreenCaptureKit
import Metal
import CoreVideo
import CoreGraphics
import SwiftUI

@MainActor
@Observable
class WindowCaptureManager: NSObject {
    var availableWindows: [SCWindow] = []
    var capturedWindows: [CapturedWindow] = []
    var isCapturing = false
    
    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    private var streams: [SCWindow: SCStream] = [:]
    private var streamOutputs: [SCWindow: StreamOutput] = [:]  // Keep strong reference to outputs
    private let queue = DispatchQueue(label: "WindowCaptureManager.queue")
    
    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        self.device = device
        super.init()
        
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }
    
    func refreshAvailableWindows() async {
        do {
            let content = try await SCShareableContent.current
            
            // Filter out our own app and system windows
            let ourBundleID = Bundle.main.bundleIdentifier
            let windows = content.windows.filter { window in
                // Exclude our own windows
                if let app = window.owningApplication,
                   app.bundleIdentifier == ourBundleID {
                    return false
                }
                
                // Exclude windows that are too small or off-screen
                let frame = window.frame
                if frame.width < 100 || frame.height < 100 {
                    return false
                }
                
                // Only include windows with titles
                return window.title != nil && !window.title!.isEmpty
            }
            
            await MainActor.run {
                self.availableWindows = windows
            }
        } catch {
            print("Failed to get shareable content: \(error)")
        }
    }
    
    func startCapture(for window: SCWindow) async {
        guard !isWindowBeingCaptured(window) else { 
            print("Window already being captured: \(window.title ?? "Unknown")")
            return 
        }
        
        print("Starting capture for window: \(window.title ?? "Unknown") - ID: \(window.windowID)")
        
        do {
            // Configure the stream
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width) * 2 // Retina resolution
            config.height = Int(window.frame.height) * 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.capturesAudio = false
            config.showsCursor = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS
            
            print("Stream config: \(config.width)x\(config.height) @ 60fps")
            
            // Create filter for the specific window
            let filter = SCContentFilter(desktopIndependentWindow: window)
            
            // Create and configure stream
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Create output handler
            let output = StreamOutput(window: window, captureManager: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            
            // Start capture
            try await stream.startCapture()
            
            await MainActor.run {
                self.streams[window] = stream
                self.streamOutputs[window] = output  // Store the output to prevent deallocation
                let capturedWindow = CapturedWindow(
                    window: window,
                    texture: nil,
                    lastUpdate: Date()
                )
                self.capturedWindows.append(capturedWindow)
                self.isCapturing = true
            }
            
        } catch {
            print("Failed to start capture for window: \(error)")
        }
    }
    
    func stopCapture(for window: SCWindow) async {
        guard let stream = streams[window] else { return }
        
        do {
            try await stream.stopCapture()
            
            await MainActor.run {
                self.streams.removeValue(forKey: window)
                self.streamOutputs.removeValue(forKey: window)  // Remove the output reference
                self.capturedWindows.removeAll { $0.window.windowID == window.windowID }
                
                if self.streams.isEmpty {
                    self.isCapturing = false
                }
            }
            
        } catch {
            print("Failed to stop capture: \(error)")
        }
    }
    
    func stopAllCaptures() async {
        for window in streams.keys {
            await stopCapture(for: window)
        }
    }
    
    private func isWindowBeingCaptured(_ window: SCWindow) -> Bool {
        return capturedWindows.contains { $0.window.windowID == window.windowID }
    }
    
    func updateTexture(for window: SCWindow, with sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cache = textureCache else { 
            print("Failed to get pixel buffer or texture cache")
            return 
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Failed to create Metal texture from pixel buffer (status: \(status))")
            return
        }
        
        print("Successfully created texture for window \(window.title ?? "Unknown") - size: \(width)x\(height)")
        
        Task { @MainActor in
            if let index = self.capturedWindows.firstIndex(where: { $0.window.windowID == window.windowID }) {
                self.capturedWindows[index].texture = texture
                self.capturedWindows[index].lastUpdate = Date()
                print("Updated texture for captured window: \(self.capturedWindows[index].title)")
            } else {
                print("Warning: Received texture update for non-captured window")
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension WindowCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        
        Task { @MainActor in
            // Find and remove the stream
            if let window = self.streams.first(where: { $0.value === stream })?.key {
                self.streams.removeValue(forKey: window)
                self.streamOutputs.removeValue(forKey: window)  // Remove the output reference
                self.capturedWindows.removeAll { $0.window.windowID == window.windowID }
            }
            
            if self.streams.isEmpty {
                self.isCapturing = false
            }
        }
    }
}

// MARK: - Stream Output Handler

private class StreamOutput: NSObject, SCStreamOutput {
    weak var window: SCWindow?
    weak var captureManager: WindowCaptureManager?
    private var frameCount = 0
    
    init(window: SCWindow, captureManager: WindowCaptureManager) {
        self.window = window
        self.captureManager = captureManager
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let window = window,
              let captureManager = captureManager else { 
            print("StreamOutput: Skipping frame - type: \(type), window: \(window != nil), manager: \(captureManager != nil)")
            return 
        }
        
        // Log only periodically to avoid spam
        frameCount += 1
        if frameCount % 60 == 0 {  // Log every 60 frames (once per second at 60fps)
            print("StreamOutput: Received frame \(frameCount) for window: \(window.title ?? "Unknown")")
        }
        
        captureManager.updateTexture(for: window, with: sampleBuffer)
    }
}