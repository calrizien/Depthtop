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
    // Removed capturedWindows - now managed by AppModel
    var isCapturing = false
    
    // Callbacks for AppModel to receive updates  
    var onCaptureStarted: ((SCWindow) -> Void)?
    var onCaptureStopped: ((CGWindowID) -> Void)?
    var onFrameUpdated: ((CGWindowID, MTLTexture, CGRect, CGFloat, CGFloat) -> Void)?  // Changed to pass MTLTexture
    
    private var streams: [SCWindow: SCStream] = [:]
    private var streamOutputs: [SCWindow: StreamOutput] = [:]  // Keep strong reference to outputs
    private let queue = DispatchQueue(label: "WindowCaptureManager.queue")
    
    // Metal properties for efficient texture conversion
    private let metalDevice: MTLDevice?
    private var textureCache: CVMetalTextureCache?
    
    override init() {
        // Initialize Metal device
        self.metalDevice = MTLCreateSystemDefaultDevice()
        
        super.init()
        
        // Create CVMetalTextureCache for efficient texture conversion
        if let device = metalDevice {
            var cache: CVMetalTextureCache?
            let result = CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil, // cache attributes
                device,
                nil, // texture attributes
                &cache
            )
            
            if result == kCVReturnSuccess, let cache = cache {
                self.textureCache = cache
                print("✅ Created CVMetalTextureCache for efficient texture conversion")
                print("   Metal device: \(device.name)")
            } else {
                print("❌ Failed to create CVMetalTextureCache: \(result)")
                print("   Error code: \(result) (kCVReturnSuccess = \(kCVReturnSuccess))")
            }
        } else {
            print("❌ Failed to get Metal device")
        }
        
        print("🔧 Initializing WindowCaptureManager with Metal support")
        print("   Metal device available: \(metalDevice != nil)")
        print("   Texture cache available: \(textureCache != nil)")
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
                guard let title = window.title, !title.isEmpty else {
                    return false
                }
                
                // Exclude system/utility windows based on title patterns
                let excludedPatterns = [
                    "Wallpaper",
                    "Backstop",
                    "Shield",
                    "Display 1",
                    "Display 2",
                    "Packages Display",
                    "Offscreen",
                    "System Status Item Clone",
                    "underbelly",
                    "Menubar"
                ]
                
                for pattern in excludedPatterns {
                    if title.contains(pattern) {
                        return false
                    }
                }
                
                // Exclude windows from known system/utility apps
                if let bundleID = window.owningApplication?.bundleIdentifier {
                    let excludedBundleIDs = [
                        "com.apple.WindowServer",
                        "com.apple.dock",
                        "com.apple.finder", // Exclude desktop windows
                        "com.apple.systemuiserver",
                        "com.apple.controlcenter",
                        "com.apple.notificationcenterui"
                    ]
                    
                    for excludedID in excludedBundleIDs {
                        if bundleID.contains(excludedID) {
                            return false
                        }
                    }
                }
                
                return true
            }
            
            // Only print summary when we have reasonable window count
            if content.windows.count < 100 {
                print("📊 Found \(windows.count) real windows (filtered from \(content.windows.count) total)")
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
        
        // Limit concurrent streams based on research findings (3-8 recommended, 2-4 for full-res)
        let maxStreams = 4 // Conservative limit for full-resolution captures
        guard streams.count < maxStreams else {
            print("⚠️ Stream limit reached (\(maxStreams)). Cannot start capture for: \(window.title ?? "Unknown")")
            return
        }
        
        print("Starting capture for window: \(window.title ?? "Unknown") - ID: \(window.windowID) (current streams: \(streams.count))")
        
        do {
            // Configure the stream with optimized settings for Metal texture conversion
            let config = SCStreamConfiguration()
            
            // Calculate optimal resolution based on window size and display scale
            let windowFrame = window.frame
            let baseWidth = Int(windowFrame.width)
            let baseHeight = Int(windowFrame.height)
            
            // Use 2x for Retina displays, but cap at reasonable maximum
            let maxDimension = 2048  // Prevent excessive memory usage
            let scale = min(2.0, min(Double(maxDimension) / Double(baseWidth), Double(maxDimension) / Double(baseHeight)))
            
            config.width = Int(Double(baseWidth) * scale)
            config.height = Int(Double(baseHeight) * scale)
            
            // Use BGRA format which is optimal for Metal on Apple Silicon
            config.pixelFormat = kCVPixelFormatType_32BGRA
            
            // Set color space to match our Metal device capabilities
            config.colorSpaceName = CGColorSpace.displayP3  // Better color gamut for modern displays
            
            // Optimize for our use case
            config.capturesAudio = false
            config.showsCursor = false
            
            // Set frame rate for smooth capture but not excessive GPU load
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS for balance
            
            // Enable queue depth for better throughput
            config.queueDepth = 3
            
            print("📹 Stream config for '\(window.title ?? "Unknown")':")
            print("   Original size: \(baseWidth)x\(baseHeight)")
            print("   Capture size: \(config.width)x\(config.height) (scale: \(scale))")
            print("   Format: BGRA, Color space: Display P3, FPS: 30")
            
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
                // Notify AppModel that capture has started
                self.onCaptureStarted?(window)
                self.isCapturing = true
            }
            
        } catch {
            print("Failed to start capture for window: \(error)")
        }
    }
    
    func stopCapture(for window: SCWindow) async {
        guard let stream = streams[window] else { return }
        
        print("Stopping capture for window: \(window.title ?? "Unknown") - ID: \(window.windowID)")
        
        do {
            // Proper cleanup sequence based on research
            try await stream.stopCapture()
            
            // Remove stream output to prevent callbacks
            if let output = streamOutputs[window] {
                // SCStream automatically removes outputs when stopped, but we clean up our reference
                print("Cleaning up stream output for window: \(window.title ?? "Unknown")")
            }
            
            await MainActor.run {
                self.streams.removeValue(forKey: window)
                self.streamOutputs.removeValue(forKey: window)  // Remove the output reference
                // Notify AppModel that capture has stopped
                self.onCaptureStopped?(window.windowID)
                
                print("Stream cleanup complete. Remaining streams: \(self.streams.count)")
                
                if self.streams.isEmpty {
                    self.isCapturing = false
                }
            }
            
        } catch {
            print("Failed to stop capture: \(error)")
            // Still clean up references even on error
            await MainActor.run {
                self.streams.removeValue(forKey: window)
                self.streamOutputs.removeValue(forKey: window)
                // Notify AppModel that capture has stopped
                self.onCaptureStopped?(window.windowID)
                
                if self.streams.isEmpty {
                    self.isCapturing = false
                }
            }
        }
    }
    
    func stopAllCaptures() async {
        for window in streams.keys {
            await stopCapture(for: window)
        }
    }
    
    private func isWindowBeingCaptured(_ window: SCWindow) -> Bool {
        return streams.keys.contains { $0.windowID == window.windowID }
    }
    
    func updateTexture(for window: SCWindow, with sampleBuffer: CMSampleBuffer) {
        // Flush texture cache at the beginning of each frame update
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
        
        // Validate CMSampleBuffer first
        guard CMSampleBufferIsValid(sampleBuffer) else {
            print("❌ Invalid CMSampleBuffer for window: \(window.title ?? "Unknown")")
            return
        }
        
        // Check if buffer is ready
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("⚠️ CMSampleBuffer data not ready for window: \(window.title ?? "Unknown")")
            return
        }
        
        // Extract pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ No pixel buffer in CMSampleBuffer for window: \(window.title ?? "Unknown")")
            return
        }
        
        // Verify pixel buffer format
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat != kCVPixelFormatType_32BGRA {
            print("⚠️ Unexpected pixel format: \(pixelFormat) (expected \(kCVPixelFormatType_32BGRA))")
            let fourCC = String(format: "%c%c%c%c",
                               UInt8((pixelFormat >> 24) & 0xFF),
                               UInt8((pixelFormat >> 16) & 0xFF),
                               UInt8((pixelFormat >> 8) & 0xFF),
                               UInt8(pixelFormat & 0xFF))
            print("   Format FourCC: \(fourCC)")
        }
        
        // Check we have texture cache
        guard let textureCache = textureCache else {
            print("❌ No texture cache available - Metal device init failed")
            return
        }
        
        // Get dimensions
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Validate dimensions
        guard width > 0, height > 0 else {
            print("❌ Invalid pixel buffer dimensions: \(width)x\(height)")
            return
        }
        
        // Create Metal texture from pixel buffer using CVMetalTextureCache
        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil, // texture attributes
            .bgra8Unorm, // pixel format
            width,
            height,
            0, // plane index
            &cvMetalTexture
        )
        
        // Check status and provide detailed error info
        guard status == kCVReturnSuccess else {
            print("❌ CVMetalTextureCacheCreateTextureFromImage failed with status: \(status)")
            switch status {
            case kCVReturnInvalidArgument:
                print("   Error: Invalid argument")
            case kCVReturnAllocationFailed:
                print("   Error: Allocation failed")
            case kCVReturnInvalidPixelFormat:
                print("   Error: Invalid pixel format")
            case kCVReturnInvalidPixelBufferAttributes:
                print("   Error: Invalid pixel buffer attributes")
            case kCVReturnPixelBufferNotMetalCompatible:
                print("   Error: Pixel buffer not Metal compatible")
            default:
                print("   Error: Unknown error code \(status)")
            }
            return
        }
        
        guard let cvTexture = cvMetalTexture else {
            print("❌ CVMetalTexture is nil despite success status")
            return
        }
        
        guard let metalTexture = CVMetalTextureGetTexture(cvTexture) else {
            print("❌ Failed to get MTLTexture from CVMetalTexture")
            return
        }
        
        // Get the backing IOSurface for additional info
        guard let ioSurfaceRef = CVPixelBufferGetIOSurface(pixelBuffer) else {
            print("❌ No IOSurface found in pixel buffer for window: \(window.title ?? "Unknown")")
            return
        }
        let surface = ioSurfaceRef.takeUnretainedValue() as IOSurface
        
        print("🎯 DEBUG: IOSurface extracted successfully for \(window.title ?? "Unknown"):")
        print("   Surface dimensions: \(surface.width)x\(surface.height)")
        print("   Surface pixel format: \(surface.pixelFormat)")
        print("   Surface bytes per element: \(surface.bytesPerElement)")
        print("   Surface bytes per row: \(surface.bytesPerRow)")
        print("   Surface element width: \(surface.elementWidth)")
        print("   Surface element height: \(surface.elementHeight)")
        print("   Surface plane count: \(surface.planeCount)")
        print("   Surface allocation size: \(surface.allocationSize)")
        
        // Handle ScreenCaptureKit attachments using proper enum values
        var contentRect: CGRect = .zero
        var contentScale: CGFloat = 1.0
        var scaleFactor: CGFloat = 1.0
        
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let firstAttachment = attachments.first {
            
            // Validate the status of the frame
            if let statusRawValue = firstAttachment[SCStreamFrameInfo.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRawValue),
               status != .complete {
                print("⚠️ Frame not complete for window: \(window.title ?? "Unknown"), status: \(status)")
                return
            }
            
            // Extract content rectangle using proper enum
            if let contentRectDict = firstAttachment[.contentRect],
               let rect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary) {
                contentRect = rect
            }
            
            // Extract content scale and scale factor using proper enums
            if let scale = firstAttachment[.contentScale] as? CGFloat {
                contentScale = scale
            }
            
            if let factor = firstAttachment[.scaleFactor] as? CGFloat {
                scaleFactor = factor
            }
        }
        
        // Log content information on first frame for debugging
        let windowID = window.windowID
        // Track if this is the first frame with an IOSurface for this window
        let isFirstFrame = true  // We'll let AppModel track this now
        
        if isFirstFrame {
            print("📊 First frame info for \(window.title ?? "Unknown"):")
            print("   Pixel buffer size: \(metalTexture.width)x\(metalTexture.height)")
            print("   Content rect: \(contentRect)")
            print("   Content scale: \(contentScale)")
            print("   Scale factor: \(scaleFactor)")
        }
        
        // Notify AppModel with the new Metal texture
        // IMPORTANT: Keep cvTexture alive by passing it along or storing it temporarily
        // The texture will be valid as long as cvTexture is retained
        Task { @MainActor in
            // Pass the texture - cvTexture will be kept alive by ARC until this task completes
            self.onFrameUpdated?(window.windowID, metalTexture, contentRect, contentScale, scaleFactor)
            // cvTexture goes out of scope here and is released after the callback
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
                // Notify AppModel that capture has stopped
                self.onCaptureStopped?(window.windowID)
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
    private var errorCount = 0
    private var lastFrameTime = Date()
    private var droppedFrameCount = 0
    
    init(window: SCWindow, captureManager: WindowCaptureManager) {
        self.window = window
        self.captureManager = captureManager
        super.init()
        print("🎥 StreamOutput initialized for window: \(window.title ?? "Unknown")")
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Validate input parameters
        guard type == .screen else {
            if frameCount == 0 {  // Only log once
                print("⚠️ StreamOutput: Ignoring non-screen output type: \(type)")
            }
            return
        }
        
        guard let window = window else {
            print("❌ StreamOutput: Window reference is nil")
            return
        }
        
        guard let captureManager = captureManager else {
            print("❌ StreamOutput: CaptureManager reference is nil")
            return
        }
        
        // Track frame timing for performance monitoring
        let currentTime = Date()
        let timeSinceLastFrame = currentTime.timeIntervalSince(lastFrameTime)
        lastFrameTime = currentTime
        
        frameCount += 1
        
        // Detect dropped frames (gaps larger than expected frame interval)
        let expectedInterval = 1.0 / 30.0  // 30 FPS
        if timeSinceLastFrame > expectedInterval * 1.5 && frameCount > 1 {
            droppedFrameCount += 1
            if droppedFrameCount % 10 == 1 {  // Log every 10th dropped frame
                print("⚠️ Possible dropped frame detected for \(window.title ?? "Unknown")")
                print("   Time since last frame: \(String(format: "%.3f", timeSinceLastFrame))s")
            }
        }
        
        // Enhanced periodic logging with performance metrics
        if frameCount % 60 == 0 {  // Log every 60 frames (every 2 seconds at 30fps)
            let avgFrameTime = timeSinceLastFrame
            let fps = 1.0 / avgFrameTime
            
            print("📊 StreamOutput stats for '\(window.title ?? "Unknown")':")
            print("   Frames received: \(frameCount)")
            print("   Current FPS: \(String(format: "%.1f", fps))")
            print("   Dropped frames: \(droppedFrameCount)")
            print("   Errors: \(errorCount)")
        }
        
        // Validate sample buffer before processing
        guard CMSampleBufferIsValid(sampleBuffer) else {
            errorCount += 1
            if errorCount % 10 == 1 {  // Log every 10th error
                print("❌ StreamOutput: Invalid sample buffer for \(window.title ?? "Unknown") (error #\(errorCount))")
            }
            return
        }
        
        // Pass to texture update (no try/catch needed as updateTexture doesn't throw)
        captureManager.updateTexture(for: window, with: sampleBuffer)
    }
    
    // Add stream error handling
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ StreamOutput: Stream stopped with error for \(window?.title ?? "Unknown"): \(error)")
        print("   Final stats - Frames: \(frameCount), Errors: \(errorCount), Dropped: \(droppedFrameCount)")
    }
    
    deinit {
        print("🗑️ StreamOutput deallocated for window: \(window?.title ?? "Unknown")")
        print("   Final frame count: \(frameCount), errors: \(errorCount)")
    }
}