//
//  RenderData.swift
//  Depthtop
//
//  Core rendering state manager adapted from CS_HoverEffect
//  for window texture rendering
//

import SwiftUI
import RealityKit
import CompositorServices
import ModelIO
import ARKit
@preconcurrency import MetalKit
import Spatial
import os.log

/// A class that encapsulates the rendering state for the app
actor RenderData {
    
    /// The Metal device for the app
    var device: MTLDevice
    
    /// The command queue for the app
    var queue: MTLCommandQueue

    /// The ARKit session
    let session: ARKitSession?

    /// The world-tracking provider
    let worldTracking = WorldTrackingProvider()
    
    /// The root transform for windows in 3D space
    let rootTransform = simd_float4x4(
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, -2.0, 1]
    )
    
    /// The cache for color textures (for window captures)
    var colorTextureCache = TextureCache()
    
    /// The cache for depth textures
    var depthTextureCache = TextureCache()
    
    /// The command buffer to use for rendering
    var buffer: (any MTLCommandBuffer)?
    
    /// The depth state to use for rendering
    var depthState: (any MTLDepthStencilState)?
    
    /// The pipeline states for different shader constants
    var pStates = [ShaderConstants: MTLRenderPipelineState]()
    
    /// The pipeline state for rendering windows
    var windowPipeline: MTLRenderPipelineState!
    
    /// The pipeline state for handling object indices with MSAA (hover tracking)
    var tileResolvePipeline: TileResolvePipeline?

    weak var _appModel: AppModel?
    
    /// The Compositor Services layer renderer
    let renderer: LayerRenderer
    
    /// The app model
    var appModel: AppModel { 
        guard let model = _appModel else {
            fatalError("AppModel was deallocated")
        }
        return model
    }
    
    /// The time of rendering the last frame
    var lastRenderTime: TimeInterval?
    
    /// The vertex descriptor for window quads
    let vertexDescriptor: MTLVertexDescriptor

    /// Creates a `RenderData` instance
    /// - Parameters:
    ///   - theRenderer: The layer renderer
    ///   - context: The compositor layer context
    ///   - theAppModel: The app model
    init(
        layerRenderer theRenderer: LayerRenderer,
        context: CompositorLayerContext,
        theAppModel: AppModel
    ) {
        #if os(macOS)
        // On macOS, create ARKitSession with the remote device identifier if available
        session = context.remoteDeviceIdentifier.map { ARKitSession(device: $0) }
        #else
        session = ARKitSession()
        #endif

        let device = theRenderer.device
        self.device = device
        queue = device.makeCommandQueue()!
        
        // Set up vertex descriptor for window quads
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
        
        _appModel = theAppModel
        renderer = theRenderer
    }
    
    // MARK: - Mutators and Accessors
    
    /// Performs an update to the render pipeline state dictionary
    /// - Parameters:
    ///   - key: The key to use for storing the pipeline state
    ///   - value: The new render pipeline state
    func updatePipelineState(key: ShaderConstants, value: MTLRenderPipelineState) async {
        pStates[key] = value
    }
    
    /// Returns the depth state
    func getDepthState() -> (any MTLDepthStencilState)? {
        depthState
    }
    
    // MARK: - Initial Setup
    
    /// Sets up the tile resolve pipeline for hover tracking
    func setUpTileResolvePipeline() async {
        guard let model = _appModel else { 
            tileResolvePipeline = nil
            return 
        }
        let withHover = await MainActor.run { model.withHover }
        let useMSAA = await MainActor.run { model.useMSAA }
        if withHover && useMSAA {
            tileResolvePipeline = TileResolvePipeline(device: device, configuration: renderer.configuration)
        } else {
            tileResolvePipeline = nil
        }
    }
    
    /// Performs initial setup of the shader pipeline state object
    func setUpShaderPipeline() async {
        // Create depth stencil state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
        
        // Load the shader library
        guard let library = device.makeDefaultLibrary() else {
            logger.error("[CRITICAL] Failed to create default library for device")
            
            // Try to load from bundle as fallback
            if let bundleURL = Bundle.main.url(forResource: "default-binaryarchive", withExtension: "metallib") {
                logger.info("[DEBUG] Attempting to load metallib from bundle: \(bundleURL)")
                do {
                    let library = try device.makeLibrary(URL: bundleURL)
                    logger.info("[SUCCESS] Loaded metallib from bundle")
                    // Continue with library
                    await setupPipelineWithLibrary(library)
                    return
                } catch {
                    logger.error("[CRITICAL] Failed to load metallib from bundle: \(error)")
                }
            } else {
                logger.error("[CRITICAL] No metallib found in bundle")
            }
            return
        }
        
        await setupPipelineWithLibrary(library)
    }
    
    private func setupPipelineWithLibrary(_ library: MTLLibrary) async {
        // Verify struct sizes match between Swift and Metal
        let swiftSize = MemoryLayout<WindowUniformsArray>.stride  // Use stride for buffer allocation
        let expectedSize = 400  // What Metal expects based on the error
        logger.info("[DEBUG] WindowUniformsArray size: Swift=\(swiftSize), Expected=\(expectedSize)")
        if swiftSize != expectedSize {
            logger.error("[CRITICAL] Size mismatch! Swift struct is \(swiftSize) bytes but Metal expects \(expectedSize) bytes")
        }
        
        // Set up the window rendering pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Window Pipeline"
        
        // Create function constants for shader specialization
        let functionConstants = MTLFunctionConstantValues()
        
        // Set hover effect based on platform (only on visionOS)
        var useHoverEffect = false
        #if os(visionOS)
        useHoverEffect = true
        #endif
        functionConstants.setConstantValue(&useHoverEffect, type: .bool, index: 0) // FunctionConstantHoverEffect
        
        // Set texture array usage based on renderer configuration
        var useTextureArray = renderer.configuration.layout == .layered
        functionConstants.setConstantValue(&useTextureArray, type: .bool, index: 1) // FunctionConstantUseTextureArray
        
        // Set debug colors
        var useDebugColors = false
        #if DEBUG
        if let model = _appModel {
            useDebugColors = await MainActor.run { model.debugColors }
        }
        #endif
        functionConstants.setConstantValue(&useDebugColors, type: .bool, index: 2) // FunctionConstantDebugColors
        
        // Create specialized functions with constants
        guard let vertexFunction = try? await library.makeFunction(name: "windowVertex", constantValues: functionConstants) else {
            logger.error("[CRITICAL] Failed to create specialized windowVertex function")
            return
        }
        guard let fragmentFunction = try? await library.makeFunction(name: "windowFragment", constantValues: functionConstants) else {
            logger.error("[CRITICAL] Failed to create specialized windowFragment function")
            return
        }
        
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = renderer.configuration.colorFormat
        pipelineDescriptor.depthAttachmentPixelFormat = renderer.configuration.depthFormat
        
        // Configure tracking areas attachment for hover effects (if available)
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            if let trackingFormat = renderer.configuration.trackingAreasFormat {
                pipelineDescriptor.colorAttachments[1].pixelFormat = trackingFormat
            }
        }
        #endif
        
        // Configure for stereoscopic rendering (vertex amplification)
        if renderer.configuration.layout == .layered {
            pipelineDescriptor.maxVertexAmplificationCount = 2  // Stereo views
        }
        
        do {
            windowPipeline = try await device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logger.error("Failed to create window pipeline state: \(error)")
        }
        
        logger.info("[SUCCESS] Shader pipeline setup complete")
    }
    
    /// Sets the currently hovered window
    func setHoveredWindow(windowID: CGWindowID) async {
        guard let model = _appModel else { return }
        await MainActor.run {
            model.hoveredWindowID = windowID
            model.hoverProgress = 0.0  // Will animate up
        }
    }
    
    /// Clears the currently hovered window
    func clearHoveredWindow() async {
        guard let model = _appModel else { return }
        await MainActor.run {
            model.hoveredWindowID = nil
            model.hoverProgress = 0.0
        }
    }
    
    /// Handles a tap on a window
    func handleWindowTap(windowID: CGWindowID) async {
        logger.info("Window tapped: \(windowID)")
        // TODO: Implement window interaction (bring to front, maximize, etc.)
    }
    
    /// Checks if the pipeline is ready for rendering
    func isPipelineReady() -> Bool {
        return windowPipeline != nil
    }
    
    /// Sets up world tracking
    func setUpWorldTracking() async {
        guard let session = session else {
            logger.warning("No ARKit session available - world tracking disabled")
            return
        }
        
        do {
            if WorldTrackingProvider.isSupported {
                try await session.run([worldTracking])
                logger.info("World tracking started successfully")
            } else {
                logger.warning("WorldTrackingProvider not supported on this device")
            }
        } catch {
            logger.error("Failed to start world tracking: \(error)")
        }
    }
}

/// Shader constants structure
struct ShaderConstants: Hashable {
    let color: Bool
    let texture: Bool
    let debugColors: Bool
}

/// Texture cache for managing textures
class TextureCache {
    private var textures: [String: MTLTexture] = [:]
    
    func texture(for key: String) -> MTLTexture? {
        return textures[key]
    }
    
    func store(_ texture: MTLTexture, for key: String) {
        textures[key] = texture
    }
    
    func clear() {
        textures.removeAll()
    }
}